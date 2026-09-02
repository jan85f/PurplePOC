# Start: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PurplePOC-1.0.12-proxy-support.ps1
param(
    [string]$Version = "1.0.12",
    [string]$ProjectName = "PurplePOC",

    # Optional HTTP/HTTPS proxy for bootstrap traffic.
    # Example: http://proxy.company.local:8080
    [string]$Proxy
)

$ErrorActionPreference = "Stop"

$Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Join-Path $Base $ProjectName
$Dist = Join-Path $Base "dist"
$Zip  = Join-Path $Dist "$ProjectName-$Version.zip"

Write-Host ""
Write-Host "  PPPP   U   U  RRRR   PPPP   L      EEEEE  PPPP    OOO    CCC " -ForegroundColor Magenta
Write-Host "  P   P  U   U  R   R  P   P  L      E      P   P  O   O  C    " -ForegroundColor Magenta
Write-Host "  PPPP   U   U  RRRR   PPPP   L      EEEE   PPPP   O   O  C    " -ForegroundColor Magenta
Write-Host "  P      U   U  R  R   P      L      E      P      O   O  C    " -ForegroundColor Magenta
Write-Host "  P       UUU   R   R  P      LLLLL  EEEEE  P       OOO    CCC " -ForegroundColor Magenta
Write-Host ""
Write-Host "  Installer / Package Builder" -ForegroundColor Cyan
Write-Host "  by Jan Fischbach" -NoNewline -ForegroundColor DarkGray
Write-Host "  |  " -NoNewline -ForegroundColor DarkGray
Write-Host "v1.0.12" -NoNewline -ForegroundColor Magenta
Write-Host "  |  August 2026" -ForegroundColor DarkGray
Write-Host ""
Write-Host ("=" * 68) -ForegroundColor DarkGray
Write-Host "  Building $ProjectName $Version" -ForegroundColor Cyan
Write-Host ("=" * 68) -ForegroundColor DarkGray
Write-Host ""

if (Test-Path $Root) {
    # Upgrade-safe rebuild:
    # Never destroy installed runtimes, downloaded Atomic content, run history
    # or logs when deploying a newer PurplePOC builder over the same project.
    $PreserveTopLevel = @(
        ".venv",
        "data",
        "reports",
        "logs",
        "tools"
    )

    Write-Host "[+] " -NoNewline -ForegroundColor Cyan
    Write-Host "Upgrade-safe project refresh" -ForegroundColor White

    foreach ($Item in Get-ChildItem -LiteralPath $Root -Force) {
        if ($PreserveTopLevel -contains $Item.Name) {
            Write-Host ("       Preserving: {0}" -f $Item.Name) -ForegroundColor DarkGray
            continue
        }

        Remove-Item `
            -LiteralPath $Item.FullName `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
} else {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

if (-not (Test-Path $Dist)) {
    New-Item -ItemType Directory -Path $Dist -Force | Out-Null
}

if (Test-Path $Zip) {
    Remove-Item $Zip -Force
}

$dirs = @(
    "core",
    "connectors",
    "scenarios",
    "runbooks",
    "tools",
    "tests",
    "reports",
    "data",
    "logs"
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path (Join-Path $Root $d) -Force | Out-Null
}

$ProxyConfigFile = Join-Path $Root "data\proxy.txt"

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    Set-Content -Path $ProxyConfigFile -Value $Proxy -Encoding ASCII
    Write-Host "[+] " -NoNewline -ForegroundColor Cyan
    Write-Host "Proxy configuration saved to data\proxy.txt" -ForegroundColor White
}
elseif (Test-Path $ProxyConfigFile) {
    Write-Host "[+] " -NoNewline -ForegroundColor Cyan
    Write-Host "Existing proxy configuration preserved" -ForegroundColor White
}

function Write-File {
    param(
        [string]$RelativePath,
        [string]$Content
    )

    $Path = Join-Path $Root $RelativePath
    $Parent = Split-Path $Path -Parent

    if (-not (Test-Path $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        [System.Text.UTF8Encoding]::new($false)
    )
}

function Confirm-GeneratedFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RelativePath,
        [switch]$Critical
    )

    $Path = Join-Path $Root $RelativePath

    if (-not (Test-Path $Path -PathType Leaf)) {
        Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
        Write-Host ("Generation failed: {0}" -f $RelativePath) -ForegroundColor Red

        if ($Critical) {
            throw "Required generated file missing immediately after generation: $RelativePath"
        }

        return $false
    }

    $Item = Get-Item $Path -ErrorAction Stop

    if ($Item.Length -le 0) {
        Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
        Write-Host ("Generated file is empty: {0}" -f $RelativePath) -ForegroundColor Red

        if ($Critical) {
            throw "Required generated file is empty: $RelativePath"
        }

        return $false
    }

    $Hash = Get-FileHash `
        -Path $Path `
        -Algorithm SHA256 `
        -ErrorAction Stop

    Write-Host "[PASS] " -NoNewline -ForegroundColor Green
    Write-Host ("Generated {0}" -f $RelativePath) -ForegroundColor White
    Write-Host ("       Size   : {0} bytes" -f $Item.Length) -ForegroundColor DarkGray
    Write-Host ("       SHA256 : {0}" -f $Hash.Hash) -ForegroundColor DarkGray

    return $true
}


# --------------------------------------------------------------------
# VERSION
# --------------------------------------------------------------------

Write-File "VERSION" $Version

# --------------------------------------------------------------------
# requirements.txt
# --------------------------------------------------------------------

Write-File "requirements.txt" @'
pyyaml==6.0.3
rich==13.9.4
requests==2.32.3
pytest==8.3.4
PySide6>=6.10.1,<6.11

'@

# --------------------------------------------------------------------
# config.yaml
# --------------------------------------------------------------------

Write-File "config.yaml" @'
scope:
  domain: corp.local
  attack_hosts:
  - POC-ATTACK01
  domain_controllers:
  - DC01.corp.local
  target_hosts:
  - POC-WIN11-01
  - POC-SRV01
execution:
  default_scenario: full
  cleanup: true
cleanup:
  enabled: true
  retry_pending_at_end: true
  retain_framework: true
  write_summary: true
console:
  show_command_output: true
  atomic_compact_output: true
  output_preview_max_lines: 10
  output_preview_max_chars: 2500
  error_preview_max_lines: 6
  error_preview_max_chars: 2000
atomic:
  enabled: true
  install_scope: CurrentUser
  auto_get_prereqs: true
  cleanup_after_test: true
  tests:
  - technique: T1059.001
    guid: a538de64-1c74-46ed-aa60-b995ed302598
    name: PowerShell Command Execution
  - technique: T1053.005
    guid: 42f53695-ad4a-4546-abb6-7d837f644a71
    name: Scheduled task Local
  - technique: T1547.001
    guid: e55be3fd-3521-4610-9d1a-e210e42dcf05
    name: Reg Key Run
  - technique: T1543.003
    guid: 981e2942-e433-44e9-afc1-8c957a1496b6
    name: Service Installation CMD
  - technique: T1047
    guid: b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3
    name: WMI Execute Local Process
  - technique: T1057
    guid: c5806a4f-62b8-4900-980b-c7ec004e9908
    name: Process Discovery - tasklist
  - technique: T1082
    guid: 66703791-c902-4560-8770-42b8a91f7667
    name: System Information Discovery
  - technique: T1012
    guid: 8f7578c4-9863-4d83-875c-a565573bbdf0
    name: Query Registry
  - technique: T1055.004
    guid: 611b39b7-e243-4c81-87a4-7145a90358b1
    name: Process Injection via C#
  - technique: T1218.010
    guid: 449aa403-6aba-47ce-8a37-247d21ef0306
    name: Regsvr32 local COM scriptlet execution
  - technique: T1218.008
    guid: 2430498b-06c0-4b92-a448-8ad263c388e2
    name: Odbcconf.exe - Execute Arbitrary DLL
  - technique: T1112
    guid: 1324796b-d0f6-455a-b4ae-21ffee6aa6b9
    name: Modify Registry of Current User Profile - cmd
  - technique: T1218.005
    guid: c4b97eeb-5249-4455-a607-59f95485cb45
    name: MSHTA Remote HTA Download + Execute
  - technique: T1218.005
    guid: 8707a805-2b76-4f32-b1c0-14e558205772
    name: MSHTA Proxy Execute PowerShell
  - technique: T1218.010
    guid: c9d0c4ef-8a96-4794-a75b-3d3a5e6f2a36
    name: Regsvr32 Remote COM Scriptlet
  - technique: T1218.011
    guid: 57ba4ce9-ee7a-4f27-9928-3c70c489b59d
    name: Rundll32 Remote Script Proxy Execution
  - technique: T1218.011
    guid: 32d1cf1b-cbc2-4c09-8d05-07ec5c83a821
    name: Rundll32 VBScript Proxy Execution
  - technique: T1218.003
    guid: 34e63321-9683-496b-bbc1-7566bc55e624
    name: CMSTP Remote Scriptlet Execution
  - technique: T1218.001
    guid: 0f8af516-9818-4172-922b-42986ef1e81d
    name: HH.exe Remote CHM Execution
  - technique: T1218.003
    guid: 748cb4f6-2fb3-4e97-b7ad-b22635a09ab0
    name: CMSTP UAC Bypass
  - technique: T1053.005
    guid: fec27f65-db86-4c2d-b66c-61945aee87c2
    name: Scheduled Task Startup as SYSTEM
  - technique: T1021.002
    guid: d41aaab5-bdfe-431d-a3d5-c29e9136ff46
    name: Local ADMIN$ Command Output
  - technique: T1021.002
    guid: 0eb03d41-79e4-4393-8e57-6344856be1cf
    name: PsExec Copy + Execute on Localhost
  - technique: T1047
    guid: 00738d2a-4651-4d76-adf2-c43a41dfb243
    name: WMI Remote Process via Loopback
  - technique: T1218.005
    guid: b8a8bdb2-7eae-490d-8251-d5e0295b2362
    name: MSHTA UNC Lateral Movement Simulation
  - technique: T1685.001
    guid: b26a3340-dad7-4360-9176-706269c74103
    name: Disable Windows Event Log Channel
  - technique: T1685.001
    guid: 8e81d090-0cd6-4d46-863c-eec11311298f
    name: Modify Event Log Channel Permissions
  - technique: T1685.005
    guid: e6abb60e-26b8-41da-8aae-0c35174b0967
    name: Clear Windows Event Log
telemetry:
  before_seconds: 10
  after_seconds: 60
connectors:
  qradar:
    enabled: false
    host: https://qradar.example.local
    token_env: QRADAR_TOKEN
    verify_ssl: false
  mde:
    enabled: false
  crowdstrike:
    enabled: false
  cortex:
    enabled: false

'@

# --------------------------------------------------------------------
# tools/manifest.yaml
# --------------------------------------------------------------------

Write-File "tools\manifest.yaml" @'
tools:

  rubeus:
    mode: guided
    distribution: operator_staged
    source_url: https://github.com/GhostPack/Rubeus
    expected_path: tools/rubeus/Rubeus.exe
    help: "Place the approved Rubeus build at this path. PurplePOC records version/hash and opens the folder during the GUIDED step; use the approved runbook for the actual test."

  mimikatz:
    mode: guided
    distribution: operator_staged
    source_url: https://github.com/gentilkiwi/mimikatz
    expected_path: tools/mimikatz/mimikatz.exe
    help: "Place the engagement-approved build at this path. PurplePOC does not invoke credential-dumping commands automatically."

  secretsdump:
    mode: guided
    distribution: operator_staged
    source_url: https://github.com/fortra/impacket
    expected_path: tools/impacket/secretsdump.py
    help: "Stage the approved Impacket tool here if your runbook requires it. PurplePOC only validates/stages evidence around the operator-run action."

  certipy:
    mode: guided
    distribution: public_verified
    source_url: https://github.com/ly4k/Certipy
    install_type: python_package
    package: certipy-ad
    expected_path: runtime:venv/Scripts/certipy.exe
    help: "PurplePOC installs Certipy into its private venv. Use only the approved engagement runbook for any privileged ADCS action."

  seatbelt:
    mode: guided
    distribution: operator_staged
    source_url: https://github.com/GhostPack/Seatbelt
    expected_path: tools/seatbelt/Seatbelt.exe
    help: "Stage the approved Seatbelt binary here. Use it for host/security-context assessment according to the test plan."

  sharpup:
    mode: guided
    distribution: operator_staged
    source_url: https://github.com/GhostPack/SharpUp
    expected_path: tools/sharpup/SharpUp.exe
    help: "Stage the approved SharpUp binary here. Use audit-oriented checks according to the test plan."

  atomic_red_team:
    mode: auto_allowlisted
    distribution: public_verified
    source_project: redcanaryco/atomic-red-team
    install_type: invoke_atomic_installer
    expected_path: tools/atomic-red-team
    help: "Installed automatically from the official Red Canary project. PurplePOC executes only techniques in config.yaml atomic.allowlist."

  invoke_atomicredteam:
    mode: auto_allowlisted
    distribution: public_verified
    source_project: redcanaryco/invoke-atomicredteam
    install_type: powershell_module
    expected_module: invoke-atomicredteam
    help: "Installed automatically from PowerShell Gallery and used as the execution backend for allowlisted Atomic Red Team tests."

  purplesharp:
    mode: auto_allowlisted
    distribution: public_verified
    source_project: mvelazc0/PurpleSharp
    expected_path: tools/purplesharp/PurpleSharp.exe

  sysinternals:
    mode: support
    distribution: public_verified
    source_vendor: Microsoft
    expected_path: tools/sysinternals
'@

# --------------------------------------------------------------------
# scenarios/full.yaml
# --------------------------------------------------------------------

Write-File "scenarios\full.yaml" @'
name: Full Domain Detection Validation
steps:
- id: whoami
  name: Account Context
  technique: T1033
  tactic: discovery
  mode: auto
  action: whoami
  description: Runs `whoami.exe /all`. The test records the current user, SID, group memberships, privileges, integrity-related token information and authentication context visible to
    the process.
  siem_rule:
    event_ids: &id001
    - '4688'
    - Sysmon 1
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `whoami.exe /all` and captures its stdout.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate detections for account/context discovery and give the analyst the exact identity and privilege context used by the remaining tests.
    implementation: 'PurplePOC native action: whoami'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: &id002
    endpoint:
    - Windows 4688
    - Sysmon 1
    - PowerShell 4104
    ad_dc:
    - Directory Service 4662 where SACL/auditing permits
    - LDAP/DC diagnostics where enabled
    network:
    - Firewall/NDR metadata for LDAP/SMB/WMI connections to DCs/targets
    application:
    - AD/LDAP logs where available
    correlation: Correlate unusual enumeration process + user + source host with broad/repeated directory or system queries in a short window. Increase risk when multiple discovery techniques
      occur sequentially.
    enrichment:
    - Process image
    - CommandLine
    - User
    - Parent process
    - Source host
    - Destination/DC
    protocols_ports:
    - 'LDAP: TCP/UDP 389'
    - 'LDAPS: TCP 636'
    - 'Global Catalog: TCP 3268; GC over TLS: TCP 3269 (when GC is used)'
    - Authentication may additionally use Kerberos TCP/UDP 88 depending on the logged-on context
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4662, Sysmon 1, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Performs a paged, read-only LDAP computer-object search and prints hostnames only.'
      - '3. If network activity is relevant, filter source -> destination using: LDAP: TCP/UDP 389; LDAPS: TCP 636; Global Catalog: TCP 3268; GC over TLS: TCP 3269 (when GC is used);
        Authentication may additionally use Kerberos TCP/UDP 88 depending on the logged-on context'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Correlate unusual enumeration process + user + source host with broad/repeated directory or system queries in a short window. Increase
        risk when multiple discovery techniques occur sequentially.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Process image
      - CommandLine
      - User
      - Parent process
      - Source host
      - Destination/DC
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: systeminfo
  name: System Information Discovery
  technique: T1082
  tactic: discovery
  mode: auto
  action: systeminfo
  description: Runs `systeminfo.exe` to query the local Windows host for OS version/build, system manufacturer/model, boot time, memory, hotfix and domain/workgroup information.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `systeminfo.exe` locally and captures the returned host inventory.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate host-information discovery telemetry and provide OS/build context for interpreting later detections.
    implementation: 'PurplePOC native action: systeminfo'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: network
  name: Network Configuration Discovery
  technique: T1016
  tactic: discovery
  mode: auto
  action: ipconfig
  description: Runs `ipconfig.exe /all` and records adapters, IPv4/IPv6 addresses, gateways, DNS servers, DHCP state, DNS suffixes and MAC-related interface information.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `ipconfig.exe /all` on the tested endpoint.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate network-configuration discovery and give the analyst the endpoint's addressing, resolver and interface context.
    implementation: 'PurplePOC native action: ipconfig'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: trusts
  name: Domain Trust Discovery
  technique: T1482
  tactic: discovery
  mode: auto
  action: domain_trusts
  description: Runs `nltest.exe /domain_trusts` to ask Windows for the domain trusts visible to the current host/session.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `nltest.exe /domain_trusts` and captures the returned trust relationships.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate domain-trust discovery telemetry and identify which trust relationships would be visible to an attacker from this host.
    implementation: 'PurplePOC native action: domain_trusts'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: process_discovery
  name: Process Discovery
  technique: T1057
  tactic: discovery
  mode: auto
  action: process_discovery
  description: Runs `tasklist.exe /V` to enumerate running processes together with PID, session, memory and verbose process/session information.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `tasklist.exe /V` and captures the complete visible process list.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate process-discovery telemetry and show which running applications/security processes are observable from the test context.
    implementation: 'PurplePOC native action: process_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: service_discovery
  name: Service Discovery
  technique: T1007
  tactic: discovery
  mode: auto
  action: service_discovery
  description: Runs `sc.exe query type= service state= all` to enumerate Windows services and their current states.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes the Service Control Manager query for all services and captures service names/states.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate service-discovery telemetry and provide service inventory context for persistence and defense-evasion analysis.
    implementation: 'PurplePOC native action: service_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: account_discovery
  name: Domain Account Discovery
  technique: T1087.002
  tactic: discovery
  mode: auto
  action: account_discovery
  description: Runs `net.exe user /domain` to request the domain user list using the current Windows domain context.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `net.exe user /domain`; on a non-domain-joined or unreachable-domain host the command is expected to fail and that failure is evidence.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate domain-account discovery and distinguish successful AD enumeration from hosts that lack usable domain context.
    implementation: 'PurplePOC native action: account_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: group_discovery
  name: Domain Group Discovery
  technique: T1069.002
  tactic: discovery
  mode: auto
  action: group_discovery
  description: Runs `net.exe group /domain` to enumerate domain groups visible to the current Windows session.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `net.exe group /domain` and captures returned domain group names or the domain-context error.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate domain-group discovery, especially unusual enumeration from workstations or non-administrative user sessions.
    implementation: 'PurplePOC native action: group_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: dc_discovery
  name: Domain Controller Discovery
  technique: T1018
  tactic: discovery
  mode: auto
  action: dc_discovery
  description: Runs `nltest.exe /dclist:` to request a list of domain controllers for the current domain context.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `nltest.exe /dclist:` and captures the discovered DC names/addresses or the domain-context failure.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate domain-controller discovery and identify the DCs an attacker could select for subsequent LDAP/Kerberos/RPC activity.
    implementation: 'PurplePOC native action: dc_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: share_discovery
  name: Network Share Discovery
  technique: T1135
  tactic: discovery
  mode: auto
  action: share_discovery
  description: Runs `net.exe view` to enumerate computers/resources exposed through Windows network browsing and share discovery mechanisms.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `net.exe view` and captures visible network systems/shares or the browsing/domain error.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate network-share discovery and provide context for later SMB/admin-share lateral-movement tests.
    implementation: 'PurplePOC native action: share_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: netstat
  name: System Network Connections Discovery
  technique: T1049
  tactic: discovery
  mode: auto
  action: netstat
  description: Runs `netstat.exe -ano` to list active/listening TCP/UDP endpoints with local/remote addresses and owning process IDs.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `netstat.exe -ano` and captures the endpoint connection/listener table.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate system-network-connection discovery and let the analyst correlate sockets back to process IDs.
    implementation: 'PurplePOC native action: netstat'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: arp
  name: Local Neighbor Discovery
  technique: T1016
  tactic: discovery
  mode: auto
  action: arp
  description: Runs `arp.exe -a` to read the local ARP/neighbor cache and expose recently resolved IPv4 neighbors and their MAC addresses.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `arp.exe -a` and captures the current neighbor cache.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate local-neighbor discovery and show which nearby systems have recently communicated at layer 2.
    implementation: 'PurplePOC native action: arp'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: dns_cache
  name: DNS Cache Discovery
  technique: T1016
  tactic: discovery
  mode: auto
  action: dns_cache
  description: Runs `ipconfig.exe /displaydns` to dump the Windows DNS client resolver cache, including recently resolved names and cached record data.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `ipconfig.exe /displaydns` and captures cached DNS entries.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate DNS-cache discovery and demonstrate how recent user/system destinations can be learned without generating new DNS queries.
    implementation: 'PurplePOC native action: dns_cache'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: firewall_discovery
  name: Windows Firewall Discovery
  technique: T1016
  tactic: discovery
  mode: auto
  action: firewall_discovery
  description: Runs PowerShell `Get-NetFirewallProfile` and reads each profile's enabled state plus default inbound/outbound action.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Executes `Get-NetFirewallProfile | Format-List Name,Enabled,DefaultInboundAction,DefaultOutboundAction`.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate Windows Firewall discovery and provide the effective profile posture relevant to later network tests.
    implementation: 'PurplePOC native action: firewall_discovery'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id002
- id: atomic_process_discovery
  name: Atomic Process Discovery
  technique: T1057
  tactic: discovery
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1057
  atomic_guid: c5806a4f-62b8-4900-980b-c7ec004e9908
  description: Invokes Atomic Red Team T1057 test GUID `c5806a4f-62b8-4900-980b-c7ec004e9908` to perform the Atomic project's process-discovery behavior.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Runs `Invoke-AtomicTest T1057 -TestGuids c5806a4f-62b8-4900-980b-c7ec004e9908` and captures the Atomic output/cleanup result.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate the SIEM rule against a standardized Atomic process-discovery pattern in addition to PurplePOC's native `tasklist` test.
    implementation: Atomic Red Team T1057 / GUID c5806a4f-62b8-4900-980b-c7ec004e9908
    command: Invoke-AtomicTest T1057 -TestGuids c5806a4f-62b8-4900-980b-c7ec004e9908
  detection_sources: *id002
- id: atomic_system_information
  name: Atomic System Information Discovery
  technique: T1082
  tactic: discovery
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1082
  atomic_guid: 66703791-c902-4560-8770-42b8a91f7667
  description: Invokes Atomic Red Team T1082 test GUID `66703791-c902-4560-8770-42b8a91f7667` to perform the Atomic project's system-information discovery behavior.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Runs `Invoke-AtomicTest T1082 -TestGuids 66703791-c902-4560-8770-42b8a91f7667` and captures its telemetry.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate system-information discovery against a repeatable Atomic implementation rather than only `systeminfo.exe`.
    implementation: Atomic Red Team T1082 / GUID 66703791-c902-4560-8770-42b8a91f7667
    command: Invoke-AtomicTest T1082 -TestGuids 66703791-c902-4560-8770-42b8a91f7667
  detection_sources: *id002
- id: atomic_registry_query
  name: Atomic Registry Query
  technique: T1012
  tactic: discovery
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1012
  atomic_guid: 8f7578c4-9863-4d83-875c-a565573bbdf0
  description: Invokes Atomic Red Team T1012 test GUID `8f7578c4-9863-4d83-875c-a565573bbdf0` to query Windows Registry data using the Atomic-defined test.
  siem_rule:
    event_ids: *id001
    logic: Alert on uncommon discovery commands or bursts of enumeration from unusual users/process parents.
  execution_details:
    process: Technique-dependent process / Atomic Red Team launcher
    input: Local host, account, network or domain context
    operation: Runs `Invoke-AtomicTest T1012 -TestGuids 8f7578c4-9863-4d83-875c-a565573bbdf0` and records the resulting registry/process telemetry.
    destination: Local stdout / Windows telemetry
    network: Technique-dependent; often none
    artifacts: Process creation and command-line telemetry; technique-specific query activity
    purpose: Validate detection of registry-based discovery from the exact Atomic T1012 test.
    implementation: Atomic Red Team T1012 / GUID 8f7578c4-9863-4d83-875c-a565573bbdf0
    command: Invoke-AtomicTest T1012 -TestGuids 8f7578c4-9863-4d83-875c-a565573bbdf0
  detection_sources: *id002
- id: powershell
  name: PowerShell
  technique: T1059.001
  tactic: execution
  mode: auto
  action: powershell
  description: Starts `powershell.exe` with PurplePOC's local test command. The default command reads the computer name and current date, creating a real PowerShell process and command
    line without changing the system.
  siem_rule:
    event_ids: &id003
    - '4688'
    - Sysmon 1
    - PowerShell 4104
    logic: IF powershell.exe starts with an unusual command line, uncommon parent process, encoded/scripted content, or unexpected user context THEN alert; enrich with PowerShell 4104
      and Sysmon 1/4688.
  execution_details:
    process: powershell.exe
    input: PurplePOC controlled local command
    operation: Executes `powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command <PurplePOC test command>`.
    destination: Local host
    network: No network connection is required by this exact test.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate PowerShell process creation, command-line logging and script telemetry using a harmless command that is easy to correlate in the SIEM.
    implementation: 'PurplePOC native action: powershell'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: &id004
    endpoint:
    - Windows 4688
    - Sysmon 1
    - PowerShell 4104 where applicable
    ad_dc: []
    network:
    - Firewall/NDR if the execution technique creates network traffic
    application: []
    correlation: IF hh.exe accesses a remote URL/share OR spawns an unusual child process outside normal help usage THEN alert; enrich with destination reputation/rarity.
    enrichment:
    - Image
    - CommandLine
    - ParentImage
    - User
    - IntegrityLevel
    - ProcessGuid
    protocols_ports:
    - 'HTTP: TCP 80'
    - 'HTTPS/TLS: TCP 443'
    - Exact destination/port depends on the Atomic test payload URL
    analyst_recipe:
      time_window: 60 seconds
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, Sysmon 1, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Runs the exact Atomic HH.exe remote-CHM test and captures `hh.exe`, content retrieval and resulting child execution
        telemetry.'
      - '3. If network activity is relevant, filter source -> destination using: HTTP: TCP 80; HTTPS/TLS: TCP 443; Exact destination/port depends on the Atomic test payload URL'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply this SIEM correlation: IF hh.exe accesses a remote URL/share OR spawns an unusual child process outside normal help usage THEN alert; enrich with destination reputation/rarity.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Image
      - CommandLine
      - ParentImage
      - User
      - IntegrityLevel
      - ProcessGuid
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: wmi
  name: WMI
  technique: T1047
  tactic: execution
  mode: auto
  action: wmi
  description: Runs `wmic.exe process call create "cmd.exe /c exit 0"`. WMI asks the local `Win32_Process` provider to create a short-lived `cmd.exe` process that immediately exits.
  siem_rule:
    event_ids: *id003
    logic: IF an unusual process/user initiates WMI execution AND WMI provider activity or a child process appears within 60 seconds THEN alert; increase severity for remote source context.
  execution_details:
    process: powershell.exe / WMI provider
    input: Local WMI execution request
    operation: Executes local WMI process creation through `wmic.exe`; the child command is `cmd.exe /c exit 0`.
    destination: Local WMI provider on the tested endpoint
    network: 'Local test: no remote TCP 135/dynamic RPC connection. Remote WMI would use TCP 135 plus dynamic RPC TCP 49152-65535.'
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate T1047 by correlating the WMI/WMIC initiator, WMI provider activity and the created `cmd.exe` process. No remote host is contacted in this test.
    implementation: 'PurplePOC native action: wmi'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id004
- id: atomic_powershell
  name: Atomic PowerShell Execution
  technique: T1059.001
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1059.001
  atomic_guid: a538de64-1c74-46ed-aa60-b995ed302598
  description: Invokes Atomic Red Team T1059.001 GUID `a538de64-1c74-46ed-aa60-b995ed302598`. PurplePOC records the Atomic-defined PowerShell command, process tree, script telemetry
    and cleanup result.
  siem_rule:
    event_ids: *id003
    logic: Correlate Invoke-AtomicTest/PowerShell parentage with 4688, Sysmon 1 and PowerShell 4104. Alert on suspicious PowerShell syntax, encoded content, unusual parents or unexpected
      user context.
  execution_details:
    process: powershell.exe launched by Invoke-AtomicTest
    input: Atomic Red Team T1059.001 test definition
    operation: Runs `Invoke-AtomicTest T1059.001 -TestGuids a538de64-1c74-46ed-aa60-b995ed302598`.
    destination: Local host
    network: Technique/test dependent; this selected execution test is primarily endpoint-focused.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate the PowerShell detection against the exact Atomic T1059.001 test rather than an abstract 'PowerShell activity' condition.
    implementation: Atomic Red Team T1059.001 / GUID a538de64-1c74-46ed-aa60-b995ed302598
    command: Invoke-AtomicTest T1059.001 -TestGuids a538de64-1c74-46ed-aa60-b995ed302598
  detection_sources: *id004
- id: atomic_wmi
  name: Atomic WMI
  technique: T1047
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1047
  atomic_guid: b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3
  description: Invokes Atomic Red Team T1047 GUID `b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3`. The Atomic definition performs its WMI execution behavior and PurplePOC captures the generated
    process/WMI telemetry.
  siem_rule:
    event_ids: *id003
    logic: IF WMI execution occurs from an uncommon parent/user AND a child process is created by WMI/provider context within 60 seconds THEN alert.
  execution_details:
    process: Atomic launcher -> WMI provider / spawned process
    input: Atomic Red Team T1047 test definition
    operation: Runs `Invoke-AtomicTest T1047 -TestGuids b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3`.
    destination: Local host in this Atomic test
    network: Local execution in this scenario. Remote WMI equivalents use TCP 135 plus dynamic RPC TCP 49152-65535.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate WMI execution detection using the exact Atomic test identified by GUID and correlate its initiating process with WMI/provider and child-process telemetry.
    implementation: Atomic Red Team T1047 / GUID b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3
    command: Invoke-AtomicTest T1047 -TestGuids b3bdfc91-b33e-4c6d-a5c8-d64bee0276b3
  detection_sources: *id004
- id: atomic_mshta_remote_hta
  name: MSHTA Remote HTA Download + Execute
  technique: T1218.005
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.005
  atomic_guid: c4b97eeb-5249-4455-a607-59f95485cb45
  description: Invokes Atomic Red Team T1218.005 GUID `c4b97eeb-5249-4455-a607-59f95485cb45`. The test starts `mshta.exe`, obtains HTA content from the Atomic test location and executes
    the HTA script content through the signed Windows binary.
  siem_rule:
    event_ids: *id003
    logic: IF mshta.exe starts AND makes HTTP/HTTPS access or launches script/interpreter child activity within 60 seconds THEN alert; increase severity for rare destination or unusual
      parent.
  execution_details:
    process: mshta.exe
    input: Atomic Red Team remote HTA test content/URL
    operation: Runs the specified Atomic MSHTA remote-HTA test and captures `mshta.exe`, command-line, child-process and HTTP/HTTPS telemetry.
    destination: Atomic test URL defined by the selected test
    network: HTTP TCP 80 or HTTPS TCP 443 depending on the Atomic test URL.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate detection of `mshta.exe` acting as a signed proxy for remotely sourced script execution.
    implementation: Atomic Red Team T1218.005 / GUID c4b97eeb-5249-4455-a607-59f95485cb45
    command: Invoke-AtomicTest T1218.005 -TestGuids c4b97eeb-5249-4455-a607-59f95485cb45
  detection_sources: *id004
- id: atomic_mshta_powershell
  name: MSHTA Proxy Execute PowerShell
  technique: T1218.005
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.005
  atomic_guid: 8707a805-2b76-4f32-b1c0-14e558205772
  description: Invokes Atomic Red Team T1218.005 GUID `8707a805-2b76-4f32-b1c0-14e558205772`. The test uses `mshta.exe` in a process chain that results in PowerShell execution.
  siem_rule:
    event_ids: *id003
    logic: IF mshta.exe creates powershell.exe OR another script interpreter AND the parent/user combination is uncommon THEN alert; enrich with network destination if remote content
      is retrieved.
  execution_details:
    process: mshta.exe -> powershell.exe
    input: Atomic Red Team T1218.005 proxy-execution test
    operation: Runs the specified Atomic MSHTA-to-PowerShell test and records the `mshta.exe` -> PowerShell execution chain.
    destination: Local host; remote content may be used by the mapped Atomic definition
    network: 'If remote content is used: HTTP TCP 80 / HTTPS TCP 443.'
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate a high-signal LOLBin-to-script-interpreter parent/child relationship.
    implementation: Atomic Red Team T1218.005 / GUID 8707a805-2b76-4f32-b1c0-14e558205772
    command: Invoke-AtomicTest T1218.005 -TestGuids 8707a805-2b76-4f32-b1c0-14e558205772
  detection_sources: *id004
- id: atomic_regsvr32_remote
  name: Regsvr32 Remote COM Scriptlet
  technique: T1218.010
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.010
  atomic_guid: c9d0c4ef-8a96-4794-a75b-3d3a5e6f2a36
  description: Invokes Atomic Red Team T1218.010 GUID `c9d0c4ef-8a96-4794-a75b-3d3a5e6f2a36`. The test starts `regsvr32.exe` with the Atomic remote COM-scriptlet parameters.
  siem_rule:
    event_ids: *id003
    logic: IF regsvr32.exe contains scriptlet/proxy-execution arguments or accesses a remote HTTP(S) destination THEN alert; increase severity for uncommon parent/user or rare domain.
  execution_details:
    process: regsvr32.exe
    input: Atomic Red Team remote COM scriptlet definition
    operation: Runs the exact Atomic Regsvr32 remote-scriptlet test and captures command-line plus any network/scriptlet telemetry.
    destination: Atomic test scriptlet location
    network: Typically HTTP TCP 80 / HTTPS TCP 443 when the scriptlet is remote.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate Regsvr32 signed-binary proxy execution, especially scriptlet-related arguments and remote content access.
    implementation: Atomic Red Team T1218.010 / GUID c9d0c4ef-8a96-4794-a75b-3d3a5e6f2a36
    command: Invoke-AtomicTest T1218.010 -TestGuids c9d0c4ef-8a96-4794-a75b-3d3a5e6f2a36
  detection_sources: *id004
- id: atomic_rundll32_remote
  name: Rundll32 Remote Script Proxy Execution
  technique: T1218.011
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.011
  atomic_guid: 57ba4ce9-ee7a-4f27-9928-3c70c489b59d
  description: Invokes Atomic Red Team T1218.011 GUID `57ba4ce9-ee7a-4f27-9928-3c70c489b59d`. The Atomic definition starts `rundll32.exe` with its remote script-proxy arguments.
  siem_rule:
    event_ids: *id003
    logic: IF rundll32.exe is launched with unusual script/protocol handlers or remote content AND the behavior is not baseline for the host THEN alert; correlate process and network
      telemetry.
  execution_details:
    process: rundll32.exe
    input: Atomic Red Team T1218.011 remote proxy-execution definition
    operation: Runs the exact Atomic Rundll32 remote-proxy test and captures the resulting process, command line and network activity defined by that Atomic test.
    destination: Atomic test remote content location
    network: HTTP TCP 80 / HTTPS TCP 443 when remote content is retrieved.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate abnormal `rundll32.exe` use where its command line and remote-content behavior differ from normal DLL invocation.
    implementation: Atomic Red Team T1218.011 / GUID 57ba4ce9-ee7a-4f27-9928-3c70c489b59d
    command: Invoke-AtomicTest T1218.011 -TestGuids 57ba4ce9-ee7a-4f27-9928-3c70c489b59d
  detection_sources: *id004
- id: atomic_rundll32_vbscript
  name: Rundll32 VBScript Proxy Execution
  technique: T1218.011
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.011
  atomic_guid: 32d1cf1b-cbc2-4c09-8d05-07ec5c83a821
  description: Invokes Atomic Red Team T1218.011 GUID `32d1cf1b-cbc2-4c09-8d05-07ec5c83a821`. The test uses `rundll32.exe` in the Atomic VBScript proxy-execution pattern.
  siem_rule:
    event_ids: *id003
    logic: IF rundll32.exe command line contains script-proxy indicators OR creates/coordinates with a script engine from an unusual parent/user THEN alert.
  execution_details:
    process: rundll32.exe / script execution chain
    input: Atomic Red Team VBScript proxy-execution test
    operation: Runs the exact Atomic Rundll32/VBScript test and records the command line and associated script-execution process chain.
    destination: Local host
    network: No network connection is required unless the Atomic definition references remote content.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate Rundll32 used as a script proxy rather than for ordinary DLL entry-point execution.
    implementation: Atomic Red Team T1218.011 / GUID 32d1cf1b-cbc2-4c09-8d05-07ec5c83a821
    command: Invoke-AtomicTest T1218.011 -TestGuids 32d1cf1b-cbc2-4c09-8d05-07ec5c83a821
  detection_sources: *id004
- id: atomic_cmstp_remote
  name: CMSTP Remote Scriptlet Execution
  technique: T1218.003
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.003
  atomic_guid: 34e63321-9683-496b-bbc1-7566bc55e624
  description: Invokes Atomic Red Team T1218.003 GUID `34e63321-9683-496b-bbc1-7566bc55e624`. The test starts `cmstp.exe` with the Atomic profile/scriptlet content used for proxy execution.
  siem_rule:
    event_ids: *id003
    logic: IF cmstp.exe starts outside approved software/network-profile deployment AND has suspicious arguments or remote content access THEN alert.
  execution_details:
    process: cmstp.exe
    input: Atomic Red Team T1218.003 test content
    operation: Runs the exact Atomic CMSTP remote-scriptlet test and captures CMSTP process, arguments and any remote-resource activity.
    destination: Local host; selected Atomic content can reference a remote resource
    network: 'If remote content is used: HTTP TCP 80 / HTTPS TCP 443.'
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate suspicious use of Connection Manager Profile Installer outside expected profile deployment.
    implementation: Atomic Red Team T1218.003 / GUID 34e63321-9683-496b-bbc1-7566bc55e624
    command: Invoke-AtomicTest T1218.003 -TestGuids 34e63321-9683-496b-bbc1-7566bc55e624
  detection_sources: *id004
- id: atomic_hh_remote
  name: HH.exe Remote CHM Execution
  technique: T1218.001
  tactic: execution
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.001
  atomic_guid: 0f8af516-9818-4172-922b-42986ef1e81d
  description: Invokes Atomic Red Team T1218.001 GUID `0f8af516-9818-4172-922b-42986ef1e81d`. The test starts `hh.exe` against the Atomic remote CHM/help content.
  siem_rule:
    event_ids: *id003
    logic: IF hh.exe accesses a remote URL/share OR spawns an unusual child process outside normal help usage THEN alert; enrich with destination reputation/rarity.
  execution_details:
    process: hh.exe
    input: Atomic Red Team remote CHM test
    operation: Runs the exact Atomic HH.exe remote-CHM test and captures `hh.exe`, content retrieval and resulting child execution telemetry.
    destination: Atomic test CHM/help location
    network: HTTP TCP 80 / HTTPS TCP 443 when the CHM/help content is remote.
    artifacts: Process creation, command line, parent/child telemetry; script, WMI and network telemetry where applicable
    purpose: Validate remote CHM/HTML Help proxy execution from a Windows binary that is rarely expected to fetch remote executable content.
    implementation: Atomic Red Team T1218.001 / GUID 0f8af516-9818-4172-922b-42986ef1e81d
    command: Invoke-AtomicTest T1218.001 -TestGuids 0f8af516-9818-4172-922b-42986ef1e81d
  detection_sources: *id004
- id: scheduled_task
  name: Scheduled Task
  technique: T1053.005
  tactic: persistence
  mode: auto
  action: scheduled_task
  description: Creates a one-time task named `PurplePOC_<random>` with `schtasks.exe`. The task action is `cmd.exe /c exit 0`; PurplePOC starts the task and then deletes it.
  siem_rule:
    event_ids: &id005
    - '4688'
    - 4698/4702
    - '7045'
    - Sysmon 1,12,13
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `schtasks /Create`, `schtasks /Run`, then `schtasks /Delete` for the temporary PurplePOC task.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate scheduled-task creation/execution/deletion telemetry without leaving persistent payloads behind.
    implementation: 'PurplePOC native action: scheduled_task'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: &id006
    endpoint:
    - Windows 4688
    - 4698/4702 scheduled task
    - 7045/4697 service
    - Sysmon 1/12/13
    ad_dc:
    - 5136 if AD-backed persistence objects are modified
    network: []
    application: []
    correlation: Alert when persistence configuration is created or changed by an unusual user/process; correlate with the initiating process and target object.
    enrichment:
    - User
    - Process
    - Task/service/registry object
    - Target host
    protocols_ports: &id013
    - Local host only - no network port expected from this exact test
    analyst_recipe:
      time_window: 2 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4698/4702, 7045, Sysmon 1,12,13.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Runs `Invoke-AtomicTest T1543.003 -TestGuids 981e2942-e433-44e9-afc1-8c957a1496b6` and records service creation/execution/cleanup
        telemetry.'
      - '3. If network activity is relevant, filter source -> destination using: Local host only - no network port expected from this exact test'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Alert when persistence configuration is created or changed by an unusual user/process; correlate with the initiating process and target
        object.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - User
      - Process
      - Task/service/registry object
      - Target host
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: run_key
  name: Registry Run Key
  technique: T1547.001
  tactic: persistence
  mode: auto
  action: run_key
  description: Adds a temporary value named `PurplePOC_<random>` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. The value data is `cmd.exe /c exit 0`; PurplePOC deletes
    the value after validation.
  siem_rule:
    event_ids: *id005
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `reg.exe ADD` for the HKCU Run value and immediately removes it with `reg.exe DELETE`.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate Registry Run Key persistence detection using a real registry write with a harmless command and verified cleanup.
    implementation: 'PurplePOC native action: run_key'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id006
- id: service
  name: Windows Service
  technique: T1543.003
  tactic: persistence
  mode: auto
  action: service
  description: Creates a temporary Windows service named `PurplePOC_<random>` whose `binPath` is `cmd.exe /c exit 0`, attempts to start it, and deletes the service afterward.
  siem_rule:
    event_ids: *id005
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `sc.exe create`, `sc.exe start`, and `sc.exe delete` for the PurplePOC service.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate service-creation persistence telemetry such as 7045/4697 and process/service-control activity without leaving a service installed.
    implementation: 'PurplePOC native action: service'
    command: No automatic command; guided/operator-controlled step.
  detection_sources: *id006
- id: atomic_scheduled_task
  name: Atomic Scheduled Task
  technique: T1053.005
  tactic: persistence
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1053.005
  atomic_guid: 42f53695-ad4a-4546-abb6-7d837f644a71
  description: Invokes Atomic Red Team T1053.005 GUID `42f53695-ad4a-4546-abb6-7d837f644a71`, which creates/uses the Atomic project's Windows scheduled-task persistence test.
  siem_rule:
    event_ids: *id005
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `Invoke-AtomicTest T1053.005 -TestGuids 42f53695-ad4a-4546-abb6-7d837f644a71`; Atomic cleanup is executed afterward.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate scheduled-task persistence detections against the standardized Atomic test and verify cleanup telemetry.
    implementation: Atomic Red Team T1053.005 / GUID 42f53695-ad4a-4546-abb6-7d837f644a71
    command: Invoke-AtomicTest T1053.005 -TestGuids 42f53695-ad4a-4546-abb6-7d837f644a71
  detection_sources: *id006
- id: atomic_run_key
  name: Atomic Registry Run Keys
  technique: T1547.001
  tactic: persistence
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1547.001
  atomic_guid: e55be3fd-3521-4610-9d1a-e210e42dcf05
  description: Invokes Atomic Red Team T1547.001 GUID `e55be3fd-3521-4610-9d1a-e210e42dcf05`, which performs the Atomic Registry Run Keys / Startup Folder persistence test.
  siem_rule:
    event_ids: *id005
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `Invoke-AtomicTest T1547.001 -TestGuids e55be3fd-3521-4610-9d1a-e210e42dcf05` and records registry/process artifacts.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate Run/Startup persistence rules against the exact Atomic test rather than only PurplePOC's native HKCU Run value.
    implementation: Atomic Red Team T1547.001 / GUID e55be3fd-3521-4610-9d1a-e210e42dcf05
    command: Invoke-AtomicTest T1547.001 -TestGuids e55be3fd-3521-4610-9d1a-e210e42dcf05
  detection_sources: *id006
- id: atomic_windows_service
  name: Atomic Windows Service
  technique: T1543.003
  tactic: persistence
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1543.003
  atomic_guid: 981e2942-e433-44e9-afc1-8c957a1496b6
  description: Invokes Atomic Red Team T1543.003 GUID `981e2942-e433-44e9-afc1-8c957a1496b6`, which performs the Atomic Windows-service persistence test.
  siem_rule:
    event_ids: *id005
    logic: Detect new/changed tasks, services, or autorun registry values created by unusual processes/users.
  execution_details:
    process: PowerShell / Atomic Red Team / Windows persistence utility
    input: PurplePOC synthetic persistence configuration
    operation: Runs `Invoke-AtomicTest T1543.003 -TestGuids 981e2942-e433-44e9-afc1-8c957a1496b6` and records service creation/execution/cleanup telemetry.
    destination: Local Windows configuration
    network: None unless explicitly stated by the Atomic test
    artifacts: Task/service/registry or other technique-specific persistence artifacts; cleanup expected
    purpose: Validate Windows-service persistence detections against the exact Atomic implementation.
    implementation: Atomic Red Team T1543.003 / GUID 981e2942-e433-44e9-afc1-8c957a1496b6
    command: Invoke-AtomicTest T1543.003 -TestGuids 981e2942-e433-44e9-afc1-8c957a1496b6
  detection_sources: *id006
- id: atomic_process_injection
  name: Atomic APC Process Injection
  technique: T1055.004
  tactic: privilege_escalation
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1055.004
  atomic_guid: 611b39b7-e243-4c81-87a4-7145a90358b1
  description: Invokes Atomic Red Team T1055.004 GUID `611b39b7-e243-4c81-87a4-7145a90358b1`, the Atomic APC process-injection test. PurplePOC captures the Atomic-defined target/process-access
    activity and cleanup output.
  siem_rule:
    event_ids: &id007
    - '4688'
    - Sysmon 1,10
    logic: Correlate elevation behavior, SYSTEM execution and suspicious process access/parent-child relationships.
  execution_details:
    process: Technique-dependent elevated process / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs `Invoke-AtomicTest T1055.004 -TestGuids 611b39b7-e243-4c81-87a4-7145a90358b1`.
    destination: Local host
    network: Technique-dependent
    artifacts: Elevated process creation and technique-specific security telemetry
    purpose: Validate EDR/Sysmon detections for APC-based process injection, including suspicious process access and the involved source/target processes.
    implementation: Atomic Red Team T1055.004 / GUID 611b39b7-e243-4c81-87a4-7145a90358b1
    command: Invoke-AtomicTest T1055.004 -TestGuids 611b39b7-e243-4c81-87a4-7145a90358b1
  detection_sources: &id008
    endpoint:
    - Windows 4688
    - Sysmon 1/10
    - Security 4672 where relevant
    ad_dc: []
    network: []
    application: []
    correlation: Correlate high-integrity execution or sensitive process access with unusual parent-child chains and privileged context.
    enrichment:
    - User
    - IntegrityLevel
    - TokenElevationType
    - ParentImage
    - TargetProcess
    protocols_ports:
    - 'LDAP: TCP/UDP 389'
    - 'LDAPS: TCP 636'
    - 'Global Catalog: TCP 3268; GC over TLS: TCP 3269 (when GC is used)'
    - 'RPC Endpoint Mapper: TCP 135'
    - 'Dynamic RPC high ports: TCP 49152-65535 (modern Windows default range)'
    - 'HTTP: TCP 80'
    - 'HTTPS/TLS: TCP 443'
    - AD CS template discovery is commonly LDAP; certificate enrollment may use RPC/DCOM or HTTP(S), depending on CA configuration
    analyst_recipe:
      time_window: 2 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, Sysmon 1,10.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: No automatic ESC1 exploitation command is executed; the runbook uses Certipy-supported enumeration/validation
        context and the CA/LDAP/RPC/HTTP telemetry to review.'
      - '3. If network activity is relevant, filter source -> destination using: LDAP: TCP/UDP 389; LDAPS: TCP 636; Global Catalog: TCP 3268; GC over TLS: TCP 3269 (when GC is used);
        RPC Endpoint Mapper: TCP 135; Dynamic RPC high ports: TCP 49152-65535 (modern Windows default range); HTTP: TCP 80; HTTPS/TLS: TCP 443; AD CS template discovery is commonly LDAP;
        certificate enrollment may use RPC/DCOM or HTTP(S), depending on CA configuration'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Correlate high-integrity execution or sensitive process access with unusual parent-child chains and privileged context.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - User
      - IntegrityLevel
      - TokenElevationType
      - ParentImage
      - TargetProcess
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: atomic_cmstp_uac_bypass
  name: CMSTP UAC Bypass
  technique: T1218.003
  tactic: privilege_escalation
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.003
  atomic_guid: 748cb4f6-2fb3-4e97-b7ad-b22635a09ab0
  description: Invokes Atomic Red Team T1218.003 GUID `748cb4f6-2fb3-4e97-b7ad-b22635a09ab0`, the Atomic CMSTP UAC-bypass test.
  siem_rule:
    event_ids: *id007
    logic: Correlate elevation behavior, SYSTEM execution and suspicious process access/parent-child relationships.
  execution_details:
    process: Technique-dependent elevated process / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs `Invoke-AtomicTest T1218.003 -TestGuids 748cb4f6-2fb3-4e97-b7ad-b22635a09ab0` and records the CMSTP/elevation process chain.
    destination: Local host
    network: Technique-dependent
    artifacts: Elevated process creation and technique-specific security telemetry
    purpose: Validate UAC-bypass/elevation telemetry associated with suspicious `cmstp.exe` execution and elevated child context.
    implementation: Atomic Red Team T1218.003 / GUID 748cb4f6-2fb3-4e97-b7ad-b22635a09ab0
    command: Invoke-AtomicTest T1218.003 -TestGuids 748cb4f6-2fb3-4e97-b7ad-b22635a09ab0
  detection_sources: *id008
- id: atomic_scheduled_task_system
  name: Scheduled Task Startup as SYSTEM
  technique: T1053.005
  tactic: privilege_escalation
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1053.005
  atomic_guid: fec27f65-db86-4c2d-b66c-61945aee87c2
  description: Invokes Atomic Red Team T1053.005 GUID `fec27f65-db86-4c2d-b66c-61945aee87c2`, which creates a scheduled task configured to start under SYSTEM context.
  siem_rule:
    event_ids: *id007
    logic: Correlate elevation behavior, SYSTEM execution and suspicious process access/parent-child relationships.
  execution_details:
    process: Technique-dependent elevated process / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs `Invoke-AtomicTest T1053.005 -TestGuids fec27f65-db86-4c2d-b66c-61945aee87c2` and records scheduled-task plus SYSTEM execution telemetry.
    destination: Local host
    network: Technique-dependent
    artifacts: Elevated process creation and technique-specific security telemetry
    purpose: Validate rules that detect task creation followed by execution as SYSTEM, including 4698/4702/4688 and task operational logs where enabled.
    implementation: Atomic Red Team T1053.005 / GUID fec27f65-db86-4c2d-b66c-61945aee87c2
    command: Invoke-AtomicTest T1053.005 -TestGuids fec27f65-db86-4c2d-b66c-61945aee87c2
  detection_sources: *id008
- id: atomic_regsvr32
  name: Atomic Regsvr32 Local COM Scriptlet
  technique: T1218.010
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.010
  atomic_guid: 449aa403-6aba-47ce-8a37-247d21ef0306
  description: Invokes Atomic Red Team T1218.010 GUID `449aa403-6aba-47ce-8a37-247d21ef0306`, which uses `regsvr32.exe` for the Atomic local COM-scriptlet proxy-execution test.
  siem_rule:
    event_ids: &id009
    - '4688'
    - '1102'
    - '4719'
    - Sysmon 1,5,12,13
    - PowerShell 4104
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact local Regsvr32 Atomic test and records process/command-line/scriptlet artifacts.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate defense-evasion detection for Regsvr32 used as a signed proxy rather than ordinary COM registration.
    implementation: Atomic Red Team T1218.010 / GUID 449aa403-6aba-47ce-8a37-247d21ef0306
    command: Invoke-AtomicTest T1218.010 -TestGuids 449aa403-6aba-47ce-8a37-247d21ef0306
  detection_sources: &id010
    endpoint:
    - Windows 4688
    - PowerShell 4104
    - Sysmon 1
    - Sysmon 5 Process Terminated where configured
    ad_dc: []
    network:
    - Local host only - no network port expected from this exact test
    application:
    - EDR self-protection/tamper events are relevant for real-world equivalents
    correlation: IF security-software discovery is followed by Stop-Process/taskkill/service-control targeting a security-related process/service from the same host/user within 5 minutes
      THEN alert. PurplePOC validates this safely by terminating only its own dummy child.
    enrichment:
    - User
    - Host
    - ParentImage
    - Image
    - CommandLine
    - ProcessGuid
    - TargetProcessId
    - TargetProcessName
    protocols_ports:
    - Local host only - no network port expected from this exact test
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and identify the parent PurplePOC PowerShell process.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: No automatic DCShadow command is executed; the step is an operator-controlled runbook tied to LDAP/RPC/Directory
        Service telemetry.'
      - 3. Correlate child process creation with PowerShell 4104 and process-termination telemetry such as Sysmon 5.
      - 4. In the production SIEM rule, require a preceding Security Software Discovery event from the same host/user within 5 minutes.
      - 5. Match real-world target names against the organization's AV/EDR process/service inventory.
      - 6. Suppress approved vendor upgrade/uninstall/maintenance workflows.
      - 7. Raise high severity when a real security process/service is targeted outside an approved workflow.
      minimum_fields:
      - timestamp
      - host
      - user
      - source process
      - parent process
      - target PID
      - target process
      - command line
      - ProcessGuid
      evidence:
      - Parent/child process tree
      - Target PID/name
      - PowerShell command
      - Termination event
      - Any preceding security-product enumeration
      false_positive_checks:
      - Approved security-product upgrade/uninstall?
      - Vendor maintenance process?
      - Authorized PurplePOC test window?
- id: atomic_odbcconf
  name: Atomic Odbcconf DLL Proxy Execution
  technique: T1218.008
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.008
  atomic_guid: 2430498b-06c0-4b92-a448-8ad263c388e2
  description: Invokes Atomic Red Team T1218.008 GUID `2430498b-06c0-4b92-a448-8ad263c388e2`, which uses `odbcconf.exe` in the Atomic DLL proxy-execution test.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact Odbcconf Atomic test and captures `odbcconf.exe`, command line and DLL-related execution telemetry.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate detection of the rarely used `odbcconf.exe` binary loading/executing content outside expected ODBC administration.
    implementation: Atomic Red Team T1218.008 / GUID 2430498b-06c0-4b92-a448-8ad263c388e2
    command: Invoke-AtomicTest T1218.008 -TestGuids 2430498b-06c0-4b92-a448-8ad263c388e2
  detection_sources: *id010
- id: atomic_modify_registry
  name: Atomic Modify Current User Registry
  technique: T1112
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1112
  atomic_guid: 1324796b-d0f6-455a-b4ae-21ffee6aa6b9
  description: Invokes Atomic Red Team T1112 GUID `1324796b-d0f6-455a-b4ae-21ffee6aa6b9` to modify the current user's Registry according to the Atomic test definition, followed by Atomic
    cleanup.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact Atomic T1112 Registry-modification test and records the changed key/value plus process telemetry.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate registry-modification detections and confirm the analyst can identify which process/user changed which registry object.
    implementation: Atomic Red Team T1112 / GUID 1324796b-d0f6-455a-b4ae-21ffee6aa6b9
    command: Invoke-AtomicTest T1112 -TestGuids 1324796b-d0f6-455a-b4ae-21ffee6aa6b9
  detection_sources: *id010
- id: atomic_disable_event_channel
  name: Disable Windows Event Log Channel
  technique: T1685.001
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1685.001
  atomic_guid: b26a3340-dad7-4360-9176-706269c74103
  description: Invokes Atomic Red Team T1685.001 GUID `b26a3340-dad7-4360-9176-706269c74103`, which disables a Windows Event Log channel according to the Atomic test definition and then
    relies on cleanup/recovery handling.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact Atomic event-channel-disable test and records event-log configuration/process telemetry.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate detection of event-channel disablement and identify the actor, channel and time at which logging visibility was reduced.
    implementation: Atomic Red Team T1685.001 / GUID b26a3340-dad7-4360-9176-706269c74103
    command: Invoke-AtomicTest T1685.001 -TestGuids b26a3340-dad7-4360-9176-706269c74103
  detection_sources: *id010
- id: atomic_eventlog_acl_modify
  name: Modify Event Log Channel Permissions
  technique: T1685.001
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1685.001
  atomic_guid: 8e81d090-0cd6-4d46-863c-eec11311298f
  description: Invokes Atomic Red Team T1685.001 GUID `8e81d090-0cd6-4d46-863c-eec11311298f`, which changes permissions on a Windows Event Log channel according to the Atomic test definition.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact Atomic event-log channel permission modification and records the initiating process plus channel configuration change.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate detection of event-log access-control tampering that could prevent collectors/users from reading security telemetry.
    implementation: Atomic Red Team T1685.001 / GUID 8e81d090-0cd6-4d46-863c-eec11311298f
    command: Invoke-AtomicTest T1685.001 -TestGuids 8e81d090-0cd6-4d46-863c-eec11311298f
  detection_sources: *id010
- id: atomic_clear_eventlog
  name: Clear Windows Event Log
  technique: T1685.005
  tactic: defense_evasion
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1685.005
  atomic_guid: e6abb60e-26b8-41da-8aae-0c35174b0967
  description: Invokes Atomic Red Team T1685.005 GUID `e6abb60e-26b8-41da-8aae-0c35174b0967` to clear a Windows Event Log using the Atomic test definition.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: Runs the exact Atomic log-clearing test and captures the process plus resulting log-clear telemetry such as Security 1102 where applicable.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate high-severity detection for clearing Windows logs and distinguish a true log-clear event from ordinary log maintenance.
    implementation: Atomic Red Team T1685.005 / GUID e6abb60e-26b8-41da-8aae-0c35174b0967
    command: Invoke-AtomicTest T1685.005 -TestGuids e6abb60e-26b8-41da-8aae-0c35174b0967
  detection_sources: *id010
- id: security_process_enumeration
  name: Security Software Process & Service Enumeration
  technique: T1518.001
  tactic: defense_evasion
  mode: auto
  action: powershell
  command: $patterns='defender|sense|crowdstrike|csfalcon|sentinel|sentinelone|carbonblack|cbdefense|sophos|mcafee|trellix|symantec|elastic|cylance|trend|eset|tanium'; $procs=Get-CimInstance
    Win32_Process | Where-Object {($_.Name -match $patterns) -or ($_.ExecutablePath -match $patterns)}; $svcs=Get-CimInstance Win32_Service | Where-Object {($_.Name -match $patterns)
    -or ($_.DisplayName -match $patterns) -or ($_.PathName -match $patterns)}; Write-Output '=== SECURITY PROCESSES ==='; $procs | Select-Object ProcessId,Name,ExecutablePath,CommandLine
    | Format-Table -AutoSize; Write-Output '=== SECURITY SERVICES ==='; $svcs | Select-Object Name,DisplayName,State,StartMode,PathName | Format-Table -AutoSize
  description: Queries `Win32_Process` and `Win32_Service` with `Get-CimInstance`, then filters process names, service names, display names and executable paths for common AV/EDR/security-product
    identifiers such as Defender, Sense, CrowdStrike, SentinelOne, Sophos, Trellix, Symantec, Elastic, Cylance, Trend, ESET and Tanium.
  siem_rule:
    event_ids:
    - '4688'
    - Sysmon 1
    - PowerShell 4104
    - WMI-Activity 5857-5861 where enabled
    logic: IF PowerShell/CIM broadly enumerates Win32_Process and Win32_Service for security-product names from a non-management endpoint THEN alert or raise risk; increase severity
      if termination/tamper/log-clearing follows within 5 minutes.
  execution_details:
    process: powershell.exe using Get-CimInstance
    input: Local Win32_Process and Win32_Service inventories
    operation: Reads local process/service metadata and prints the matching security processes and services. It does not stop, modify or reconfigure them.
    destination: Local host
    network: Local CIM/WMI query only; no remote destination or network port expected.
    artifacts: PowerShell, process creation and WMI/CIM activity where enabled
    purpose: Validate Security Software Discovery and give the analyst the actual security products/processes/services present on the endpoint.
    implementation: 'PurplePOC native PowerShell action: security_process_enumeration'
    command: $patterns='defender|sense|crowdstrike|csfalcon|sentinel|sentinelone|carbonblack|cbdefense|sophos|mcafee|trellix|symantec|elastic|cylance|trend|eset|tanium'; $procs=Get-CimInstance
      Win32_Process | Where-Object {($_.Name -match $patterns) -or ($_.ExecutablePath -match $patterns)}; $svcs=Get-CimInstance Win32_Service | Where-Object {($_.Name -match $patterns)
      -or ($_.DisplayName -match $patterns) -or ($_.PathName -match $patterns)}; Write-Output '=== SECURITY PROCESSES ==='; $procs | Select-Object ProcessId,Name,ExecutablePath,CommandLine
      | Format-Table -AutoSize; Write-Output '=== SECURITY SERVICES ==='; $svcs | Select-Object Name,DisplayName,State,StartMode,PathName | Format-Table -AutoSize
  detection_sources:
    endpoint:
    - Windows 4688
    - Sysmon 1
    - PowerShell 4104
    - WMI-Activity 5857-5861 where enabled
    ad_dc: []
    network:
    - Local host only - no network port expected from this exact test
    application:
    - EDR self-telemetry can enrich which security product is installed/running
    correlation: Correlate security-product process/service enumeration with subsequent Stop-Process, taskkill, service-control, audit-policy change, log clearing or other tamper activity
      from the same user/host within 5 minutes.
    enrichment:
    - User
    - Host
    - ProcessGuid
    - Image
    - CommandLine
    - ParentImage
    - Enumerated process
    - Enumerated service
    - Service state
    - ExecutablePath
    protocols_ports:
    - Local host only - no network port expected from this exact test
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the PurplePOC test timestamp, host and user.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Reads local process/service metadata and prints the matching security processes and services. It does not stop,
        modify or reconfigure them.'
      - 3. Extract the returned security process/service names and compare them with the endpoint's approved AV/EDR inventory.
      - 4. Pivot to WMI-Activity 5857-5861 where enabled.
      - 5. Correlate any process termination, taskkill, service stop, audit/log change or tamper activity from the same host/user within 5 minutes.
      - 6. Suppress approved inventory, health-check and endpoint-management tools.
      - 7. Alert when unusual security-software discovery is followed by defense-evasion behavior.
      minimum_fields:
      - timestamp
      - host
      - user
      - process image
      - command line
      - parent process
      - ProcessGuid
      - enumerated process/service
      - service state
      - executable path
      evidence:
      - PowerShell command/script block
      - Process tree
      - Enumerated security products/services
      - WMI activity where available
      - Any following termination/tamper activity
      false_positive_checks:
      - Approved endpoint inventory tool?
      - EDR health/upgrade workflow?
      - Known SOC/IT management process?
      - Expected behavior from this user/host?
- id: simulate_av_process_kill
  name: Security Process Termination Simulation (PurplePOC Dummy)
  technique: T1562.001
  tactic: defense_evasion
  mode: auto
  action: powershell
  command: $p=Start-Process powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 30' -PassThru; Start-Sleep -Milliseconds 500; Write-Output ('PurplePOC dummy security
    process PID=' + $p.Id); Stop-Process -Id $p.Id -Force; Write-Output ('PurplePOC terminated dummy PID=' + $p.Id)
  description: Starts a PurplePOC-owned `powershell.exe` child that only sleeps for 30 seconds, records its PID, then terminates that exact child PID with `Stop-Process -Force`.
  siem_rule:
    event_ids: *id009
    logic: IF security-software discovery is followed by Stop-Process/taskkill/service-control targeting a security-related process/service from the same host/user within 5 minutes THEN
      alert. PurplePOC validates this safely by terminating only its own dummy child.
  execution_details:
    process: powershell.exe -> PurplePOC-owned disposable powershell.exe child
    input: PID returned by Start-Process for the PurplePOC dummy child
    operation: Creates a disposable PowerShell child and terminates only the PID returned by `Start-Process`.
    destination: Local PurplePOC-owned dummy process
    network: Local host only - no network port expected.
    artifacts: 4688/Sysmon 1 process creation, PowerShell 4104 and process-termination telemetry such as Sysmon 5 where configured
    purpose: Validate process-termination/tamper-style telemetry safely. No Defender, EDR or third-party security process is targeted.
    implementation: 'PurplePOC native PowerShell action: simulate_av_process_kill'
    command: $p=Start-Process powershell.exe -ArgumentList '-NoProfile -Command Start-Sleep -Seconds 30' -PassThru; Start-Sleep -Milliseconds 500; Write-Output ('PurplePOC dummy security
      process PID=' + $p.Id); Stop-Process -Id $p.Id -Force; Write-Output ('PurplePOC terminated dummy PID=' + $p.Id)
  detection_sources: *id010
- id: atomic_admin_share_local
  name: Local ADMIN$ Command Output
  technique: T1021.002
  tactic: lateral_movement
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1021.002
  atomic_guid: d41aaab5-bdfe-431d-a3d5-c29e9136ff46
  description: Invokes Atomic Red Team T1021.002 GUID `d41aaab5-bdfe-431d-a3d5-c29e9136ff46` for the Atomic local ADMIN$ command-output test, generating administrative-share/SMB telemetry
    against the local test context.
  siem_rule:
    event_ids: &id011
    - '4688'
    - '4624'
    - 5140/5145
    - Sysmon 1,3,19-21
    logic: Correlate remote logon/share access with remote process creation, WMI/SMB activity, and unusual source hosts.
  execution_details:
    process: Windows remote-management/admin utility or Atomic Red Team launcher
    input: PurplePOC/Atomic localhost or lab target
    operation: Runs the exact Atomic ADMIN$ test and records SMB/share access plus related process/authentication telemetry.
    destination: Localhost or explicitly configured lab target
    network: SMB/WMI/remote-management traffic when the Atomic test actually generates it
    artifacts: Remote logon, share, WMI and process-creation telemetry
    purpose: Validate detections that correlate ADMIN$ access with command execution behavior while keeping the target on the authorized local test host.
    implementation: Atomic Red Team T1021.002 / GUID d41aaab5-bdfe-431d-a3d5-c29e9136ff46
    command: Invoke-AtomicTest T1021.002 -TestGuids d41aaab5-bdfe-431d-a3d5-c29e9136ff46
  detection_sources: &id012
    endpoint:
    - Windows 4624
    - '4688'
    - 5140/5145
    - 7045/4697 where service-based
    - Sysmon 1/3/19-21
    ad_dc:
    - Kerberos 4769 / NTLM 4776 when relevant
    network:
    - Firewall/NDR SMB/WMI/WinRM/RPC metadata
    - Source and destination host
    - Ports/protocol
    application:
    - WMI Operational 5857-5861 when configured
    correlation: Correlate remote logon/share access with remote process/service/WMI creation from the same source to target within a short window.
    enrichment:
    - Source IP/host
    - Destination host
    - User
    - LogonType
    - Share
    - Process/service
    protocols_ports:
    - 'Kerberos: TCP/UDP 88'
    - 'Kerberos password change/set: TCP/UDP 464 (only if password operations occur)'
    - After ticket use, the target service port is service-dependent (for example SMB 445, WinRM 5985/5986, RDP 3389)
    analyst_recipe:
      time_window: 2 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4624, 5140/5145, Sysmon 1,3,19-21.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: No automatic ticket injection/use command is executed; the runbook focuses on the resulting Kerberos, logon and
        target-service telemetry.'
      - '3. If network activity is relevant, filter source -> destination using: Kerberos: TCP/UDP 88; Kerberos password change/set: TCP/UDP 464 (only if password operations occur);
        After ticket use, the target service port is service-dependent (for example SMB 445, WinRM 5985/5986, RDP 3389)'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Correlate remote logon/share access with remote process/service/WMI creation from the same source to target within a short window.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Source IP/host
      - Destination host
      - User
      - LogonType
      - Share
      - Process/service
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: atomic_psexec_localhost
  name: PsExec Copy + Execute on Localhost
  technique: T1021.002
  tactic: lateral_movement
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1021.002
  atomic_guid: 0eb03d41-79e4-4393-8e57-6344856be1cf
  description: Invokes Atomic Red Team T1021.002 GUID `0eb03d41-79e4-4393-8e57-6344856be1cf` for a PsExec-style copy-and-execute workflow against localhost.
  siem_rule:
    event_ids: *id011
    logic: Correlate remote logon/share access with remote process creation, WMI/SMB activity, and unusual source hosts.
  execution_details:
    process: Windows remote-management/admin utility or Atomic Red Team launcher
    input: PurplePOC/Atomic localhost or lab target
    operation: Runs the exact Atomic localhost PsExec test and records SMB/admin-share, service/process and authentication telemetry.
    destination: Localhost or explicitly configured lab target
    network: SMB/WMI/remote-management traffic when the Atomic test actually generates it
    artifacts: Remote logon, share, WMI and process-creation telemetry
    purpose: 'Validate the classic PsExec sequence: SMB/admin-share activity followed by service/process execution on the target host.'
    implementation: Atomic Red Team T1021.002 / GUID 0eb03d41-79e4-4393-8e57-6344856be1cf
    command: Invoke-AtomicTest T1021.002 -TestGuids 0eb03d41-79e4-4393-8e57-6344856be1cf
  detection_sources: *id012
- id: atomic_wmi_remote_loopback
  name: WMI Remote Process Execution via Loopback
  technique: T1047
  tactic: lateral_movement
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1047
  atomic_guid: 00738d2a-4651-4d76-adf2-c43a41dfb243
  description: Invokes Atomic Red Team T1047 GUID `00738d2a-4651-4d76-adf2-c43a41dfb243` using the loopback/local target as the remote-WMI destination. The Atomic test attempts remote-style
    WMI process creation without selecting another production host.
  siem_rule:
    event_ids: *id011
    logic: Correlate remote logon/share access with remote process creation, WMI/SMB activity, and unusual source hosts.
  execution_details:
    process: Windows remote-management/admin utility or Atomic Red Team launcher
    input: PurplePOC/Atomic localhost or lab target
    operation: Runs the exact Atomic WMI remote-process test against the authorized loopback/local context and captures WMI/RPC/process telemetry.
    destination: Localhost or explicitly configured lab target
    network: SMB/WMI/remote-management traffic when the Atomic test actually generates it
    artifacts: Remote logon, share, WMI and process-creation telemetry
    purpose: Validate remote-WMI detection logic, including source process, RPC/WMI activity and target process creation, without requiring a second host.
    implementation: Atomic Red Team T1047 / GUID 00738d2a-4651-4d76-adf2-c43a41dfb243
    command: Invoke-AtomicTest T1047 -TestGuids 00738d2a-4651-4d76-adf2-c43a41dfb243
  detection_sources: *id012
- id: atomic_mshta_unc_lateral
  name: MSHTA UNC Lateral Movement Simulation
  technique: T1218.005
  tactic: lateral_movement
  mode: auto
  action: atomic
  backend: atomic
  atomic_technique: T1218.005
  atomic_guid: b8a8bdb2-7eae-490d-8251-d5e0295b2362
  description: Invokes Atomic Red Team T1218.005 GUID `b8a8bdb2-7eae-490d-8251-d5e0295b2362`, using the Atomic MSHTA/UNC lateral-movement pattern in the local lab context.
  siem_rule:
    event_ids: *id011
    logic: Correlate remote logon/share access with remote process creation, WMI/SMB activity, and unusual source hosts.
  execution_details:
    process: Windows remote-management/admin utility or Atomic Red Team launcher
    input: PurplePOC/Atomic localhost or lab target
    operation: Runs the exact Atomic MSHTA UNC-path test and records UNC/SMB access plus `mshta.exe` execution telemetry.
    destination: Localhost or explicitly configured lab target
    network: SMB/WMI/remote-management traffic when the Atomic test actually generates it
    artifacts: Remote logon, share, WMI and process-creation telemetry
    purpose: Validate a lateral-movement pattern where a signed Windows binary executes content referenced through a UNC/SMB path.
    implementation: Atomic Red Team T1218.005 / GUID b8a8bdb2-7eae-490d-8251-d5e0295b2362
    command: Invoke-AtomicTest T1218.005 -TestGuids b8a8bdb2-7eae-490d-8251-d5e0295b2362
  detection_sources: *id012
- id: exfil_stage
  name: Stage Synthetic Exfiltration Data
  technique: T1074.001
  tactic: exfiltration
  mode: auto
  action: powershell
  command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; New-Item -ItemType Directory -Force $d|Out-Null; 1..64|%{Add-Content (Join-Path $d 'synthetic.txt') ('PURPLEPOC-'+$_+'-'+('X'*128))};
    Compress-Archive (Join-Path $d 'synthetic.txt') (Join-Path $d 'staged.zip') -Force; Write-Output 'Synthetic data staged'
  description: Creates `%TEMP%\PurplePOC-Exfil\synthetic.txt` containing 64 synthetic `PURPLEPOC-...` records and compresses that file into `%TEMP%\PurplePOC-Exfil\staged.zip` with `Compress-Archive`.
  siem_rule:
    event_ids:
    - '4688'
    - '4663'
    - Sysmon 1,11
    - PowerShell 4104
    logic: IF PowerShell creates/compresses staged data AND the same user/process initiates unusual outbound traffic within 5 minutes THEN alert.
  execution_details:
    process: powershell.exe
    input: Generated synthetic lines PURPLEPOC-<n>-<padding>
    operation: Creates synthetic text data and a ZIP archive only inside the PurplePOC temporary directory.
    destination: '%TEMP%\PurplePOC-Exfil\staged.zip'
    network: NONE
    artifacts: PurplePOC-Exfil directory, synthetic.txt, staged.zip; PowerShell/file-create telemetry
    purpose: Validate data-staging/file-creation telemetry that would commonly precede exfiltration, without touching real user documents.
    implementation: 'PurplePOC native PowerShell action: exfil_stage'
    command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; New-Item -ItemType Directory -Force $d|Out-Null; 1..64|%{Add-Content (Join-Path $d 'synthetic.txt') ('PURPLEPOC-'+$_+'-'+('X'*128))};
      Compress-Archive (Join-Path $d 'synthetic.txt') (Join-Path $d 'staged.zip') -Force; Write-Output 'Synthetic data staged'
  detection_sources: &id014
    endpoint:
    - Windows 4688
    - Sysmon 1/3/11/22/23 as applicable
    - PowerShell 4104
    - 4663 where file auditing applies
    ad_dc: []
    network:
    - 'Firewall/NDR/NetFlow: src/dst, protocol, bytes, duration, connection frequency'
    application:
    - DNS logs
    - Proxy/SWG
    - CASB/cloud audit where applicable
    correlation: Correlate staging/file access with outbound network/application activity by the same host/user/process. Use destination rarity, protocol, upload volume, periodicity,
      subdomain entropy and byte ratios depending on technique.
    enrichment:
    - ProcessGuid
    - Image
    - User
    - Source host/IP
    - Destination/domain
    - Bytes sent/received
    - File/archive path
    protocols_ports: *id013
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4663, Sysmon 1,23, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Runs `Remove-Item -Recurse -Force` on the PurplePOC synthetic exfiltration directory.'
      - '3. If network activity is relevant, filter source -> destination using: Local host only - no network port expected from this exact test'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Correlate staging/file access with outbound network/application activity by the same host/user/process. Use destination rarity, protocol,
        upload volume, periodicity, subdomain entropy and byte ratios depending on technique.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - ProcessGuid
      - Image
      - User
      - Source host/IP
      - Destination/domain
      - Bytes sent/received
      - File/archive path
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_http_loopback
  name: HTTP Exfiltration Pattern to Loopback
  technique: T1048.003
  tactic: exfiltration
  mode: auto
  action: powershell
  command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $n=(Get-Item (Join-Path $d 'staged.zip')).Length; Write-Output ('HTTP exfiltration simulation prepared bytes='+$n+' target=127.0.0.1')
  description: Reads the size of the previously created `staged.zip` and prints a marker stating target `127.0.0.1`. This exact step does not create an HTTP connection or POST data.
  siem_rule:
    event_ids:
    - '4688'
    - '5156'
    - Sysmon 1,3
    - PowerShell 4104
    logic: IF a script interpreter accesses an archive AND initiates HTTP/POST or unusual HTTP traffic shortly afterward THEN alert; in PurplePOC lab runs allow loopback as the validation
      destination.
  execution_details:
    process: powershell.exe
    input: '%TEMP%\PurplePOC-Exfil\staged.zip'
    operation: Reads ZIP metadata with `Get-Item` and writes an HTTP-exfiltration simulation marker containing byte count and loopback target.
    destination: stdout only
    network: NONE — no HTTP request or POST is sent in v1.0.12
    artifacts: PowerShell execution and file metadata access; no network connection is intentionally created
    purpose: Document the HTTP-exfiltration workflow and analyst rule while making clear that this exact PurplePOC step produces no network event.
    implementation: 'PurplePOC native PowerShell action: exfil_http_loopback'
    command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $n=(Get-Item (Join-Path $d 'staged.zip')).Length; Write-Output ('HTTP exfiltration simulation prepared bytes='+$n+' target=127.0.0.1')
  detection_sources:
    endpoint:
    - '4688'
    - PowerShell 4104
    - Sysmon 1
    ad_dc: []
    network:
    - No network telemetry is expected from the current PurplePOC implementation because no HTTP request is sent.
    application:
    - No proxy/SWG event is expected from this exact simulation.
    correlation: 'For real T1048.003 detection: correlate staged/archive file access with HTTP POST/upload to a rare destination, unusual process, or abnormal outbound byte volume. Do
      not expect Sysmon 3/5156 from this specific PurplePOC step.'
    enrichment:
    - Process
    - Archive path
    - Destination URL/domain for real-world detections
    - Bytes uploaded
    protocols_ports:
    - 'Exact PurplePOC step: no HTTP connection is currently sent'
    - 'Production T1048.003 detection: HTTP TCP 80 / HTTPS TCP 443'
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 5156, Sysmon 1,3, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Reads ZIP metadata with `Get-Item` and writes an HTTP-exfiltration simulation marker containing byte count and
        loopback target.'
      - '3. If network activity is relevant, filter source -> destination using: Exact PurplePOC step: no HTTP connection is currently sent; Production T1048.003 detection: HTTP TCP
        80 / HTTPS TCP 443'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: For real T1048.003 detection: correlate staged/archive file access with HTTP POST/upload to a rare destination, unusual process, or
        abnormal outbound byte volume. Do not expect Sysmon 3/5156 from this specific PurplePOC step.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Process
      - Archive path
      - Destination URL/domain for real-world detections
      - Bytes uploaded
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_c2_pattern
  name: Exfiltration Over C2 Channel Simulation
  technique: T1041
  tactic: exfiltration
  mode: auto
  action: powershell
  command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $x=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $d 'staged.zip'))); Write-Output ('Synthetic C2 payload bytes='+$x.Length)
  description: Reads the synthetic `staged.zip` into memory with `[IO.File]::ReadAllBytes()` and Base64-encodes the bytes with `[Convert]::ToBase64String()`. The encoded data is not
    sent anywhere.
  siem_rule:
    event_ids:
    - '4688'
    - '4663'
    - Sysmon 1,3
    - PowerShell 4104
    logic: IF a scripting process accesses staged/archive data AND performs encoding AND has outbound C2-like traffic within 5 minutes THEN alert.
  execution_details:
    process: powershell.exe
    input: '%TEMP%\PurplePOC-Exfil\staged.zip'
    operation: Performs local file read plus Base64 encoding and prints only the encoded payload length.
    destination: Process memory; only encoded payload length is written to stdout
    network: NONE — encoded data is not transmitted
    artifacts: PowerShell execution plus access to staged.zip; encoded data exists transiently in memory
    purpose: Validate preparation/encoding telemetry associated with C2 exfiltration while avoiding any outbound transfer.
    implementation: 'PurplePOC native PowerShell action: exfil_c2_pattern'
    command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $x=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $d 'staged.zip'))); Write-Output ('Synthetic C2 payload bytes='+$x.Length)
  detection_sources:
    endpoint:
    - '4688'
    - PowerShell 4104
    - Sysmon 1
    - 4663 if file auditing enabled
    ad_dc: []
    network:
    - No outbound C2 transfer is performed by this exact simulation.
    application: []
    correlation: 'For real T1041: correlate archive/file access + encoding behavior with an existing C2/network session from the same host/process within 5 minutes. Flag large outbound
      byte spikes or changed upload/download ratio.'
    enrichment:
    - ProcessGuid
    - Image
    - Archive path
    - Encoding behavior
    - C2 destination
    - Bytes sent
    protocols_ports:
    - 'Exact PurplePOC step: no outbound C2 session is currently sent'
    - 'Production C2/exfil channel: protocol/port is channel-dependent; commonly TCP 443/80 but do not rely on port alone'
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4663, Sysmon 1,3, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Performs local file read plus Base64 encoding and prints only the encoded payload length.'
      - '3. If network activity is relevant, filter source -> destination using: Exact PurplePOC step: no outbound C2 session is currently sent; Production C2/exfil channel: protocol/port
        is channel-dependent; commonly TCP 443/80 but do not rely on port alone'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: For real T1041: correlate archive/file access + encoding behavior with an existing C2/network session from the same host/process within
        5 minutes. Flag large outbound byte spikes or changed upload/download ratio.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - ProcessGuid
      - Image
      - Archive path
      - Encoding behavior
      - C2 destination
      - Bytes sent
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_dns_pattern
  name: DNS Exfiltration Pattern Simulation
  technique: T1048
  tactic: exfiltration
  mode: auto
  action: powershell
  command: 1..8|%{Resolve-DnsName ('ppoc'+$_.ToString('00')+'.exfil.invalid') -ErrorAction SilentlyContinue|Out-Null}; Write-Output 'Synthetic DNS pattern generated'
  description: Issues eight `Resolve-DnsName` lookups for `ppoc01.exfil.invalid` through `ppoc08.exfil.invalid`. `.invalid` is reserved for non-resolving test names, so the activity
    creates DNS-query/NXDOMAIN-style telemetry without transmitting file data.
  siem_rule:
    event_ids:
    - '4688'
    - '5156'
    - Sysmon 1,22
    - PowerShell 4104
    logic: IF one ProcessGuid generates many unique or long subdomains for the same parent domain in <=60 seconds THEN alert; increase severity for high entropy or sustained volume.
  execution_details:
    process: powershell.exe -> Resolve-DnsName
    input: Generated hostnames ppoc01.exfil.invalid through ppoc08.exfil.invalid
    operation: Performs eight DNS resolution attempts to synthetic `ppocXX.exfil.invalid` names.
    destination: Configured Windows DNS resolver
    network: DNS queries are attempted; .invalid prevents a legitimate external destination from resolving
    artifacts: PowerShell execution and DNS-query telemetry; Sysmon 22 when configured
    purpose: Validate DNS-exfiltration analytics such as unique subdomain count, label pattern/entropy, query rate and NXDOMAIN behavior.
    implementation: 'PurplePOC native PowerShell action: exfil_dns_pattern'
    command: 1..8|%{Resolve-DnsName ('ppoc'+$_.ToString('00')+'.exfil.invalid') -ErrorAction SilentlyContinue|Out-Null}; Write-Output 'Synthetic DNS pattern generated'
  detection_sources:
    endpoint:
    - Windows 4688
    - PowerShell 4104
    - Sysmon 1
    - Sysmon 22 DNS Query
    ad_dc: []
    network:
    - 'Firewall/NDR: client -> DNS resolver, UDP/TCP 53'
    - Detect direct DNS to non-approved resolvers
    application:
    - Microsoft DNS Server Analytical/Audit logs where enabled
    - Recursive resolver logs
    - DoH/DoT visibility from proxy/SWG if available
    correlation: IF one host/process generates many unique subdomains for the same parent domain within <=60s AND label length/entropy or NXDOMAIN rate is abnormal THEN alert. Increase
      severity for sustained volume, direct-to-external resolver traffic, or PowerShell/Python/nslookup as the originating process.
    enrichment:
    - Client IP/host
    - ProcessGuid/Image
    - QueryName
    - Parent domain
    - QueryType
    - ResponseCode
    - Unique subdomain count
    - Label length/entropy
    - NXDOMAIN rate
    protocols_ports:
    - 'DNS: UDP/TCP 53'
    - 'DNS over TLS: TCP 853 (only if used)'
    - 'DNS over HTTPS: TCP 443 (only if used; inspect proxy/SWG/EDR rather than port 53)'
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 5156, Sysmon 1,22, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Performs eight DNS resolution attempts to synthetic `ppocXX.exfil.invalid` names.'
      - '3. If network activity is relevant, filter source -> destination using: DNS: UDP/TCP 53; DNS over TLS: TCP 853 (only if used); DNS over HTTPS: TCP 443 (only if used; inspect
        proxy/SWG/EDR rather than port 53)'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: IF one host/process generates many unique subdomains for the same parent domain within <=60s AND label length/entropy or NXDOMAIN rate
        is abnormal THEN alert. Increase severity for sustained volume, direct-to-external resolver traffic, or PowerShell/Python/nslookup as the originating process.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Client IP/host
      - ProcessGuid/Image
      - QueryName
      - Parent domain
      - QueryType
      - ResponseCode
      - Unique subdomain count
      - Label length/entropy
      - NXDOMAIN rate
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_web_service
  name: Web Service Exfiltration Simulation
  technique: T1567
  tactic: exfiltration
  mode: auto
  action: powershell
  command: Write-Output 'Synthetic web-service exfiltration pattern generated; no real data transmitted'
  description: Writes a PurplePOC marker stating that a web-service exfiltration pattern was generated. This exact test does not open a socket, access a URL or upload a file.
  siem_rule:
    event_ids:
    - '4688'
    - '5156'
    - Sysmon 1,3
    - Proxy/Firewall
    logic: IF an uncommon process/script interpreter connects to cloud or web-service destinations after archive/file access AND upload ratio/volume is anomalous THEN alert.
  execution_details:
    process: powershell.exe
    input: Synthetic PurplePOC marker only
    operation: Writes a local stdout marker only.
    destination: stdout only
    network: NONE — no web-service upload is performed
    artifacts: PowerShell/process telemetry only
    purpose: Provide T1567 detection/runbook context while explicitly avoiding real web-service traffic.
    implementation: 'PurplePOC native PowerShell action: exfil_web_service'
    command: Write-Output 'Synthetic web-service exfiltration pattern generated; no real data transmitted'
  detection_sources:
    endpoint:
    - '4688'
    - PowerShell 4104
    - Sysmon 1
    ad_dc: []
    network:
    - 'For real detections: Firewall/NDR flow metadata and outbound byte volume to cloud/web services'
    application:
    - Proxy/SWG URL/domain/category
    - CASB/cloud audit
    - TLS SNI/metadata if available
    correlation: IF an uncommon process/script interpreter accesses staged/archive data AND subsequently uploads to a web/cloud service with unusual destination rarity, volume or upload/download
      ratio THEN alert. This PurplePOC step itself does not upload.
    enrichment:
    - Process
    - URL/domain
    - Cloud service
    - Bytes uploaded
    - User
    - File/archive accessed
    protocols_ports:
    - 'Exact PurplePOC step: no outbound web-service upload is currently sent'
    - 'Production web-service exfiltration: typically HTTPS TCP 443; sometimes HTTP TCP 80'
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 5156, Sysmon 1,3, Proxy/Firewall.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Writes a local stdout marker only.'
      - '3. If network activity is relevant, filter source -> destination using: Exact PurplePOC step: no outbound web-service upload is currently sent; Production web-service exfiltration:
        typically HTTPS TCP 443; sometimes HTTP TCP 80'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: IF an uncommon process/script interpreter accesses staged/archive data AND subsequently uploads to a web/cloud service with unusual
        destination rarity, volume or upload/download ratio THEN alert. This PurplePOC step itself does not upload.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Process
      - URL/domain
      - Cloud service
      - Bytes uploaded
      - User
      - File/archive accessed
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_automated
  name: Automated Exfiltration Chunking Simulation
  technique: T1020
  tactic: exfiltration
  mode: auto
  action: powershell
  command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $n=(Get-Item (Join-Path $d 'staged.zip')).Length; $chunks=[Math]::Ceiling($n/1024); 1..$chunks|%{Start-Sleep -Milliseconds 50}; Write-Output
    ('Synthetic exfil chunks='+$chunks)
  description: Reads the synthetic ZIP size, calculates how many 1 KiB chunks it would contain and sleeps 50 ms once per calculated chunk. No chunk bytes are transmitted.
  siem_rule:
    event_ids:
    - '4688'
    - '4663'
    - Sysmon 1
    - PowerShell 4104
    logic: IF repeated access to staged data is followed by periodic outbound transfers to the same destination across multiple intervals THEN alert; suppress approved backup/sync software.
  execution_details:
    process: powershell.exe
    input: Byte length of %TEMP%\PurplePOC-Exfil\staged.zip
    operation: Calculates conceptual 1 KiB transfer chunks and generates a timed loop locally.
    destination: Local process timing only
    network: NONE — chunks are not transmitted
    artifacts: PowerShell execution, staged.zip metadata access and repeated short sleeps
    purpose: Validate the analyst logic for periodic/automated exfiltration while keeping the test network-silent.
    implementation: 'PurplePOC native PowerShell action: exfil_automated'
    command: $d=Join-Path $env:TEMP 'PurplePOC-Exfil'; $n=(Get-Item (Join-Path $d 'staged.zip')).Length; $chunks=[Math]::Ceiling($n/1024); 1..$chunks|%{Start-Sleep -Milliseconds 50};
      Write-Output ('Synthetic exfil chunks='+$chunks)
  detection_sources:
    endpoint:
    - '4688'
    - PowerShell 4104
    - Sysmon 1
    - 4663 if file auditing enabled
    ad_dc: []
    network:
    - 'For real T1020: NetFlow/NDR periodic outbound sessions, bytes, destination persistence'
    application:
    - Proxy/DNS where the automated channel uses them
    correlation: Detect repeated or periodic outbound transfers from the same host/process to the same destination across multiple intervals, especially after staged-file access. Suppress
      approved backup/sync agents.
    enrichment:
    - Periodicity
    - Destination
    - Bytes per interval
    - Process
    - Archive/file path
    - User
    protocols_ports:
    - 'Exact PurplePOC step: local chunking only; no network port expected'
    - 'Production automated exfiltration: channel-dependent; correlate the repeated transfer pattern with the actual destination port/protocol'
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4663, Sysmon 1, PowerShell 4104.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: Calculates conceptual 1 KiB transfer chunks and generates a timed loop locally.'
      - '3. If network activity is relevant, filter source -> destination using: Exact PurplePOC step: local chunking only; no network port expected; Production automated exfiltration:
        channel-dependent; correlate the repeated transfer pattern with the actual destination port/protocol'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Detect repeated or periodic outbound transfers from the same host/process to the same destination across multiple intervals, especially
        after staged-file access. Suppress approved backup/sync agents.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - Periodicity
      - Destination
      - Bytes per interval
      - Process
      - Archive/file path
      - User
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: exfil_cleanup
  name: Cleanup Synthetic Exfiltration Data
  technique: T1070.004
  tactic: exfiltration
  mode: auto
  action: powershell
  command: Remove-Item -Recurse -Force (Join-Path $env:TEMP 'PurplePOC-Exfil') -ErrorAction SilentlyContinue; Write-Output 'Synthetic exfil artifacts cleaned'
  description: Deletes `%TEMP%\PurplePOC-Exfil` recursively after the synthetic exfiltration sequence. Only PurplePOC-created test artifacts in that directory are removed.
  siem_rule:
    event_ids:
    - '4688'
    - '4663'
    - Sysmon 1,23
    - PowerShell 4104
    logic: IF staged/archive files are deleted shortly after suspicious outbound transfer activity THEN increase correlation severity; exclude approved PurplePOC validation runs.
  execution_details:
    process: powershell.exe
    input: '%TEMP%\PurplePOC-Exfil'
    operation: Runs `Remove-Item -Recurse -Force` on the PurplePOC synthetic exfiltration directory.
    destination: Local filesystem deletion
    network: NONE
    artifacts: Deletion of synthetic.txt/staged.zip/directory; file-delete telemetry when configured
    purpose: Validate post-staging deletion telemetry and ensure the exfiltration test leaves no synthetic files behind.
    implementation: 'PurplePOC native PowerShell action: exfil_cleanup'
    command: Remove-Item -Recurse -Force (Join-Path $env:TEMP 'PurplePOC-Exfil') -ErrorAction SilentlyContinue; Write-Output 'Synthetic exfil artifacts cleaned'
  detection_sources: *id014
- id: dcsync
  name: DCSync
  technique: T1003.006
  tactic: credential_access
  mode: guided
  tool: rubeus
  runbook: RT-AD-006
  description: GUIDED DCSync validation. The operator reviews whether the SIEM detects directory-replication behavior from a non-domain-controller identity/host. PurplePOC does not automatically
    request or extract directory secrets.
  siem_rule:
    event_ids: &id015
    - '4688'
    - 4624/4625
    - 4768/4769
    - Sysmon 1,10
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic DCSync command is executed. The report provides the authorized manual validation workflow and the DC/RPC/Directory Service telemetry to review.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate detection of abnormal directory replication, especially replication rights/use originating from a host or account that is not an approved DC.
    implementation: GUIDED operator runbook RT-AD-006 using rubeus; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: &id016
    endpoint:
    - Windows 4688
    - Sysmon 1/10
    - PowerShell 4104 where applicable
    ad_dc:
    - Kerberos 4768/4769
    - NTLM 4776
    - 4624/4625
    - 4662/5136 for directory attributes
    network:
    - NDR/firewall for LDAP/Kerberos/SMB flows
    - Source host to DC/service
    application: []
    correlation: Correlate credential-related process behavior with unusual authentication/Kerberos patterns from the same user/source. Use rate, target diversity and auth/encryption
      anomalies rather than a single event.
    enrichment:
    - User
    - Source host/IP
    - ServiceName/SPN
    - TicketEncryptionType
    - Process
    - Target account
    protocols_ports:
    - 'HTTP: TCP 80'
    - 'HTTPS/TLS: TCP 443'
    - 'SMB/CIFS: TCP 445'
    - 'Legacy NetBIOS Session Service: TCP 139 (only where legacy SMB is still used)'
    - AD CS Web Enrollment target is typically HTTP/HTTPS 80/443; relayed authentication source may be SMB 445 or another NTLM-capable protocol
    analyst_recipe:
      time_window: 5 minutes
      steps:
      - 1. Fix the test timestamp and source host/user. Start with 4688, 4624/4625, 4768/4769, Sysmon 1,10.
      - '2. Confirm the exact action/process chain. PurplePOC behavior: No automatic ESC8 relay/enrollment command is executed; the runbook links the authorized test to HTTP(S), NTLM,
        SMB and certificate-service telemetry.'
      - '3. If network activity is relevant, filter source -> destination using: HTTP: TCP 80; HTTPS/TLS: TCP 443; SMB/CIFS: TCP 445; Legacy NetBIOS Session Service: TCP 139 (only where
        legacy SMB is still used); AD CS Web Enrollment target is typically HTTP/HTTPS 80/443; relayed authentication source may be SMB 445 or another NTLM-capable protocol'
      - 4. Pivot all matching telemetry to the same user, source host, ProcessGuid/process, destination and test time window.
      - '5. Apply the SIEM correlation condition: Correlate credential-related process behavior with unusual authentication/Kerberos patterns from the same user/source. Use rate, target
        diversity and auth/encryption anomalies rather than a single event.'
      - 6. Remove known-good administration, software deployment, scanners, backup/sync agents and approved service accounts before alerting.
      - 7. Escalate when the correlated pattern is unusual for this user/host and the expected PurplePOC artifacts are present.
      minimum_fields:
      - timestamp
      - source host
      - source IP
      - user
      - process image
      - command line
      - parent process
      - User
      - Source host/IP
      - ServiceName/SPN
      - TicketEncryptionType
      - Process
      - Target account
      - destination host/IP
      - destination port
      - protocol
      - event/log source
      evidence:
      - Process tree and command line
      - Relevant Windows/Sysmon/EDR events
      - 'Network tuple: src IP -> dst IP : dst port / protocol when applicable'
      - Relevant AD/DNS/Proxy/NDR/Application records
      - Correlation timeline covering the complete cookbook time window
      false_positive_checks:
      - Expected administrator or service account?
      - Known software deployment / monitoring / backup / vulnerability scanner?
      - Expected management server or jump host?
      - Destination approved and normal for this source host/user?
      - Same behavior seen regularly in baseline before the test?
- id: dcshadow
  name: DCShadow
  technique: T1207
  tactic: defense_evasion
  mode: guided
  tool: operator-approved
  runbook: RT-AD-007
  description: GUIDED DCShadow validation. The operator reviews the monitoring path for rogue domain-controller registration/replication-style directory changes. PurplePOC does not automatically
    register a rogue DC or modify production AD.
  siem_rule:
    event_ids: *id009
    logic: Alert on log/audit changes, suspicious signed-binary proxy execution, and termination of security-like processes.
  execution_details:
    process: PowerShell / Windows utility / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: No automatic DCShadow command is executed; the step is an operator-controlled runbook tied to LDAP/RPC/Directory Service telemetry.
    destination: Local Windows security/audit configuration or disposable simulation target
    network: Usually none
    artifacts: Process, audit-policy/log, registry or process-termination telemetry depending on test
    purpose: Validate detection of directory/RPC behavior associated with DCShadow while keeping domain-impacting changes manual and explicitly authorized.
    implementation: GUIDED operator runbook RT-AD-007 using operator-approved; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id010
- id: ntlm_relay
  name: NTLM Relay
  technique: T1557.001
  tactic: credential_access
  mode: guided
  tool: operator-approved
  runbook: RT-NTLM-001
  description: GUIDED NTLM Relay validation. The operator selects an authorized lab source and target and verifies whether relayed NTLM authentication would be detected across SMB, HTTP(S)
    or LDAP(S). PurplePOC performs no automatic relay.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No relay command is launched automatically; the runbook identifies the authentication/network telemetry the analyst must correlate.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate relayed-authentication detection, including source/target mismatch, NTLM use and the target service reached by the relayed session.
    implementation: GUIDED operator runbook RT-NTLM-001 using operator-approved; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016
- id: ad_rootdse
  name: AD RootDSE Discovery
  technique: T1018
  tactic: discovery
  mode: auto
  action: powershell
  command: $r=[ADSI]'LDAP://RootDSE';$r|Select defaultNamingContext,configurationNamingContext,rootDomainNamingContext,dnsHostName|Format-List
  description: Reads the LDAP RootDSE object and returns `defaultNamingContext`, `configurationNamingContext`, `rootDomainNamingContext` and `dnsHostName` for the current directory service.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: RootDSE LDAP discovery from unusual workstation/script host.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: LDAP://RootDSE
    operation: Binds to `LDAP://RootDSE` with ADSI and reads naming-context/DC identity attributes.
    destination: Active Directory Domain Services
    network: Read-only LDAP
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Provide exact AD naming contexts/DC identity for later LDAP tests and validate low-level directory-discovery telemetry.
    implementation: 'PurplePOC native PowerShell action: ad_rootdse'
    command: $r=[ADSI]'LDAP://RootDSE';$r|Select defaultNamingContext,configurationNamingContext,rootDomainNamingContext,dnsHostName|Format-List
  detection_sources: *id002
- id: ad_spn_discovery
  name: LDAP SPN Account Discovery
  technique: T1087.002
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(servicePrincipalName=*))';$s.PageSize=200;$s.FindAll()|Select -First
    50|%{$_.Properties.samaccountname[0]}
  description: Uses `System.DirectoryServices.DirectorySearcher` with `(&(objectCategory=person)(objectClass=user)(servicePrincipalName=*))` and returns up to 50 `sAMAccountName` values
    for SPN-bearing user accounts.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: Broad servicePrincipalName LDAP search; correlate with later 4769 bursts.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD users
    operation: Performs a read-only LDAP search for user objects with `servicePrincipalName` populated. It does not request Kerberos service tickets.
    destination: Active Directory Domain Services
    network: Read-only LDAP; no TGS
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Identify Kerberoasting-relevant candidate accounts while separately validating broad SPN LDAP enumeration.
    implementation: 'PurplePOC native PowerShell action: ad_spn_discovery'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(servicePrincipalName=*))';$s.PageSize=200;$s.FindAll()|Select -First
      50|%{$_.Properties.samaccountname[0]}
  detection_sources: *id002
- id: ad_unconstrained_delegation
  name: Unconstrained Delegation Discovery
  technique: T1482
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(userAccountControl:1.2.840.113556.1.4.803:=524288)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  description: Searches AD with the LDAP matching rule for `userAccountControl` bit `524288`, returning principals configured for unconstrained delegation.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: Unusual LDAP bitwise delegation-UAC searches.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD objects
    operation: Performs a read-only LDAP bitwise search for the unconstrained-delegation UAC flag.
    destination: Active Directory Domain Services
    network: Read-only LDAP
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Identify unconstrained-delegation exposure and validate detection of directory searches for delegation configuration.
    implementation: 'PurplePOC native PowerShell action: ad_unconstrained_delegation'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(userAccountControl:1.2.840.113556.1.4.803:=524288)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  detection_sources: *id002
- id: ad_constrained_delegation
  name: Constrained Delegation Discovery
  technique: T1482
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(msDS-AllowedToDelegateTo=*)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  description: Searches AD for objects where `msDS-AllowedToDelegateTo` is present and returns the matching distinguished names.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: Unusual msDS-AllowedToDelegateTo reads; correlate Kerberos anomalies.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD objects
    operation: Performs a read-only LDAP search for constrained-delegation configuration.
    destination: Active Directory Domain Services
    network: Read-only LDAP
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Identify principals configured for constrained delegation and provide candidate objects for the manual Kerberos validation workflow.
    implementation: 'PurplePOC native PowerShell action: ad_constrained_delegation'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(msDS-AllowedToDelegateTo=*)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  detection_sources: *id002
- id: ad_rbcd_discovery
  name: RBCD Configuration Discovery
  technique: T1482
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(msDS-AllowedToActOnBehalfOfOtherIdentity=*)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  description: Searches AD for objects with `msDS-AllowedToActOnBehalfOfOtherIdentity` populated, identifying existing resource-based constrained delegation (RBCD) configuration.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    - '5136'
    logic: Unusual RBCD reads; high severity for 5136 writes.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD objects
    operation: Performs a read-only LDAP search for the RBCD attribute; PurplePOC does not write or change that attribute.
    destination: Active Directory Domain Services
    network: Read-only LDAP; no write
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Identify existing RBCD relationships and validate monitoring for sensitive delegation-attribute discovery.
    implementation: 'PurplePOC native PowerShell action: ad_rbcd_discovery'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(msDS-AllowedToActOnBehalfOfOtherIdentity=*)';$s.FindAll()|%{$_.Properties.distinguishedname[0]}
  detection_sources: *id002
- id: ad_asrep_candidate_discovery
  name: AS-REP Roast Candidate Discovery
  technique: T1558.004
  tactic: credential_access
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))';$s.FindAll()|%{$_.Properties.samaccountname[0]}
  description: Searches user objects for `userAccountControl` bit `4194304` (`DONT_REQ_PREAUTH`) and returns the candidate account names. No AS-REQ/AS-REP material is requested.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    - '4768'
    logic: DONT_REQ_PREAUTH enumeration; correlate actual abuse with abnormal 4768.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD users
    operation: Performs a read-only LDAP bitwise search for accounts that do not require Kerberos pre-authentication.
    destination: Active Directory Domain Services
    network: Read-only LDAP; no AS-REQ
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Identify AS-REP-roasting candidates without performing roasting and validate the directory-enumeration portion separately from Kerberos request telemetry.
    implementation: 'PurplePOC native PowerShell action: ad_asrep_candidate_discovery'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(userAccountControl:1.2.840.113556.1.4.803:=4194304))';$s.FindAll()|%{$_.Properties.samaccountname[0]}
  detection_sources: *id016
- id: ad_admincount_discovery
  name: Privileged adminCount Discovery
  technique: T1069.002
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(adminCount=1))';$s.FindAll()|%{$_.Properties.samaccountname[0]}
  description: Searches AD user objects for `adminCount=1` and returns account names commonly associated with protected/privileged group membership history.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: Broad privileged-account LDAP enumeration.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD users
    operation: Performs a read-only LDAP search for `adminCount=1` user objects.
    destination: Active Directory Domain Services
    network: Read-only LDAP
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Provide a privileged-account candidate set for higher-sensitivity detections while validating privileged-account enumeration.
    implementation: 'PurplePOC native PowerShell action: ad_admincount_discovery'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(&(objectCategory=person)(objectClass=user)(adminCount=1))';$s.FindAll()|%{$_.Properties.samaccountname[0]}
  detection_sources: *id002
- id: ad_gpo_discovery
  name: Group Policy Object Discovery
  technique: T1615
  tactic: discovery
  mode: auto
  action: powershell
  command: $r=[ADSI]'LDAP://RootDSE';$b='CN=Policies,CN=System,'+[string]$r.defaultNamingContext;$s=New-Object DirectoryServices.DirectorySearcher([ADSI]('LDAP://'+$b));$s.Filter='(objectClass=groupPolicyContainer)';$s.FindAll()|Select
    -First 100|%{$_.Properties.displayname[0]}
  description: Reads RootDSE to build `CN=Policies,CN=System,<defaultNamingContext>`, then searches for `groupPolicyContainer` objects and returns up to 100 GPO display names.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: GPO LDAP enumeration; correlate later SYSVOL 5140/5145.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: GPO containers
    operation: Performs a read-only LDAP enumeration of Group Policy container objects; it does not modify GPOs or SYSVOL.
    destination: Active Directory Domain Services
    network: Read-only LDAP
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Validate GPO discovery and provide exact policy objects for later authorized policy/SYSVOL review.
    implementation: 'PurplePOC native PowerShell action: ad_gpo_discovery'
    command: $r=[ADSI]'LDAP://RootDSE';$b='CN=Policies,CN=System,'+[string]$r.defaultNamingContext;$s=New-Object DirectoryServices.DirectorySearcher([ADSI]('LDAP://'+$b));$s.Filter='(objectClass=groupPolicyContainer)';$s.FindAll()|Select
      -First 100|%{$_.Properties.displayname[0]}
  detection_sources: *id002
- id: ad_computer_inventory
  name: LDAP Computer Inventory
  technique: T1018
  tactic: discovery
  mode: auto
  action: powershell
  command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(objectCategory=computer)';$s.PageSize=500;$s.FindAll()|Select -First 100|%{$_.Properties.dnshostname[0]}
  description: Searches AD for `(objectCategory=computer)` and returns up to 100 `dNSHostName` values. The discovered hosts are not contacted.
  siem_rule:
    event_ids:
    - '4688'
    - '4662'
    - Sysmon 1
    - PowerShell 4104
    logic: Broad computer LDAP search followed by SMB/WMI/WinRM fan-out.
  execution_details:
    process: powershell.exe / System.DirectoryServices
    input: AD computers
    operation: Performs a paged, read-only LDAP computer-object search and prints hostnames only.
    destination: Active Directory Domain Services
    network: Read-only LDAP; hosts not contacted
    artifacts: PowerShell/process telemetry plus LDAP telemetry where enabled
    purpose: Build an authorized AD computer inventory for target selection while separating directory discovery from actual lateral movement.
    implementation: 'PurplePOC native PowerShell action: ad_computer_inventory'
    command: $s=New-Object DirectoryServices.DirectorySearcher;$s.Filter='(objectCategory=computer)';$s.PageSize=500;$s.FindAll()|Select -First 100|%{$_.Properties.dnshostname[0]}
  detection_sources: *id002
- id: ptt
  name: Pass-the-Ticket
  technique: T1550.003
  tactic: lateral_movement
  mode: guided
  tool: rubeus
  runbook: RT-KRB-010
  description: GUIDED Pass-the-Ticket validation. The operator uses an authorized lab Kerberos ticket/session and verifies whether ticket use against an approved service is visible.
    PurplePOC does not automatically inject or reuse a ticket.
  siem_rule:
    event_ids: *id011
    logic: Correlate remote logon/share access with remote process creation, WMI/SMB activity, and unusual source hosts.
  execution_details:
    process: Windows remote-management/admin utility or Atomic Red Team launcher
    input: PurplePOC/Atomic localhost or lab target
    operation: No automatic ticket injection/use command is executed; the runbook focuses on the resulting Kerberos, logon and target-service telemetry.
    destination: Localhost or explicitly configured lab target
    network: SMB/WMI/remote-management traffic when the Atomic test actually generates it
    artifacts: Remote logon, share, WMI and process-creation telemetry
    purpose: Validate detection of suspicious Kerberos ticket reuse and the service access that follows it.
    implementation: GUIDED operator runbook RT-KRB-010 using rubeus; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id012
- id: s4u
  name: S4U
  technique: T1558
  tactic: credential_access
  mode: guided
  tool: rubeus
  runbook: RT-KRB-011
  description: GUIDED S4U validation. The operator reviews an authorized lab delegation path and verifies whether S4U-related Kerberos service-ticket activity is detected. PurplePOC
    does not automatically request delegated tickets.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic S4U request is issued; the runbook directs the analyst to correlate the approved test with DC 4769 and delegation context.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate unusual delegated Kerberos ticket requests and service/account combinations associated with S4U abuse.
    implementation: GUIDED operator runbook RT-KRB-011 using rubeus; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016
- id: kerberoast
  name: Kerberoasting
  technique: T1558.003
  tactic: credential_access
  mode: guided
  tool: rubeus
  runbook: RT-KRB-003
  description: GUIDED Kerberoasting validation. The operator uses the SPN accounts discovered by the AUTO LDAP step as the authorized candidate set and verifies service-ticket request
    telemetry. PurplePOC does not automatically request or export roastable ticket material.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic Kerberoasting command is executed; the runbook links discovered SPNs to DC 4769/service-ticket analytics.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate high-volume, unusual or weak-encryption service-ticket requests against SPN accounts while preserving an operator approval boundary.
    implementation: GUIDED operator runbook RT-KRB-003 using rubeus; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016
- id: asrep
  name: AS-REP Roasting
  technique: T1558.004
  tactic: credential_access
  mode: guided
  tool: rubeus
  runbook: RT-KRB-004
  description: GUIDED AS-REP Roasting validation. The operator uses accounts identified by the `DONT_REQ_PREAUTH` AUTO search and verifies the Kerberos 4768 behavior in an authorized
    lab. PurplePOC does not automatically request or export AS-REP material.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic AS-REP roasting command is executed; the runbook links the candidate accounts to the expected Kerberos pre-authentication telemetry.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate AS-REP-roasting detection for accounts that do not require pre-authentication.
    implementation: GUIDED operator runbook RT-KRB-004 using rubeus; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016
- id: lsass
  name: LSASS Credential Access
  technique: T1003.001
  tactic: credential_access
  mode: guided
  tool: operator-approved
  runbook: RT-CRED-001
  description: GUIDED LSASS credential-access validation. The operator verifies whether an approved lab attempt to access the LSASS process is detected. PurplePOC does not automatically
    read LSASS memory or dump credentials.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic LSASS memory-access/dump command is executed; the runbook focuses on process-access telemetry such as Sysmon 10 plus EDR events.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate high-severity detection of suspicious access to `lsass.exe` while keeping real credential extraction outside AUTO execution.
    implementation: GUIDED operator runbook RT-CRED-001 using operator-approved; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016
- id: adcs_esc1
  name: ADCS ESC1
  technique: T1649
  tactic: privilege_escalation
  mode: guided
  tool: certipy
  runbook: RT-ADCS-001
  description: GUIDED AD CS ESC1 validation. The operator inspects certificate templates/CA configuration for an ESC1-style path and verifies enrollment/directory telemetry in an authorized
    lab. PurplePOC does not automatically request an identity-escalating certificate.
  siem_rule:
    event_ids: *id007
    logic: Correlate elevation behavior, SYSTEM execution and suspicious process access/parent-child relationships.
  execution_details:
    process: Technique-dependent elevated process / Atomic Red Team launcher
    input: PurplePOC/Atomic test parameters
    operation: No automatic ESC1 exploitation command is executed; the runbook uses Certipy-supported enumeration/validation context and the CA/LDAP/RPC/HTTP telemetry to review.
    destination: Local host
    network: Technique-dependent
    artifacts: Elevated process creation and technique-specific security telemetry
    purpose: Validate detection of risky certificate-template use and suspicious enrollment behavior associated with ESC1 without automatically escalating identity.
    implementation: GUIDED operator runbook RT-ADCS-001 using certipy; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id008
- id: adcs_esc8
  name: ADCS ESC8
  technique: T1557
  tactic: credential_access
  mode: guided
  tool: certipy
  runbook: RT-ADCS-008
  description: GUIDED AD CS ESC8 validation. The operator verifies whether NTLM relay toward an authorized AD CS Web Enrollment endpoint would be detected. PurplePOC does not automatically
    coerce authentication, relay NTLM or request a certificate.
  siem_rule:
    event_ids: *id015
    logic: Correlate authentication anomalies and credential-access tooling/process access with unusual or privileged accounts.
  execution_details:
    process: GUIDED operator-controlled tool
    input: Operator-selected lab target
    operation: No automatic ESC8 relay/enrollment command is executed; the runbook links the authorized test to HTTP(S), NTLM, SMB and certificate-service telemetry.
    destination: Operator-controlled lab context
    network: Depends on guided procedure
    artifacts: Authentication/process-access telemetry according to the guided technique
    purpose: Validate the authentication and certificate-enrollment chain associated with AD CS Web Enrollment relay exposure.
    implementation: GUIDED operator runbook RT-ADCS-008 using certipy; no automatic command.
    command: No automatic command. Follow the authorized GUIDED runbook.
  detection_sources: *id016

'@
# --------------------------------------------------------------------
# runbooks/runbooks.yaml
# --------------------------------------------------------------------

Write-File "runbooks\runbooks.yaml" @'
RT-AD-006:
  title: DCSync Detection Validation
  technique: T1003.006
  expected_events:
    - 4662

RT-AD-007:
  title: DCShadow Detection Validation
  technique: T1207
  expected_events:
    - 5136

RT-NTLM-001:
  title: NTLM Relay Detection Validation
  technique: T1557.001
  expected_events:
    - 4624
    - 4776

RT-KRB-003:
  title: Kerberoasting Detection Validation
  technique: T1558.003
  expected_events:
    - 4769

RT-KRB-004:
  title: AS-REP Roasting Detection Validation
  technique: T1558.004
  expected_events:
    - 4768

RT-KRB-010:
  title: Pass-the-Ticket Detection Validation
  technique: T1550.003
  expected_events:
    - 4624
    - 4769

RT-KRB-011:
  title: S4U Detection Validation
  technique: T1558
  expected_events:
    - 4769

RT-CRED-001:
  title: LSASS Credential Access Detection Validation
  technique: T1003.001
  expected_sysmon:
    - 10

RT-ADCS-001:
  title: ADCS ESC1 Detection Validation
  technique: T1649
  expected_events:
    - 4886
    - 4887

RT-ADCS-008:
  title: ADCS ESC8 Detection Validation
  technique: T1557
  expected_events:
    - 4886
    - 4887

# --- Baseline AUTO techniques (behaviour PurplePOC executes itself) ---
# Expectations assume the relevant audit policy is on (e.g. Audit Process
# Creation for 4688) and/or Sysmon is installed. A MISSED result may simply
# mean the technique ran but the corresponding logging is not enabled.

RT-DISC-001:
  title: Account Discovery Detection Validation
  technique: T1033
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-DISC-002:
  title: System Information Discovery Detection Validation
  technique: T1082
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-DISC-003:
  title: Network Configuration Discovery Detection Validation
  technique: T1016
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-DISC-004:
  title: Domain Trust Discovery Detection Validation
  technique: T1482
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-EXEC-001:
  title: PowerShell Execution Detection Validation
  technique: T1059.001
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-PERS-001:
  title: Scheduled Task Detection Validation
  technique: T1053.005
  expected_events:
    - 4698
    - 4688
  expected_sysmon:
    - 1

RT-PERS-002:
  title: Registry Run Key Detection Validation
  technique: T1547.001
  expected_events:
    - 4657
  expected_sysmon:
    - 13

RT-PERS-003:
  title: Windows Service Detection Validation
  technique: T1543.003
  expected_events:
    - 4697

RT-EXEC-002:
  title: WMI Execution Detection Validation
  technique: T1047
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-DISC-005:
  title: Registry Query Detection Validation
  technique: T1012
  expected_events:
    - 4688
  expected_sysmon:
    - 1

RT-PRIV-001:
  title: APC Process Injection Detection Validation
  technique: T1055.004
  expected_events:
    - 4688
  expected_sysmon:
    - 1
    - 10

RT-DEFEV-001:
  title: Regsvr32 Proxy Execution Detection Validation
  technique: T1218.010
  expected_events:
    - 4688
  expected_sysmon:
    - 1
    - 7

RT-DEFEV-002:
  title: Odbcconf Proxy Execution Detection Validation
  technique: T1218.008
  expected_events:
    - 4688
  expected_sysmon:
    - 1
    - 7

RT-DEFEV-003:
  title: Registry Modification Detection Validation
  technique: T1112
  expected_events:
    - 4657
  expected_sysmon:
    - 13
'@

# --------------------------------------------------------------------
# core/database.py
# --------------------------------------------------------------------

Write-File "core\database.py" @'
import json
import os
import sqlite3
from pathlib import Path


# Runtime state lives outside the project tree (which may be rebuilt or synced
# by OneDrive) so a live database is never wiped or locked mid-run.
RUNTIME = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "PurplePOC"
DB_PATH = RUNTIME / "data" / "purplepoc.db"


def connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    return sqlite3.connect(DB_PATH)


def init_db():
    con = connect()
    cur = con.cursor()

    cur.execute("""
    CREATE TABLE IF NOT EXISTS runs (
        id TEXT PRIMARY KEY,
        scenario TEXT,
        host TEXT,
        domain_name TEXT,
        operator TEXT,
        started TEXT,
        ended TEXT
    )
    """)

    cur.execute("""
    CREATE TABLE IF NOT EXISTS steps (
        id TEXT PRIMARY KEY,
        run_id TEXT,
        test_id TEXT,
        name TEXT,
        technique TEXT,
        tactic TEXT,
        mode TEXT,
        tool TEXT,
        backend TEXT,
        action TEXT,
        atomic_guid TEXT,
        target TEXT,
        status TEXT,
        exit_code INTEGER,
        stdout TEXT,
        stderr TEXT,
        evidence_count INTEGER,
        started TEXT,
        ended TEXT,
        duration_seconds REAL
    )
    """)

    existing_step_columns = {
        row[1]
        for row in cur.execute("PRAGMA table_info(steps)").fetchall()
    }

    step_migrations = {
        "test_id": "TEXT",
        "tactic": "TEXT",
        "backend": "TEXT",
        "action": "TEXT",
        "atomic_guid": "TEXT",
        "exit_code": "INTEGER",
        "stdout": "TEXT",
        "stderr": "TEXT",
        "evidence_count": "INTEGER",
        "duration_seconds": "REAL",
    }

    for column, sql_type in step_migrations.items():
        if column not in existing_step_columns:
            cur.execute(
                f"ALTER TABLE steps ADD COLUMN {column} {sql_type}"
            )

    cur.execute("""
    CREATE TABLE IF NOT EXISTS observations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        step_id TEXT,
        source TEXT,
        telemetry_seen INTEGER,
        alert_seen INTEGER,
        prevented INTEGER,
        alert_id TEXT,
        severity TEXT,
        first_seen TEXT,
        raw_json TEXT
    )
    """)

    con.commit()
    con.close()


def insert_run(row):
    con = connect()
    con.execute("""
    INSERT INTO runs
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """, row)
    con.commit()
    con.close()


def update_run_end(run_id, ended):
    con = connect()
    con.execute(
        "UPDATE runs SET ended=? WHERE id=?",
        (ended, run_id)
    )
    con.commit()
    con.close()


def insert_step(row):
    con = connect()
    con.execute("""
    INSERT INTO steps
    (
        id,
        run_id,
        test_id,
        name,
        technique,
        tactic,
        mode,
        tool,
        backend,
        action,
        atomic_guid,
        target,
        status,
        exit_code,
        stdout,
        stderr,
        evidence_count,
        started,
        ended,
        duration_seconds
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, row)
    con.commit()
    con.close()


def insert_observation(step_id, obs):
    con = connect()
    con.execute("""
    INSERT INTO observations
    (
        step_id,
        source,
        telemetry_seen,
        alert_seen,
        prevented,
        alert_id,
        severity,
        first_seen,
        raw_json
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        step_id,
        obs.get("source"),
        int(bool(obs.get("telemetry_seen"))),
        int(bool(obs.get("alert_seen"))),
        int(bool(obs.get("prevented"))),
        obs.get("alert_id"),
        obs.get("severity"),
        obs.get("first_seen"),
        json.dumps(obs.get("raw", {}))
    ))
    con.commit()
    con.close()
'@

# --------------------------------------------------------------------
# core/scope.py
# --------------------------------------------------------------------

Write-File "core\scope.py" @'
class ScopeError(RuntimeError):
    pass


def validate_target(config, target):
    scope = config.get("scope", {})

    allowed = set()

    for key in (
        "attack_hosts",
        "domain_controllers",
        "target_hosts"
    ):
        allowed.update(
            x.lower()
            for x in scope.get(key, [])
        )

    if not target:
        return True

    if target.lower() not in allowed:
        raise ScopeError(
            f"Target outside configured POC scope: {target}"
        )

    return True
'@

# --------------------------------------------------------------------
# core/tools.py
# --------------------------------------------------------------------

Write-File "core\tools.py" @'
import hashlib
import importlib.metadata
import shutil
from pathlib import Path
import yaml


ROOT = Path(__file__).resolve().parents[1]


def load_manifest():
    path = ROOT / "tools" / "manifest.yaml"
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _certipy_status(entry):
    exe = shutil.which("certipy")
    version = None

    try:
        version = importlib.metadata.version("certipy-ad")
    except importlib.metadata.PackageNotFoundError:
        pass

    if not exe and not version:
        return {
            "status": "MISSING",
            "tool": "certipy",
            "help": entry.get("help"),
            "install": "Run Bootstrap.ps1 / Setup-GuidedTools.ps1",
            "source_url": entry.get("source_url")
        }

    return {
        "status": "READY",
        "tool": "certipy",
        "path": exe or "python-package:certipy-ad",
        "version": version,
        "source_url": entry.get("source_url"),
        "help": entry.get("help")
    }


def get_tool_status(name):
    manifest = load_manifest()
    entry = manifest.get("tools", {}).get(name)

    if not entry:
        return {
            "status": "UNKNOWN",
            "tool": name
        }

    if name == "certipy" and entry.get("install_type") == "python_package":
        return _certipy_status(entry)

    expected = entry.get("expected_path")

    if not expected:
        return {
            "status": "READY_METADATA",
            "tool": name,
            "help": entry.get("help")
        }

    path = ROOT / expected

    if not path.exists():
        return {
            "status": (
                "OPERATOR_REQUIRED"
                if entry.get("distribution") == "operator_staged"
                else "MISSING"
            ),
            "tool": name,
            "path": str(path),
            "source_url": entry.get("source_url"),
            "help": entry.get("help")
        }

    result = {
        "status": "READY",
        "tool": name,
        "path": str(path),
        "source_url": entry.get("source_url"),
        "help": entry.get("help")
    }

    if path.is_file():
        result["sha256"] = sha256(path)

    return result
'@
# --------------------------------------------------------------------
# core/telemetry.py
# --------------------------------------------------------------------

Write-File "core\telemetry.py" @'
import json
import subprocess
from datetime import datetime


# Security-log event IDs relevant to the catalogued techniques.
WINDOWS_EVENTS = [
    4624, 4625, 4648, 4657, 4662, 4672,
    4688, 4697, 4698, 4699, 4768, 4769,
    4771, 4776, 4886, 4887, 5136, 5137,
    5140, 5145, 7045
]

# Sysmon (Microsoft-Windows-Sysmon/Operational) event IDs.
SYSMON_EVENTS = [1, 3, 7, 8, 10, 11, 12, 13, 22, 25]


def _query(log_name, ids, start, end):
    id_list = ",".join(str(x) for x in ids)

    script = rf'''
$Start = [datetime]::Parse("{start.isoformat()}")
$End   = [datetime]::Parse("{end.isoformat()}")

Get-WinEvent -FilterHashtable @{{
    LogName="{log_name}"
    StartTime=$Start
    EndTime=$End
    Id=@({id_list})
}} -ErrorAction SilentlyContinue |
Select-Object Id,@{{Name="Channel";Expression={{$_.LogName}}}},TimeCreated,ProviderName,MachineName,Message |
ConvertTo-Json -Compress -Depth 4
'''

    p = subprocess.run(
        [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            script
        ],
        capture_output=True,
        text=True
    )

    if not p.stdout.strip():
        return []

    try:
        data = json.loads(p.stdout)
    except Exception:
        return []

    if isinstance(data, dict):
        return [data]

    return data


def collect_security_events(start, end):
    """Collect Security-log and Sysmon-log events in the window.

    Each event carries a "Channel" field (its source log) so detection
    scoring can tell Security event IDs from Sysmon event IDs, whose
    numbering overlaps. Both queries are best-effort: a missing Sysmon
    log is silently ignored.
    """
    events = []
    events.extend(_query("Security", WINDOWS_EVENTS, start, end))
    events.extend(
        _query(
            "Microsoft-Windows-Sysmon/Operational",
            SYSMON_EVENTS,
            start,
            end
        )
    )
    return events
'@

# --------------------------------------------------------------------
# core/detection.py
# --------------------------------------------------------------------

Write-File "core\detection.py" @'
from pathlib import Path

import yaml

from core.cleanup import (
    register_action,
    mark_clean,
    mark_failed,
)


ROOT = Path(__file__).resolve().parents[1]


def load_expectations():
    """Build technique -> {"security": set, "sysmon": set} from runbooks.yaml."""
    path = ROOT / "runbooks" / "runbooks.yaml"

    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}

    expectations = {}

    for runbook in data.values():
        if not isinstance(runbook, dict):
            continue

        technique = runbook.get("technique")

        if not technique:
            continue

        entry = expectations.setdefault(
            technique,
            {"security": set(), "sysmon": set()}
        )

        for e in runbook.get("expected_events") or []:
            entry["security"].add(int(e))

        for e in runbook.get("expected_sysmon") or []:
            entry["sysmon"].add(int(e))

    return expectations


def observed_ids(events):
    """Split observed event IDs by source channel (security vs sysmon)."""
    security = set()
    sysmon = set()

    for ev in events or []:
        raw_id = ev.get("Id")

        try:
            eid = int(raw_id)
        except (TypeError, ValueError):
            continue

        channel = str(ev.get("Channel") or "").lower()

        if "sysmon" in channel:
            sysmon.add(eid)
        else:
            security.add(eid)

    return {"security": security, "sysmon": sysmon}


def evaluate(technique, status, events, expectations):
    """Return a detection verdict for one executed step.

    Verdicts:
      DETECTED       - at least one expected event was observed in the window
      MISSED         - the technique has expectations but none were observed
      NO_EXPECTATION - no runbook defines expected events for this technique
      NOT_EXECUTED   - the step was skipped, so detection is not applicable
    """
    prevented = status == "PREVENTED"

    if status in ("SKIPPED", "UNKNOWN"):
        return {
            "verdict": "NOT_EXECUTED",
            "expected": [],
            "matched": [],
            "prevented": prevented
        }

    exp = expectations.get(technique)

    if not exp or (not exp["security"] and not exp["sysmon"]):
        return {
            "verdict": "NO_EXPECTATION",
            "expected": [],
            "matched": [],
            "prevented": prevented
        }

    obs = observed_ids(events)

    matched = sorted(
        (exp["security"] & obs["security"])
        | (exp["sysmon"] & obs["sysmon"])
    )

    expected_all = sorted(exp["security"] | exp["sysmon"])

    return {
        "verdict": "DETECTED" if matched else "MISSED",
        "expected": expected_all,
        "matched": matched,
        "prevented": prevented
    }
'@

# --------------------------------------------------------------------
# core/cleanup.py
# --------------------------------------------------------------------

Write-File "core\cleanup.py" @'
import json
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "data" / "cleanup-registry.json"


def _now():
    return datetime.now(timezone.utc).isoformat()


def _load():
    if not REGISTRY.exists():
        return []

    try:
        return json.loads(REGISTRY.read_text(encoding="utf-8"))
    except Exception:
        return []


def _save(items):
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    REGISTRY.write_text(
        json.dumps(items, indent=2),
        encoding="utf-8"
    )


def register_action(
    kind,
    description,
    cleanup_command=None,
    test_id=None,
    metadata=None
):
    items = _load()

    action = {
        "id": str(uuid.uuid4()),
        "test_id": test_id,
        "kind": kind,
        "description": description,
        "cleanup_command": cleanup_command,
        "metadata": metadata or {},
        "status": "PENDING",
        "registered": _now(),
        "completed": None,
        "last_error": None,
    }

    items.append(action)
    _save(items)

    return action["id"]


def mark_clean(action_id):
    items = _load()

    for item in items:
        if item["id"] == action_id:
            item["status"] = "CLEAN"
            item["completed"] = _now()
            item["last_error"] = None
            break

    _save(items)


def mark_failed(action_id, error):
    items = _load()

    for item in items:
        if item["id"] == action_id:
            item["status"] = "FAILED"
            item["last_error"] = str(error)
            break

    _save(items)


def _run_command(command):
    if not command:
        return {
            "exit_code": 0,
            "stdout": "",
            "stderr": "",
        }

    p = subprocess.run(
        command,
        capture_output=True,
        text=True,
        shell=False,
        timeout=120
    )

    return {
        "exit_code": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
    }


def retry_pending():
    items = _load()
    results = []

    for item in items:
        if item["status"] == "CLEAN":
            continue

        command = item.get("cleanup_command")

        if not command:
            results.append({
                "id": item["id"],
                "status": item["status"],
                "description": item["description"],
                "note": "No direct cleanup command registered",
            })
            continue

        try:
            result = _run_command(command)

            if result["exit_code"] == 0:
                item["status"] = "CLEAN"
                item["completed"] = _now()
                item["last_error"] = None
            else:
                item["status"] = "FAILED"
                item["last_error"] = (
                    result["stderr"].strip()
                    or result["stdout"].strip()
                    or f"exit code {result['exit_code']}"
                )

            results.append({
                "id": item["id"],
                "status": item["status"],
                "description": item["description"],
                "result": result,
            })

        except Exception as exc:
            item["status"] = "FAILED"
            item["last_error"] = str(exc)

            results.append({
                "id": item["id"],
                "status": "FAILED",
                "description": item["description"],
                "error": str(exc),
            })

    _save(items)
    return results


def summary():
    items = _load()

    return {
        "total": len(items),
        "clean": sum(1 for x in items if x["status"] == "CLEAN"),
        "pending": sum(1 for x in items if x["status"] == "PENDING"),
        "failed": sum(1 for x in items if x["status"] == "FAILED"),
        "actions": items,
    }


def reset():
    if REGISTRY.exists():
        REGISTRY.unlink()
'@

# --------------------------------------------------------------------
# core/auto.py
# --------------------------------------------------------------------

Write-File "core\auto.py" @'
import subprocess
import uuid

from core.cleanup import (
    register_action,
    mark_clean,
    mark_failed,
)


def run(cmd):
    p = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        shell=False
    )

    return {
        "exit_code": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr
    }


def execute(action, context):
    test_id = context.get("test_id")

    if action == "whoami":
        return run(["whoami.exe", "/all"])

    if action == "systeminfo":
        return run(["systeminfo.exe"])

    if action == "ipconfig":
        return run(["ipconfig.exe", "/all"])

    if action == "domain_trusts":
        return run(["nltest.exe", "/domain_trusts"])

    if action == "process_discovery":
        return run(["tasklist.exe", "/V"])

    if action == "service_discovery":
        return run(["sc.exe", "query", "type=", "service", "state=", "all"])

    if action == "account_discovery":
        return run(["net.exe", "user", "/domain"])

    if action == "group_discovery":
        return run(["net.exe", "group", "/domain"])

    if action == "dc_discovery":
        return run(["nltest.exe", "/dclist:"])

    if action == "share_discovery":
        return run(["net.exe", "view"])

    if action == "netstat":
        return run(["netstat.exe", "-ano"])

    if action == "arp":
        return run(["arp.exe", "-a"])

    if action == "dns_cache":
        return run(["ipconfig.exe", "/displaydns"])

    if action == "firewall_discovery":
        return run([
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Get-NetFirewallProfile | Format-List Name,Enabled,DefaultInboundAction,DefaultOutboundAction"
        ])

    if action == "powershell":
        script = context.get("command") or "$env:COMPUTERNAME | Out-Null; Get-Date | Out-Null"
        return run(["powershell.exe","-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-Command",script])

    if action == "scheduled_task":
        name = "PurplePOC_" + uuid.uuid4().hex[:8]

        cleanup_id = register_action(
            kind="scheduled_task",
            description=f"Delete scheduled task {name}",
            cleanup_command=[
                "schtasks.exe",
                "/Delete",
                "/TN",
                name,
                "/F",
            ],
            test_id=test_id,
            metadata={"name": name},
        )

        try:
            create = run([
                "schtasks.exe",
                "/Create",
                "/TN",
                name,
                "/SC",
                "ONCE",
                "/ST",
                "23:59",
                "/TR",
                "cmd.exe /c exit 0",
                "/F"
            ])

            if create["exit_code"] == 0:
                run([
                    "schtasks.exe",
                    "/Run",
                    "/TN",
                    name
                ])

            cleanup = run([
                "schtasks.exe",
                "/Delete",
                "/TN",
                name,
                "/F"
            ])

            if cleanup["exit_code"] == 0:
                mark_clean(cleanup_id)
            else:
                mark_failed(
                    cleanup_id,
                    cleanup["stderr"] or cleanup["stdout"]
                )

            create["cleanup_status"] = (
                "CLEAN"
                if cleanup["exit_code"] == 0
                else "FAILED"
            )

            return create

        except Exception as exc:
            mark_failed(cleanup_id, exc)
            raise

    if action == "run_key":
        name = "PurplePOC_" + uuid.uuid4().hex[:8]
        path = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

        cleanup_id = register_action(
            kind="registry_value",
            description=f"Delete Run key value {name}",
            cleanup_command=[
                "reg.exe",
                "DELETE",
                path,
                "/v",
                name,
                "/f",
            ],
            test_id=test_id,
            metadata={
                "path": path,
                "value": name,
            },
        )

        try:
            result = run([
                "reg.exe",
                "ADD",
                path,
                "/v",
                name,
                "/t",
                "REG_SZ",
                "/d",
                "cmd.exe /c exit 0",
                "/f"
            ])

            cleanup = run([
                "reg.exe",
                "DELETE",
                path,
                "/v",
                name,
                "/f"
            ])

            if cleanup["exit_code"] == 0:
                mark_clean(cleanup_id)
            else:
                mark_failed(
                    cleanup_id,
                    cleanup["stderr"] or cleanup["stdout"]
                )

            result["cleanup_status"] = (
                "CLEAN"
                if cleanup["exit_code"] == 0
                else "FAILED"
            )

            return result

        except Exception as exc:
            mark_failed(cleanup_id, exc)
            raise

    if action == "service":
        name = "PurplePOC_" + uuid.uuid4().hex[:8]

        cleanup_id = register_action(
            kind="service",
            description=f"Delete service {name}",
            cleanup_command=[
                "sc.exe",
                "delete",
                name,
            ],
            test_id=test_id,
            metadata={"name": name},
        )

        try:
            result = run([
                "sc.exe",
                "create",
                name,
                "binPath=",
                "cmd.exe /c exit 0",
                "start=",
                "demand"
            ])

            if result["exit_code"] == 0:
                run([
                    "sc.exe",
                    "start",
                    name
                ])

            cleanup = run([
                "sc.exe",
                "delete",
                name
            ])

            if cleanup["exit_code"] == 0:
                mark_clean(cleanup_id)
            else:
                mark_failed(
                    cleanup_id,
                    cleanup["stderr"] or cleanup["stdout"]
                )

            result["cleanup_status"] = (
                "CLEAN"
                if cleanup["exit_code"] == 0
                else "FAILED"
            )

            return result

        except Exception as exc:
            mark_failed(cleanup_id, exc)
            raise

    if action == "wmi":
        return run([
            "wmic.exe",
            "process",
            "call",
            "create",
            "cmd.exe /c exit 0"
        ])

    raise ValueError(
        f"Unknown AUTO action: {action}"
    )
'@
# --------------------------------------------------------------------
# core/guided.py
# --------------------------------------------------------------------

Write-File "core\guided.py" @'
from datetime import datetime, timezone
from pathlib import Path
import os
import subprocess

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt
from rich.table import Table

from core.tools import get_tool_status


console = Console()


STEP_HELP = {
    "RT-AD-006": {
        "title": "DCSync validation",
        "purpose": "Exercise directory-replication behavior from the approved lab procedure and validate Windows/EDR/SIEM visibility.",
        "prepare": [
            "Use the engagement-approved account and DC target.",
            "Confirm directory-service auditing is enabled if Windows-event validation is required.",
            "Keep the approved operator tool ready before arming the telemetry window.",
        ],
        "expected": ["Windows Security 4662 where auditing is configured", "EDR directory-replication / credential-access telemetry"],
    },
    "RT-AD-007": {
        "title": "DCShadow validation",
        "purpose": "Validate detection around abnormal AD object/replication changes using the approved lab procedure.",
        "prepare": ["Confirm the disposable test objects and rollback plan.", "Capture Directory Service and endpoint telemetry."],
        "expected": ["Directory Service object-change/replication telemetry", "Potential 5136 depending on audit policy"],
    },
    "RT-NTLM-001": {
        "title": "NTLM relay validation",
        "purpose": "Validate relay-related authentication/network detections using the approved lab procedure.",
        "prepare": ["Confirm the intended source, target and listener interfaces.", "Ensure SMB/HTTP and authentication telemetry are being captured."],
        "expected": ["4624/4776 where applicable", "SMB/HTTP authentication and endpoint/network telemetry"],
    },
    "RT-KRB-010": {
        "title": "Pass-the-Ticket validation",
        "purpose": "Validate anomalous Kerberos ticket-use detections using the approved lab procedure.",
        "prepare": ["Use only test identities/tickets created for the engagement.", "Capture logon and Kerberos service-ticket telemetry."],
        "expected": ["4624/4769 where applicable", "EDR anomalous ticket-use telemetry"],
    },
    "RT-KRB-011": {
        "title": "S4U validation",
        "purpose": "Validate Kerberos delegation/S4U detections using the approved lab procedure.",
        "prepare": ["Confirm the designated test service account and SPN context.", "Capture KDC and endpoint telemetry."],
        "expected": ["4769/service-ticket behavior", "EDR Kerberos/delegation telemetry"],
    },
    "RT-KRB-003": {
        "title": "Kerberoasting validation",
        "purpose": "Validate service-ticket request detections using the approved lab procedure.",
        "prepare": ["Use designated test service accounts/SPNs.", "Capture KDC 4769 telemetry before arming."],
        "expected": ["4769 service-ticket events", "Detection of unusual service-ticket request behavior"],
    },
    "RT-KRB-004": {
        "title": "AS-REP roasting validation",
        "purpose": "Validate pre-authentication-related Kerberos detections using designated test accounts.",
        "prepare": ["Use only the intentionally configured test identity.", "Capture 4768/KDC telemetry."],
        "expected": ["4768", "EDR/SIEM Kerberos anomaly telemetry"],
    },
    "RT-CRED-001": {
        "title": "LSASS access validation",
        "purpose": "Validate endpoint protection and process-access telemetry around the approved LSASS test.",
        "prepare": ["Confirm the host is disposable/snapshotted.", "Capture Sysmon ProcessAccess and EDR telemetry if available."],
        "expected": ["Sysmon 10 where configured", "EDR credential-access/process-memory telemetry"],
    },
    "RT-ADCS-001": {
        "title": "ADCS ESC1 validation",
        "purpose": "Validate AD CS template/enrollment detection using the approved test CA/template.",
        "prepare": ["Confirm the deliberately vulnerable test template and CA.", "Certipy is installed by PurplePOC bootstrap.", "Capture CA auditing and endpoint telemetry."],
        "expected": ["4886/4887 where CA auditing is enabled", "Certificate enrollment and endpoint telemetry"],
    },
    "RT-ADCS-008": {
        "title": "ADCS ESC8 validation",
        "purpose": "Validate AD CS web-enrollment/relay-related detection using the approved test setup.",
        "prepare": ["Confirm the intended test CA/web-enrollment endpoint.", "Certipy is installed by PurplePOC bootstrap.", "Capture CA, authentication and network telemetry."],
        "expected": ["4886/4887 where CA auditing is enabled", "Authentication/network/CA telemetry"],
    },
}


def _open_source(status):
    url = status.get("source_url")

    if not url:
        return False

    try:
        os.startfile(url)
        return True
    except Exception:
        return False


def _open_tool_path(status):
    path = status.get("path")

    if path:
        p = Path(path)
        candidate = p if p.is_dir() else p.parent
    else:
        tool = status.get("tool") or "operator-approved"
        candidate = Path(__file__).resolve().parents[1] / "tools" / tool

    try:
        candidate.mkdir(parents=True, exist_ok=True)
        os.startfile(str(candidate))
        return True
    except Exception:
        return False


def _show_help(step, status):
    runbook = step.get("runbook")
    info = STEP_HELP.get(runbook, {})
    console.print()
    console.print(Panel(
        info.get("purpose", "Follow the approved Purple-Team runbook for this test."),
        title=info.get("title", "Guided execution help")
    ))

    prep = info.get("prepare", [])
    if prep:
        console.print("[bold]Preparation[/bold]")
        for item in prep:
            console.print(f"  - {item}")

    expected = info.get("expected", [])
    if expected:
        console.print()
        console.print("[bold]Expected telemetry[/bold]")
        for item in expected:
            console.print(f"  - {item}")

    tool_help = status.get("help")
    if tool_help:
        console.print()
        console.print("[bold]Tool setup[/bold]")
        console.print(f"  {tool_help}")

    if status.get("path"):
        console.print(f"  Path: {status.get('path')}")
    if status.get("version"):
        console.print(f"  Version: {status.get('version')}")
    if status.get("sha256"):
        console.print(f"  SHA256: {status.get('sha256')}")

    console.print()
    console.print(
        "[yellow]PurplePOC intentionally does not print or invoke credential-"
        "extraction/domain-takeover command lines. Execute the approved lab "
        "procedure in your runbook after arming the telemetry window.[/yellow]"
    )


def run_guided(step, context, interactive=True):
    tool = step.get("tool")

    tool_status = (
        get_tool_status(tool)
        if tool and tool != "operator-approved"
        else {
            "status": "OPERATOR_APPROVED",
            "tool": tool or "operator-approved"
        }
    )

    text = (
        f"[bold]Technique[/bold]   {step.get('technique')}\n"
        f"[bold]Name[/bold]        {step.get('name')}\n"
        f"[bold]Mode[/bold]        GUIDED\n"
        f"[bold]Tool[/bold]        {tool or 'operator-approved'}\n"
        f"[bold]Tool Status[/bold] {tool_status.get('status')}\n"
        f"[bold]Runbook[/bold]     {step.get('runbook')}\n"
        f"[bold]Target[/bold]      {context.get('target', 'N/A')}\n"
        f"[bold]Domain[/bold]      {context.get('domain', 'N/A')}"
    )

    console.print(Panel(text, title="PurplePOC Guided Test"))
    _show_help(step, tool_status)

    if not interactive:
        console.print(
            "[yellow]Unattended mode: GUIDED step recorded as SKIPPED.[/yellow]"
        )
        return {"status": "SKIPPED", "note": "non-interactive"}

    while True:
        choices = ["help", "arm", "skip", "skip-all", "quit"]

        if tool_status.get("path"):
            choices.insert(1, "open-tool")

        if tool_status.get("source_url"):
            choices.insert(2, "open-source")

        choice = Prompt.ask(
            "Action",
            choices=choices,
            default="help"
        )

        if choice == "help":
            _show_help(step, tool_status)
            continue

        if choice == "open-tool":
            if not _open_tool_path(tool_status):
                console.print("[red]Unable to open tool folder.[/red]")
            continue

        if choice == "open-source":
            if not _open_source(tool_status):
                console.print("[red]Unable to open official tool source.[/red]")
            continue

        if choice == "skip":
            return {"status": "SKIPPED"}

        if choice == "skip-all":
            now = datetime.now(timezone.utc)
            return {
                "status": "SKIPPED",
                "skip_all_guided": True,
                "started": now,
                "ended": now,
                "note": "operator skipped all remaining guided tests"
            }

        if choice == "quit":
            now = datetime.now(timezone.utc)
            return {
                "status": "ABORTED",
                "stop_scenario": True,
                "started": now,
                "ended": now,
                "note": "operator requested scenario stop"
            }

        break

    start = datetime.now(timezone.utc)

    console.print()
    console.print(f"[green]Telemetry armed at {start.isoformat()}[/green]")
    console.print(
        "[bold]Now execute the approved lab procedure using the staged tool/runbook.[/bold]"
    )

    input("Press ENTER after the operator-run test is finished...")

    result = Prompt.ask(
        "Operator result",
        choices=[
            "completed",
            "prevented",
            "failed",
            "aborted"
        ],
        default="completed"
    )

    end = datetime.now(timezone.utc)

    return {
        "status": result.upper(),
        "started": start,
        "ended": end
    }
'@
# --------------------------------------------------------------------
# adapters/atomic.py
# --------------------------------------------------------------------

Write-File "adapters\atomic.py" @'
import re
import subprocess
from pathlib import Path

import yaml

from core.cleanup import (
    register_action,
    mark_clean,
    mark_failed,
)


ROOT = Path(__file__).resolve().parents[1]


class AtomicPolicyError(RuntimeError):
    pass


def load_config():
    with open(ROOT / "config.yaml", "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def atomic_root():
    return ROOT / "tools" / "atomic-red-team" / "atomics"


def configured_tests():
    config = load_config()
    return config.get("atomic", {}).get("tests", [])


def allowed_test(technique, guid):
    for item in configured_tests():
        if (
            item.get("technique") == technique
            and str(item.get("guid", "")).lower() == str(guid).lower()
        ):
            return item

    return None


def validate_test(technique, guid):
    item = allowed_test(technique, guid)

    if not item:
        raise AtomicPolicyError(
            f"Atomic test is not allowlisted: {technique} / {guid}"
        )

    return item


def _powershell(script, timeout=600):
    p = subprocess.run(
        [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            script,
        ],
        capture_output=True,
        text=True,
        shell=False,
        timeout=timeout,
    )

    return {
        "exit_code": p.returncode,
        "stdout": p.stdout,
        "stderr": p.stderr,
    }


def _error_markers(stdout, stderr):
    blob = f"{stdout or ''}\n{stderr or ''}"

    patterns = [
        r"\bCommandNotFoundException\b",
        r"\bAccess is denied\b",
        r"\bFAILED\s+\d+",
        r"\bnot recognized as the name of a cmdlet\b",
        r"\bno valid module file was found\b",
        r"\bException calling\b",
        r"\bFullyQualifiedErrorId\b.*(?:CommandNotFoundException|UnauthorizedAccess|Win32Exception)",
    ]

    return [
        pattern
        for pattern in patterns
        if re.search(pattern, blob, re.IGNORECASE)
    ]


def get_prereqs(technique, guid):
    validate_test(technique, guid)
    root = atomic_root()

    script = f'''Import-Module invoke-atomicredteam -Force

Invoke-AtomicTest "{technique}" `
    -TestGuids "{guid}" `
    -GetPrereqs `
    -PathToAtomicsFolder "{root}" `
    -Confirm:$false
'''

    return _powershell(script, timeout=600)


def execute(technique, guid, test_id=None):
    test_meta = validate_test(technique, guid)

    config = load_config()
    atomic_cfg = config.get("atomic", {})
    root = atomic_root()

    cleanup_command = (
        'Import-Module invoke-atomicredteam -Force; '
        f'Invoke-AtomicTest "{technique}" '
        f'-TestGuids "{guid}" -Cleanup '
        f'-PathToAtomicsFolder "{root}" -Confirm:$false'
    )

    cleanup_id = register_action(
        kind="atomic",
        description=(
            f"Atomic cleanup for {technique} / "
            f"{test_meta.get('name', guid)}"
        ),
        cleanup_command=[
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            cleanup_command,
        ],
        test_id=test_id,
        metadata={
            "technique": technique,
            "guid": guid,
            "name": test_meta.get("name"),
        },
    )

    if atomic_cfg.get("auto_get_prereqs", True):
        prereq = get_prereqs(technique, guid)

        if prereq["exit_code"] != 0:
            mark_failed(
                cleanup_id,
                prereq.get("stderr")
                or prereq.get("stdout")
                or f"exit code {prereq['exit_code']}"
            )

            return {
                "exit_code": prereq["exit_code"],
                "stdout": prereq["stdout"],
                "stderr": "Atomic prerequisite setup failed.\n" + prereq["stderr"],
                "atomic_guid": guid,
                "atomic_name": test_meta.get("name"),
                "atomic_status": "PREREQ_FAILED",
                "error_markers": [],
            }

    script = f'''Import-Module invoke-atomicredteam -Force

Invoke-AtomicTest "{technique}" `
    -TestGuids "{guid}" `
    -PathToAtomicsFolder "{root}" `
    -Confirm:$false
'''

    result = _powershell(script, timeout=600)
    result["atomic_guid"] = guid
    result["atomic_name"] = test_meta.get("name")

    markers = _error_markers(
        result.get("stdout"),
        result.get("stderr")
    )
    result["error_markers"] = markers

    if markers and result["exit_code"] == 0:
        result["exit_code"] = 1
        result["atomic_status"] = "EXECUTION_ERROR"
    elif result["exit_code"] == 0:
        result["atomic_status"] = "COMPLETED"
    else:
        result["atomic_status"] = "FAILED"

    if atomic_cfg.get("cleanup_after_test", True):
        cleanup_script = f'''Import-Module invoke-atomicredteam -Force

Invoke-AtomicTest "{technique}" `
    -TestGuids "{guid}" `
    -Cleanup `
    -PathToAtomicsFolder "{root}" `
    -Confirm:$false
'''

        cleanup = _powershell(cleanup_script, timeout=600)

        result["stdout"] += (
            "\n\n[Atomic Cleanup]\n"
            + cleanup.get("stdout", "")
        )

        if cleanup.get("stderr"):
            result["stderr"] += (
                "\n\n[Atomic Cleanup]\n"
                + cleanup["stderr"]
            )

        cleanup_markers = _error_markers(
            cleanup.get("stdout"),
            cleanup.get("stderr")
        )

        if cleanup["exit_code"] == 0 and not cleanup_markers:
            mark_clean(cleanup_id)
            result["cleanup_status"] = "CLEAN"
        else:
            mark_failed(
                cleanup_id,
                cleanup.get("stderr")
                or cleanup.get("stdout")
                or f"exit code {cleanup['exit_code']}"
            )
            result["cleanup_status"] = "FAILED"
    else:
        result["cleanup_status"] = "PENDING"

    return result
'@
# --------------------------------------------------------------------
# connectors/base.py
# --------------------------------------------------------------------

Write-File "connectors\base.py" @'
class BaseConnector:
    name = "base"

    def collect(
        self,
        host,
        start,
        end,
        technique
    ):
        return {
            "source": self.name,
            "telemetry_seen": False,
            "alert_seen": False,
            "prevented": False,
            "alert_id": None,
            "severity": None,
            "first_seen": None,
            "raw": {}
        }
'@

# --------------------------------------------------------------------
# connectors/qradar.py
# --------------------------------------------------------------------

Write-File "connectors\qradar.py" @'
import os
import time
import requests

from connectors.base import BaseConnector


class QRadarConnector(BaseConnector):
    name = "qradar"

    def __init__(
        self,
        host,
        token_env,
        verify_ssl=False
    ):
        token = os.getenv(token_env)

        if not token:
            raise RuntimeError(
                f"Environment variable missing: {token_env}"
            )

        self.host = host.rstrip("/")

        self.session = requests.Session()

        self.session.verify = verify_ssl

        self.session.headers.update({
            "SEC": token,
            "Accept": "application/json"
        })

    def create_search(self, aql):
        r = self.session.post(
            f"{self.host}/api/ariel/searches",
            data={
                "query_expression": aql
            },
            timeout=30
        )

        r.raise_for_status()

        return r.json()["search_id"]

    def wait(self, search_id):
        for _ in range(120):
            r = self.session.get(
                f"{self.host}/api/ariel/searches/{search_id}",
                timeout=30
            )

            r.raise_for_status()

            status = r.json().get("status")

            if status == "COMPLETED":
                return

            if status in (
                "ERROR",
                "CANCELED"
            ):
                raise RuntimeError(
                    f"QRadar Ariel status: {status}"
                )

            time.sleep(1)

        raise TimeoutError(
            "QRadar Ariel search timeout"
        )

    def collect(
        self,
        host,
        start,
        end,
        technique
    ):
        start_ms = int(
            start.timestamp() * 1000
        )

        end_ms = int(
            end.timestamp() * 1000
        )

        safe_host = (
            host
            .replace("'", "")
            .replace("%", "")
        )

        aql = f"""
SELECT
    starttime,
    qidname(qid) AS event_name,
    username,
    sourceip,
    destinationip,
    LOGSOURCENAME(logsourceid) AS log_source
FROM events
WHERE
    starttime BETWEEN {start_ms} AND {end_ms}
AND
    UTF8(payload) ILIKE '%{safe_host}%'
ORDER BY starttime
"""

        search_id = self.create_search(
            aql
        )

        self.wait(
            search_id
        )

        r = self.session.get(
            f"{self.host}/api/ariel/searches/{search_id}/results",
            timeout=30
        )

        r.raise_for_status()

        events = r.json().get(
            "events",
            []
        )

        return {
            "source": "qradar",
            "telemetry_seen": len(events) > 0,
            "alert_seen": False,
            "prevented": False,
            "alert_id": None,
            "severity": None,
            "first_seen": None,
            "raw": {
                "events": events
            }
        }
'@

# --------------------------------------------------------------------
# core/reporting.py
# --------------------------------------------------------------------

Write-File "core\reporting.py" @'
import csv
import html
import json
import os
import sqlite3
from pathlib import Path

from core.detection import evaluate, load_expectations


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "PurplePOC"
DB = RUNTIME / "data" / "purplepoc.db"
REPORT_ROOT = ROOT / "reports"


VERDICT_LABEL = {
    "DETECTED": "DETECTED",
    "MISSED": "MISSED",
    "NO_EXPECTATION": "N/A",
    "NOT_EXECUTED": "not executed",
}

VERDICT_COLOR = {
    "DETECTED": "#065f46",
    "MISSED": "#7f1d1d",
    "NO_EXPECTATION": "#374151",
    "NOT_EXECUTED": "#374151",
}


import yaml

def _events_for(observation_rows):
    by_step = {}

    for obs in observation_rows:
        step_id = obs["step_id"]

        try:
            raw = json.loads(obs["raw_json"] or "{}")
        except Exception:
            raw = {}

        events = raw.get("events") or []
        by_step.setdefault(step_id, []).extend(events)

    return by_step


def _escape_pre(value):
    return html.escape(str(value or ""))


def _atomic_detail_from_output(row):
    stdout = row.get("stdout") or ""
    stderr = row.get("stderr") or ""

    executed = []
    cleanup = []
    notable = []

    for raw in stdout.splitlines():
        line = raw.strip()

        if not line:
            continue

        if line.startswith("Executing test:"):
            executed.append(line.replace("Executing test:", "", 1).strip())
        elif line.startswith("Done executing test:"):
            notable.append(line)
        elif line.startswith("Executing cleanup for test:"):
            cleanup.append(
                line.replace("Executing cleanup for test:", "", 1).strip()
            )
        elif line.startswith("Done executing cleanup for test:"):
            notable.append(line)
        elif (
            "SUCCESS" in line
            or "FAILED" in line
            or "ReturnValue =" in line
            or "ProcessId =" in line
            or "Hello, from PowerShell!" in line
        ):
            notable.append(line)

    return {
        "guid": row.get("atomic_guid") or "",
        "executed": executed,
        "cleanup": cleanup,
        "notable": notable[:12],
        "stdout": stdout,
        "stderr": stderr,
    }



def _guided_followup(row):
    tid = str(row.get("id") or row.get("scenario_id") or "")
    stdout = str(row.get("stdout") or "").strip()
    mapping = {
      "ad_spn_discovery": ("Kerberos service-account validation","Impacket","Use the AUTO-discovered SPN accounts as the candidate set for the existing operator-guided Kerberos validation.","Review the returned accounts, select only authorized targets, continue with the matching GUIDED Kerberos workflow, and correlate DC 4769 plus endpoint/network telemetry."),
      "ad_asrep_candidate_discovery": ("AS-REP candidate validation","Impacket","AUTO identified accounts configured without Kerberos pre-authentication; these are candidate objects for controlled validation.","Confirm scope, continue with the matching GUIDED Kerberos workflow, and inspect DC 4768 plus endpoint/network telemetry."),
      "ad_unconstrained_delegation": ("Delegation exposure validation","Impacket / native AD","Use discovered unconstrained-delegation principals as context for an operator-approved Kerberos validation.","Review the returned principals, select an authorized target, then continue with the GUIDED delegation workflow."),
      "ad_constrained_delegation": ("Constrained delegation validation","Impacket / native AD","Use the discovered constrained-delegation relationships to decide which authorized path warrants deeper validation.","Review principals/services, choose an in-scope path, then continue with the GUIDED Kerberos workflow."),
      "ad_rbcd_discovery": ("RBCD security review","Impacket / ldap3","AUTO found existing RBCD configuration; use it to review whether the relationship is intended and security-relevant.","Inspect the returned objects/relationship. Continue with the GUIDED RBCD review only for an authorized target; monitor 5136/4662 and Kerberos telemetry."),
      "ad_gpo_discovery": ("GPO follow-up review","Native Windows / ldap3","Use discovered GPO objects as input for controlled policy/SYSVOL monitoring validation.","Select an in-scope GPO and continue with the relevant GUIDED policy/SYSVOL test; inspect 5136, 5140 and 5145 where applicable."),
      "ad_admincount_discovery": ("Privileged-account follow-up","ldap3 / Impacket","Use the privileged-account inventory as targeting context for higher-sensitivity authentication/Kerberos detection validation.","Review returned accounts and use only authorized test identities in the matching GUIDED workflow."),
      "ad_computer_inventory": ("Lateral-movement target selection","Impacket / native Windows","Use the computer inventory as a controlled target list for the existing SMB/WMI/WinRM validation workflows.","Choose an authorized lab host, continue with the appropriate GUIDED lateral-movement test, and correlate 4624/4688/5140/5145 plus Sysmon."),
      "ad_rootdse": ("AD context for guided tests","ldap3 / native Windows","Carry the discovered naming contexts and DC identity into later domain-aware validation.","Confirm that the returned domain/DC is the intended authorized environment before starting GUIDED AD scenarios.")
    }
    item=mapping.get(tid)
    if not item:
        return ""
    title,tool,purpose,operator=item
    candidates=html.escape(stdout) if stdout else "No candidate objects were returned by this AUTO step."
    return f"""
<details class="guided-handoff report-section" open>
 <summary>Next manual validation</summary>
 <div class="section-body">
  <div class="handoff-grid"><div><span class="label">GUIDED WORKFLOW</span><strong>{html.escape(title)}</strong></div><div><span class="label">TOOL</span><strong>{html.escape(tool)}</strong></div></div>
  <p><strong>Why continue:</strong> {html.escape(purpose)}</p>
  <p><strong>What to do:</strong> {html.escape(operator)}</p>
  <p><strong>Tool note:</strong> The named tool is prepared as operator support for the related protocol/directory validation; PurplePOC does not automatically perform credential extraction or domain-impacting changes from this handoff.</p>
  <details class="candidate-results"><summary>AUTO results to use as GUIDED input</summary><pre>{candidates}</pre></details>
 </div>
</details>
"""

def _detail_block(row):
    is_atomic = (row.get("backend") == "atomic")
    atomic = _atomic_detail_from_output(row) if is_atomic else None

    expected = " ".join(str(x) for x in row.get("expected_events", [])) or "-"
    observed = " ".join(str(x) for x in row.get("matched_events", [])) or "-"

    meta = f"""
<div class="detail-grid">
  <div><span class="label">Test ID</span><span>{html.escape(str(row.get('test_id') or ''))}</span></div>
  <div><span class="label">MITRE</span><span>{html.escape(str(row.get('technique') or ''))}</span></div>
  <div><span class="label">Tactic</span><span>{html.escape(str(row.get('tactic') or 'uncategorized').replace('_', ' ').title())}</span></div>
  <div><span class="label">Mode</span><span>{html.escape(str(row.get('mode') or ''))}</span></div>
  <div><span class="label">Backend</span><span>{html.escape(str(row.get('backend') or 'native'))}</span></div>
  <div><span class="label">Action</span><span>{html.escape(str(row.get('action') or '-'))}</span></div>
  <div><span class="label">Tool</span><span>{html.escape(str(row.get('tool') or '-'))}</span></div>
  <div><span class="label">Target</span><span>{html.escape(str(row.get('target') or '-'))}</span></div>
  <div><span class="label">Expected events</span><span>{html.escape(expected)}</span></div>
  <div><span class="label">Observed events</span><span>{html.escape(observed)}</span></div>
</div>
"""

    description = html.escape(str(row.get("description") or "No analyst description defined."))
    siem_events = html.escape(", ".join(str(x) for x in (row.get("siem_event_ids") or [])) or "-")
    siem_logic = html.escape(str(row.get("siem_logic") or "No SIEM rule logic defined."))

    execution = row.get("execution_details") or {}

    def detail_value(key, fallback="-"):
        return html.escape(str(execution.get(key) or fallback))

    command = detail_value("command")
    network_value = detail_value("network")

    detection_sources = row.get("detection_sources") or {}

    def source_list(key):
        values = detection_sources.get(key) or []
        if not values:
            return '<span class="muted">Not primary for this test</span>'
        return "<ul>" + "".join(
            f"<li>{html.escape(str(value))}</li>"
            for value in values
        ) + "</ul>"

    correlation_logic = html.escape(str(detection_sources.get("correlation") or "-"))
    enrichment_values = detection_sources.get("enrichment") or []
    enrichment_html = ", ".join(html.escape(str(x)) for x in enrichment_values) or "-"

    protocols_ports = detection_sources.get("protocols_ports") or []
    protocols_html = (
        "<ul>" + "".join(f"<li>{html.escape(str(x))}</li>" for x in protocols_ports) + "</ul>"
        if protocols_ports
        else '<span class="muted">No protocol/port guidance defined.</span>'
    )

    recipe = detection_sources.get("analyst_recipe") or {}
    recipe_steps = recipe.get("steps") or []
    recipe_steps_html = (
        "<ol class=\"recipe-steps\">" +
        "".join(f"<li>{html.escape(str(x))}</li>" for x in recipe_steps) +
        "</ol>"
        if recipe_steps else '<span class="muted">No analyst recipe defined.</span>'
    )
    minimum_fields = recipe.get("minimum_fields") or []
    minimum_fields_html = ", ".join(html.escape(str(x)) for x in minimum_fields) or "-"
    evidence_items = recipe.get("evidence") or []
    evidence_html = (
        "<ul>" + "".join(f"<li>{html.escape(str(x))}</li>" for x in evidence_items) + "</ul>"
        if evidence_items else "-"
    )
    fp_items = recipe.get("false_positive_checks") or []
    fp_html = (
        "<ul>" + "".join(f"<li>{html.escape(str(x))}</li>" for x in fp_items) + "</ul>"
        if fp_items else "-"
    )
    recipe_window = html.escape(str(recipe.get("time_window") or "-"))

    cookbook_html = f"""
<details class="cookbook-box report-section" open>
  <summary>Analyst cookbook - build & validate the SIEM rule</summary>
  <div class="section-body">
    <div class="cookbook-top">
      <div class="protocol-card">
        <span class="label">PROTOCOLS / PORTS</span>
        {protocols_html}
      </div>
      <div class="window-card">
        <span class="label">CORRELATION WINDOW</span>
        <strong>{recipe_window}</strong>
        <span class="hint">Use the PurplePOC test timestamp as the center of the validation window.</span>
      </div>
    </div>
    <div class="recipe-card">
      <span class="label">STEP-BY-STEP</span>
      {recipe_steps_html}
    </div>
    <div class="cookbook-grid">
      <div>
        <span class="label">MINIMUM FIELDS TO EXTRACT / NORMALIZE</span>
        <div class="mono recipe-fields">{minimum_fields_html}</div>
      </div>
      <div>
        <span class="label">EVIDENCE TO ATTACH TO THE OFFENSE</span>
        {evidence_html}
      </div>
      <div>
        <span class="label">FALSE-POSITIVE CHECKS</span>
        {fp_html}
      </div>
    </div>
  </div>
</details>
"""

    multisource_html = f"""
<details class="multisource-box report-section" open>
  <summary>Detection sources & SIEM correlation</summary>
  <div class="section-body">
    <div class="source-grid">
      <div class="source-card endpoint"><h5>Endpoint / EDR</h5>{source_list("endpoint")}</div>
      <div class="source-card addc"><h5>AD / Domain Controller</h5>{source_list("ad_dc")}</div>
      <div class="source-card network"><h5>Network / Firewall / NDR</h5>{source_list("network")}</div>
      <div class="source-card application"><h5>Application / DNS / Proxy / Cloud</h5>{source_list("application")}</div>
    </div>
    <div class="correlation-card"><span class="label">SIEM CORRELATION LOGIC</span><div>{correlation_logic}</div></div>
    <div class="correlation-card"><span class="label">KEY ENRICHMENT FIELDS</span><div class="mono">{enrichment_html}</div></div>
  </div>
</details>
"""

    analyst_html = f"""
<details class="analyst-box report-section" open>
  <summary>What this test does</summary>
  <div class="section-body"><p>{description}</p></div>
</details>
<details class="execution-box report-section">
  <summary>Exact PurplePOC execution plan</summary>
  <div class="section-body">
  <div class="exec-grid">
    <div><span class="label">Source process</span><span>{detail_value("process")}</span></div>
    <div><span class="label">Input / source</span><span class="mono">{detail_value("input")}</span></div>
    <div><span class="label">Operation</span><span>{detail_value("operation")}</span></div>
    <div><span class="label">Destination</span><span class="mono">{detail_value("destination")}</span></div>
    <div><span class="label">Network action / target</span><span>{network_value}</span></div>
    <div><span class="label">Artifacts created / touched</span><span>{detail_value("artifacts")}</span></div>
    <div><span class="label">Implementation</span><span class="mono">{detail_value("implementation")}</span></div>
    <div><span class="label">Purpose</span><span>{detail_value("purpose")}</span></div>
  </div>
  <details class="command-details">
    <summary>Show exact command / Atomic invocation</summary>
    <pre>{command}</pre>
  </details>
  </div>
</details>
{multisource_html}
{cookbook_html}
<details class="siem-box report-section">
  <summary>Suggested SIEM detection</summary>
  <div class="section-body">
  <div class="siem-events"><span class="label">Relevant Event IDs / telemetry</span><span class="mono">{siem_events}</span></div>
  <div class="siem-logic"><span class="label">Correlation logic</span><span>{siem_logic}</span></div>
  <div class="telemetry-note"><strong>Important:</strong> Event IDs above are detection-relevant telemetry, not a guarantee that this exact simulation emits every event. Use the Execution Plan's network/operation fields to see what this test actually generates.</div>
  </div>
</details>
"""

    atomic_html = ""

    if atomic:
        executed = (
            "<ul>" +
            "".join(
                f"<li>{html.escape(item)}</li>"
                for item in atomic["executed"]
            ) +
            "</ul>"
            if atomic["executed"]
            else "<p class=\"muted\">No Atomic execution line parsed.</p>"
        )

        notable = (
            "<ul>" +
            "".join(
                f"<li>{html.escape(item)}</li>"
                for item in atomic["notable"]
            ) +
            "</ul>"
            if atomic["notable"]
            else "<p class=\"muted\">No notable Atomic output parsed.</p>"
        )

        atomic_html = f"""
<div class="atomic-box">
  <h4>Atomic Red Team details</h4>
  <div class="detail-grid">
    <div><span class="label">Atomic GUID</span><span class="mono">{html.escape(atomic['guid'])}</span></div>
    <div><span class="label">Exact test</span><span>{executed}</span></div>
  </div>
  <h5>Notable execution output</h5>
  {notable}
</div>
"""

    stdout = row.get("stdout") or ""
    stderr = row.get("stderr") or ""

    stdout_html = (
        f"<pre>{_escape_pre(stdout)}</pre>"
        if stdout
        else "<p class=\"muted\">No stdout captured.</p>"
    )

    stderr_html = (
        f"<pre class=\"error-pre\">{_escape_pre(stderr)}</pre>"
        if stderr
        else "<p class=\"muted\">No stderr captured.</p>"
    )

    return f"""
<details class="test-details">
  <summary>View execution details</summary>
  {meta}
  {analyst_html}
  {atomic_html}
  {_guided_followup(row)}
  <details class="nested-details">
    <summary>Raw stdout</summary>
    {stdout_html}
  </details>
  <details class="nested-details">
    <summary>Raw stderr</summary>
    {stderr_html}
  </details>
</details>
"""


def _write_report_crash(run_id, exc):
    try:
        logs = ROOT / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        path = logs / f"report-crash-{run_id}.log"
        import traceback
        path.write_text(
            traceback.format_exc(),
            encoding="utf-8",
            errors="replace",
        )
        return path
    except Exception:
        return None


def generate(run_id):
    out = REPORT_ROOT / run_id
    out.mkdir(parents=True, exist_ok=True)

    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row

    run = con.execute(
        "SELECT * FROM runs WHERE id=?",
        (run_id,)
    ).fetchone()

    steps = con.execute(
        "SELECT * FROM steps WHERE run_id=? ORDER BY started",
        (run_id,)
    ).fetchall()

    observations = con.execute("""
        SELECT observations.*
        FROM observations
        JOIN steps
        ON observations.step_id = steps.id
        WHERE steps.run_id=?
    """, (run_id,)).fetchall()

    con.close()

    expectations = load_expectations()
    events_by_step = _events_for(observations)

    summary = {
        "DETECTED": 0,
        "MISSED": 0,
        "NO_EXPECTATION": 0,
        "NOT_EXECUTED": 0,
    }

    step_rows = []

    for step in steps:
        events = events_by_step.get(step["id"], [])

        detection = evaluate(
            step["technique"],
            step["status"],
            events,
            expectations
        )

        summary[detection["verdict"]] = (
            summary.get(detection["verdict"], 0) + 1
        )

        row = dict(step)
        row["detection"] = detection["verdict"]
        row["expected_events"] = detection["expected"]
        row["matched_events"] = detection["matched"]
        row["prevented"] = detection["prevented"]
        step_rows.append(row)

    scored = summary["DETECTED"] + summary["MISSED"]

    detection_rate = (
        round(100.0 * summary["DETECTED"] / scored, 1)
        if scored else None
    )

    # Attach analyst documentation from scenario YAML to every result row.
    scenario_meta = {}
    try:
        scenario_path = ROOT / "scenarios" / "full.yaml"
        scenario_doc = yaml.safe_load(scenario_path.read_text(encoding="utf-8")) or {}
        for index, item in enumerate(scenario_doc.get("steps", []), start=1):
            scenario_meta[f"T-{index:03d}"] = item
    except Exception:
        scenario_meta = {}

    for row in step_rows:
        item = scenario_meta.get(str(row.get("test_id") or ""), {})
        row["description"] = item.get("description") or "No analyst description defined."
        row["execution_details"] = item.get("execution_details") or {}
        row["detection_sources"] = item.get("detection_sources") or {}
        rule = item.get("siem_rule") or {}
        row["siem_event_ids"] = rule.get("event_ids") or []
        row["siem_logic"] = rule.get("logic") or "No SIEM rule logic defined."

    evidence_root = out / "evidence"
    evidence_root.mkdir(parents=True, exist_ok=True)

    for row in step_rows:
        test_id = row.get("test_id") or row["id"]
        step_dir = evidence_root / test_id
        step_dir.mkdir(parents=True, exist_ok=True)

        with open(
            step_dir / "metadata.json",
            "w",
            encoding="utf-8"
        ) as f:
            json.dump(row, f, indent=2)

        stdout = row.get("stdout") or ""
        stderr = row.get("stderr") or ""

        if stdout:
            (step_dir / "stdout.txt").write_text(
                stdout,
                encoding="utf-8",
                errors="replace"
            )

        if stderr:
            (step_dir / "stderr.txt").write_text(
                stderr,
                encoding="utf-8",
                errors="replace"
            )

    from core.cleanup import summary as cleanup_summary

    csum = cleanup_summary()

    with open(
        out / "cleanup-report.json",
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(
            csum,
            f,
            indent=2
        )

    data = {
        "run": dict(run),
        "detection_summary": {
            **summary,
            "scored": scored,
            "detection_rate_percent": detection_rate,
        },
        "steps": step_rows,
        "observations": [dict(x) for x in observations],
    }

    with open(
        out / "report.json",
        "w",
        encoding="utf-8"
    ) as f:
        json.dump(data, f, indent=2)

    csv_fields = [
        "test_id", "technique", "tactic", "name", "mode", "status",
        "exit_code", "evidence_count", "duration_seconds",
        "detection", "expected_events", "matched_events", "target"
    ]

    with open(
        out / "techniques.csv",
        "w",
        newline="",
        encoding="utf-8"
    ) as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()

        for row in step_rows:
            writer.writerow({
                "test_id": row.get("test_id") or "",
                "technique": row["technique"],
                "tactic": row.get("tactic") or "",
                "name": row["name"],
                "mode": row["mode"],
                "status": row["status"],
                "exit_code": row.get("exit_code"),
                "evidence_count": row.get("evidence_count") or 0,
                "duration_seconds": row.get("duration_seconds") or 0,
                "detection": row["detection"],
                "expected_events": " ".join(
                    str(x) for x in row["expected_events"]
                ),
                "matched_events": " ".join(
                    str(x) for x in row["matched_events"]
                ),
                "target": row["target"] or "",
            })

    rows = []
    previous_tactic = None

    for row in step_rows:
        tactic = row.get("tactic") or "uncategorized"

        if tactic != previous_tactic:
            previous_tactic = tactic
            tactic_title = tactic.replace("_", " ").upper()
            rows.append(
                "<tr class=\"tactic-row\">"
                f"<td colspan=\"12\">{html.escape(tactic_title)}</td>"
                "</tr>"
            )

        verdict = row["detection"]
        color = VERDICT_COLOR.get(verdict, "#374151")
        label = VERDICT_LABEL.get(verdict, verdict)
        prevented = " (prevented)" if row["prevented"] else ""

        detail_html = _detail_block(row)

        rows.append(
            "<tr class=\"main-row\">"
            f"<td>{html.escape(str(row.get('test_id') or ''))}</td>"
            f"<td>{html.escape(str(row['technique']))}</td>"
            f"<td>{html.escape(str(row.get('tactic') or '').replace('_', ' ').title())}</td>"
            f"<td>{html.escape(str(row['name']))}</td>"
            f"<td>{html.escape(str(row['mode']))}</td>"
            f"<td>{html.escape(str(row['status']))}</td>"
            f"<td>{html.escape(str(row.get('exit_code') if row.get('exit_code') is not None else ''))}</td>"
            f"<td>{html.escape(str(row.get('evidence_count') or 0))}</td>"
            f"<td>{html.escape(str(round(row.get('duration_seconds') or 0, 2)))}</td>"
            f"<td><span class=\"pill\" style=\"background:{color}\">"
            f"{html.escape(label)}{prevented}</span></td>"
            f"<td>{html.escape(' '.join(str(x) for x in row['expected_events']))}</td>"
            f"<td>{html.escape(' '.join(str(x) for x in row['matched_events']))}</td>"
            "</tr>"
            "<tr class=\"detail-row\">"
            f"<td colspan=\"12\">{detail_html}</td>"
            "</tr>"
        )

    rate_text = (
        f"{detection_rate}% ({summary['DETECTED']}/{scored})"
        if detection_rate is not None else "n/a"
    )

    # Dashboard data is rendered with dependency-free HTML/CSS so reports remain
    # fully self-contained and work offline on assessment hosts.
    tactic_order = [
        "discovery", "execution", "persistence", "privilege_escalation",
        "defense_evasion", "credential_access", "lateral_movement", "exfiltration",
        "collection", "command_and_control", "uncategorized"
    ]
    tactic_labels = {
        "discovery": "Discovery", "execution": "Execution", "persistence": "Persistence",
        "privilege_escalation": "Privilege Escalation", "defense_evasion": "Defense Evasion",
        "credential_access": "Credential Access", "lateral_movement": "Lateral Movement",
        "exfiltration": "Exfiltration", "collection": "Collection",
        "command_and_control": "Command & Control", "uncategorized": "Other"
    }
    tactic_colors = {
        "discovery": "#3b82f6", "execution": "#8b5cf6", "persistence": "#14b8a6",
        "privilege_escalation": "#f97316", "defense_evasion": "#eab308",
        "credential_access": "#ec4899", "lateral_movement": "#2563eb",
        "exfiltration": "#06b6d4", "collection": "#a855f7",
        "command_and_control": "#f43f5e", "uncategorized": "#64748b"
    }
    # Never silently drop a tactic from the report. Append any tactic found in
    # stored step rows that is not in the preferred ATT&CK display order.
    observed_tactics = []
    for row in step_rows:
        key = row.get("tactic") or "uncategorized"
        if key not in observed_tactics:
            observed_tactics.append(key)

    for key in observed_tactics:
        if key not in tactic_order:
            tactic_order.append(key)
            tactic_labels[key] = key.replace("_", " ").title()
            tactic_colors[key] = "#64748b"

    tactic_stats = {}
    for key in tactic_order:
        members = [r for r in step_rows if (r.get("tactic") or "uncategorized") == key]
        if not members:
            continue
        tactic_stats[key] = {
            "total": len(members),
            "detected": sum(r["detection"] == "DETECTED" for r in members),
            "missed": sum(r["detection"] == "MISSED" for r in members),
            "not_executed": sum(r["detection"] == "NOT_EXECUTED" for r in members),
            "no_expectation": sum(r["detection"] == "NO_EXPECTATION" for r in members),
        }

    tactic_legend = "".join(
        f'<div class="legend-row"><span class="dot" style="background:{tactic_colors[k]}"></span>'
        f'<span>{html.escape(tactic_labels[k])}</span><b>{v["total"]}</b></div>'
        for k, v in tactic_stats.items()
    )
    total_tests = max(1, len(step_rows))
    tactic_segments = "".join(
        f'<span title="{html.escape(tactic_labels[k])}: {v["total"]}" style="width:{100*v["total"]/total_tests:.2f}%;background:{tactic_colors[k]}"></span>'
        for k, v in tactic_stats.items()
    )

    expected_counts = [len(r.get("expected_events") or []) for r in step_rows if r["detection"] != "NO_EXPECTATION"]
    buckets = [("1", 0), ("2-3", 0), ("4-9", 0), ("10+", 0)]
    bucket_values = [0, 0, 0, 0]
    for n in expected_counts:
        idx = 0 if n <= 1 else 1 if n <= 3 else 2 if n <= 9 else 3
        bucket_values[idx] += 1
    max_bucket = max(bucket_values or [1]) or 1
    expected_bars = "".join(
        f'<div class="bar-col"><div class="bar-value">{value}</div><div class="bar" style="height:{max(4, 112*value/max_bucket):.0f}px"></div><div class="bar-label">{label}</div></div>'
        for (label, _), value in zip(buckets, bucket_values)
    )

    # Group result rows into expandable MITRE tactic sections.
    grouped_html = []
    for key in tactic_order:
        members = [r for r in step_rows if (r.get("tactic") or "uncategorized") == key]
        if not members:
            continue
        stat = tactic_stats[key]
        member_rows = []
        for row in members:
            verdict = row["detection"]
            color = VERDICT_COLOR.get(verdict, "#374151")
            label = VERDICT_LABEL.get(verdict, verdict)
            prevented = " (prevented)" if row["prevented"] else ""
            member_rows.append(
                '<tr class="main-row">'
                f'<td>{html.escape(str(row.get("test_id") or ""))}</td>'
                f'<td>{html.escape(str(row["technique"]))}</td>'
                f'<td>{html.escape(str(row["name"]))}</td>'
                f'<td>{html.escape(str(row["mode"]))}</td>'
                f'<td><span class="status {str(row["status"]).lower()}">{html.escape(str(row["status"]))}</span></td>'
                f'<td>{html.escape(str(row.get("exit_code") if row.get("exit_code") is not None else ""))}</td>'
                f'<td>{html.escape(str(row.get("evidence_count") or 0))}</td>'
                f'<td>{html.escape(str(round(row.get("duration_seconds") or 0, 2)))}</td>'
                f'<td><span class="pill" style="background:{color}">{html.escape(label)}{prevented}</span></td>'
                f'<td>{html.escape(" ".join(str(x) for x in row["expected_events"]))}</td>'
                f'<td>{html.escape(" ".join(str(x) for x in row["matched_events"]))}</td>'
                '</tr>'
                '<tr class="detail-row">'
                f'<td colspan="11">{_detail_block(row)}</td></tr>'
            )
        grouped_html.append(
            f'<details class="tactic-card" open><summary style="--tactic:{tactic_colors[key]}">'
            f'<span class="tactic-title">{html.escape(tactic_labels[key])}</span><span class="count">{len(members)} tests</span>'
            f'<span class="tactic-kpis"><b class="ok">{stat["detected"]} Detected</b><b class="bad">{stat["missed"]} Missed</b>'
            f'<b>{stat["not_executed"]} Not Executed</b><b class="warn">{stat["no_expectation"]} No Expectation</b></span></summary>'
            '<div class="table-wrap"><table><thead><tr><th>Test ID</th><th>MITRE</th><th>Name</th><th>Mode</th><th>Execution</th><th>Exit</th><th>Evidence</th><th>Duration</th><th>Detection</th><th>Expected</th><th>Observed</th></tr></thead><tbody>'
            + ''.join(member_rows) + '</tbody></table></div></details>'
        )

    page = f"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PurplePOC Detection Validation Report</title>
<style>
:root {{ --bg:#0b1322; --card:#172235; --card2:#111c2d; --line:#2a3a50; --text:#edf4ff; --muted:#9fb0c7; --blue:#8ec5ff; --purple:#b993ff; }}
* {{ box-sizing:border-box }} body {{ margin:0;background:radial-gradient(circle at 25% 0,#12213a 0,#0b1322 38%);color:var(--text);font:14px/1.45 Segoe UI,Arial,sans-serif }}
.shell {{ max-width:1600px;margin:auto;padding:30px }} h1 {{ margin:0;color:#dce9ff;font-size:32px }} h2 {{ color:var(--blue);margin:0 0 14px }} .subtitle,.muted {{ color:var(--muted) }}
.hero {{ display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:22px }} .brand {{ display:flex;gap:16px;align-items:center }} .shield {{ width:48px;height:54px;display:grid;place-items:center;font-size:28px;color:#c7a8ff;background:linear-gradient(145deg,#8b5cf6,#5b21b6);clip-path:polygon(50% 0,92% 15%,85% 72%,50% 100%,15% 72%,8% 15%) }}
.rate {{ text-align:right }} .rate b {{ display:block;color:#ff4d4f;font-size:24px }} .badge {{ display:inline-block;padding:5px 12px;border-radius:999px;background:#4c1519;border:1px solid #9f2d32;color:#ffb1b1;font-weight:700 }}
.card {{ background:linear-gradient(145deg,#192638,#152033);border:1px solid #26364c;border-radius:12px;padding:20px;box-shadow:0 12px 35px #02061744 }} .meta {{ display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin-bottom:22px }} .meta .item {{ border-right:1px solid var(--line);padding:3px 14px }} .meta .item:last-child {{ border:0 }} .label {{ display:block;color:#7890ad;font-size:11px;text-transform:uppercase;letter-spacing:.06em }}
.dash {{ display:grid;grid-template-columns:1fr 1fr 1.05fr;gap:16px;margin-bottom:16px }} .chart-card {{ min-height:260px }} .chart-title {{ color:#c9a8ff;text-transform:uppercase;font-weight:800;font-size:12px;letter-spacing:.04em }}
.donut-wrap {{ display:flex;align-items:center;gap:25px;margin-top:20px }} .donut {{ width:150px;height:150px;border-radius:50%;background:conic-gradient(#22c55e 0 {100*summary['DETECTED']/max(1,len(step_rows)):.2f}%,#ef4444 0 {100*(summary['DETECTED']+summary['MISSED'])/max(1,len(step_rows)):.2f}%,#64748b 0 {100*(summary['DETECTED']+summary['MISSED']+summary['NOT_EXECUTED'])/max(1,len(step_rows)):.2f}%,#eab308 0);position:relative }} .donut:after {{ content:'';position:absolute;inset:22px;border-radius:50%;background:#172235 }} .donut-center {{ position:absolute;inset:0;z-index:2;display:grid;place-content:center;text-align:center;font-size:24px;font-weight:800 }} .donut-center small {{ font-size:12px;color:var(--muted);font-weight:400 }}
.legend {{ flex:1 }} .legend-row {{ display:grid;grid-template-columns:14px 1fr auto;gap:8px;align-items:center;margin:8px 0 }} .dot {{ width:9px;height:9px;border-radius:50% }} .segments {{ height:22px;border-radius:999px;overflow:hidden;display:flex;margin:28px 0 16px;background:#0b1220 }} .segments span {{ display:block;height:100% }}
.bars {{ height:170px;display:flex;gap:20px;align-items:flex-end;justify-content:center;margin-top:25px;border-bottom:1px solid var(--line) }} .bar-col {{ width:58px;text-align:center }} .bar {{ width:38px;margin:4px auto 7px;background:linear-gradient(#ef4444,#991b1b);border-radius:3px 3px 0 0 }} .bar-value {{ font-weight:700 }} .bar-label {{ color:var(--muted);font-size:12px }}
.note {{ margin-bottom:16px;color:var(--muted) }} .results {{ padding:20px }} .results-head {{ display:flex;justify-content:space-between;align-items:end;margin-bottom:15px }} .tactic-card {{ border:1px solid var(--line);border-radius:10px;margin:10px 0;overflow:hidden;background:#111c2d }} .tactic-card>summary {{ list-style:none;cursor:pointer;display:flex;align-items:center;gap:14px;padding:16px 18px;border-left:4px solid var(--tactic);background:#172438 }} .tactic-card>summary::-webkit-details-marker {{ display:none }} .tactic-title {{ color:var(--tactic);font-weight:900;text-transform:uppercase;font-size:16px }} .count {{ color:var(--muted) }} .tactic-kpis {{ margin-left:auto;display:flex;gap:8px }} .tactic-kpis b {{ padding:5px 10px;border:1px solid #334155;border-radius:6px;font-size:11px;color:#aab8ca }} .tactic-kpis .ok {{ color:#5ee48b;border-color:#1e6d3c }} .tactic-kpis .bad {{ color:#ff7373;border-color:#7f1d1d }} .tactic-kpis .warn {{ color:#ffd24d;border-color:#6d5510 }}
table {{ border-collapse:collapse;width:100% }} th,td {{ border-bottom:1px solid #2a3a50;padding:11px 10px;text-align:left;vertical-align:top }} th {{ color:#91c8ff;font-size:12px }} .table-wrap {{ overflow-x:auto }} .main-row:hover {{ background:#1a2a40 }} .detail-row td {{ padding:0 16px 8px }} .pill,.status {{ display:inline-block;padding:3px 9px;border-radius:999px;color:white;font-size:11px;font-weight:800 }} .status.completed {{ background:#14532d }} .status.failed {{ background:#7f1d1d }} .status.policy_blocked {{ background:#5b3b8a; color:#f1e8ff; }}\n.status.skipped {{ background:#5b21b6 }}
.test-details>summary,.nested-details>summary {{ cursor:pointer;color:#c4b5fd;font-weight:700;padding:9px 0 }} .detail-grid {{ display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px 14px;margin:10px 0 }} .detail-grid>div {{ background:#0d1727;border:1px solid #2a3a50;border-radius:7px;padding:9px 11px }} .atomic-box {{ background:#17152b;border:1px solid #6d28d9;border-radius:8px;padding:14px;margin:12px 0 }} .atomic-box h4 {{ color:#c4b5fd }} .atomic-box h5 {{ color:#93c5fd }} pre {{ white-space:pre-wrap;word-break:break-word;background:#08111f;border:1px solid #2a3a50;border-radius:7px;padding:12px;max-height:380px;overflow:auto }} .error-pre {{ border-color:#7f1d1d;color:#fecaca }} .mono {{ font-family:Consolas,monospace }}

/* v2.4 concise result headline */
.main-row td {{ background:#142238!important;border-top:6px solid #07111f!important;border-bottom:1px solid #3a4e69!important;padding:15px 11px!important;vertical-align:middle!important }}
.main-row:hover td {{ background:#1b304d!important }}
.main-row td:nth-child(6),.main-row td:nth-child(10),.main-row td:nth-child(11),
table thead th:nth-child(6),table thead th:nth-child(10),table thead th:nth-child(11) {{ display:none }}
.main-row td:nth-child(3) {{ min-width:300px;font-size:15px;font-weight:800;color:#f8fafc }}
.main-row td:nth-child(2) {{ color:#93c5fd;font-family:Consolas,monospace;font-weight:800 }}
.detail-row>td {{ border-bottom:6px solid #07111f!important;padding-bottom:18px!important }}
.report-section {{ margin:12px 0;padding:0!important;overflow:hidden }}
.report-section>summary {{ cursor:pointer;padding:13px 16px;font-weight:800;color:#e2e8f0;list-style:none }}
.report-section>summary:before {{ content:"▸";color:#93c5fd;margin-right:8px }}
.report-section[open]>summary:before {{ content:"▾" }}
.section-body {{ padding:4px 16px 15px }}


.guided-handoff {{ border:1px solid #8b5cf6!important;border-left:4px solid #a855f7!important;background:#11182b!important }}
.guided-handoff>summary {{ color:#d8b4fe!important }}
.handoff-grid {{ display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:12px }}
.handoff-grid>div {{ background:#0b1728;border:1px solid #2c4160;border-radius:7px;padding:11px }}
.handoff-grid .label {{ display:block;color:#7890ad;font-size:10px;letter-spacing:.08em;margin-bottom:5px }}
.candidate-results {{ margin-top:12px;border:1px solid #344a68;border-radius:7px;background:#081321 }}
.candidate-results>summary {{ cursor:pointer;padding:10px 12px;color:#93c5fd;font-weight:700 }}
.candidate-results pre {{ margin:0;padding:12px;max-height:260px;overflow:auto;white-space:pre-wrap }}


.multisource-box {{ border:1px solid #2563eb!important;border-left:4px solid #3b82f6!important;background:#0d1b2d!important }}
.multisource-box>summary {{ color:#bfdbfe!important }}
.source-grid {{ display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:8px 0 14px }}
.source-card {{ background:#091625;border:1px solid #2a405e;border-radius:8px;padding:12px 14px;min-height:110px }}
.source-card h5 {{ margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.06em }}
.source-card ul {{ margin:0;padding-left:18px }}
.source-card li {{ margin:4px 0;line-height:1.35 }}
.source-card.endpoint h5 {{ color:#60a5fa }}
.source-card.addc h5 {{ color:#c084fc }}
.source-card.network h5 {{ color:#2dd4bf }}
.source-card.application h5 {{ color:#f59e0b }}
.correlation-card {{ margin-top:10px;padding:12px 14px;background:#101f33;border:1px solid #2f4868;border-radius:8px }}
.correlation-card .label {{ display:block;color:#7f9abc;font-size:10px;letter-spacing:.08em;margin-bottom:6px }}


.cookbook-box {{ border:1px solid #16a34a!important;border-left:4px solid #22c55e!important;background:#0b1b19!important }}
.cookbook-box>summary {{ color:#86efac!important;font-size:14px }}
.cookbook-top {{ display:grid;grid-template-columns:2fr 1fr;gap:12px;margin-bottom:12px }}
.protocol-card,.window-card,.recipe-card,.cookbook-grid>div {{ background:#091625;border:1px solid #2c4963;border-radius:8px;padding:13px 15px }}
.protocol-card ul,.cookbook-grid ul {{ margin:7px 0 0;padding-left:20px }}
.protocol-card li,.cookbook-grid li {{ margin:5px 0;line-height:1.4 }}
.window-card strong {{ display:block;color:#f8fafc;font-size:20px;margin:7px 0 }}
.window-card .hint {{ display:block;color:#8095ad;line-height:1.35 }}
.recipe-card {{ margin-bottom:12px }}
.recipe-steps {{ margin:8px 0 0;padding-left:24px }}
.recipe-steps li {{ padding:5px 0 7px 4px;line-height:1.45;border-bottom:1px solid #162d43 }}
.recipe-steps li:last-child {{ border-bottom:0 }}
.cookbook-grid {{ display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px }}
.recipe-fields {{ margin-top:8px;line-height:1.55;color:#cbd5e1 }}

.footer {{ color:#71839b;text-align:right;padding:14px 3px }} @media(max-width:950px) {{ .dash,.meta {{ grid-template-columns:1fr }} .tactic-kpis {{ display:none }} .shell {{ padding:15px }} }}

/* v2.1 analyst readability */
.main-row td {{ border-top: 2px solid #334155 !important; border-bottom: 1px solid #26364a !important; padding-top: 16px !important; padding-bottom: 16px !important; }}
.main-row:nth-of-type(4n+1) td {{ background: rgba(30, 48, 70, .42); }}
.detail-row > td {{ padding: 0 16px 18px 16px !important; border-bottom: 3px solid #3b4d66 !important; background: #0d1a2b !important; }}
.test-details {{ margin: 0; padding: 10px 14px 16px; border-left: 3px solid #475569; border-radius: 0 0 8px 8px; }}
.test-details > summary {{ padding: 8px 0; font-weight: 700; color: #c4b5fd; }}
.analyst-box, .siem-box {{ margin-top: 14px; padding: 14px 16px; border: 1px solid #315071; border-radius: 8px; background: #101f33; }}
.analyst-box {{ border-left: 4px solid #38bdf8; }}
.siem-box {{ border-left: 4px solid #22c55e; }}
.analyst-box h4, .siem-box h4 {{ margin: 0 0 9px 0; }}
.siem-events, .siem-logic {{ display: grid; grid-template-columns: 220px 1fr; gap: 12px; padding: 7px 0; }}
.tactic-section, .group-card {{ margin-bottom: 18px !important; }}


.execution-box {{ margin-top: 14px; padding: 14px 16px; border: 1px solid #315071; border-left: 4px solid #a855f7; border-radius: 8px; background: #101f33; }}
.execution-box h4 {{ margin: 0 0 12px 0; }}
.exec-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 10px 14px; }}
.exec-grid > div {{ display: grid; grid-template-columns: 170px 1fr; gap: 10px; padding: 9px 10px; background: #0b1728; border: 1px solid #263b56; border-radius: 6px; }}
.command-details {{ margin-top: 12px; }}
.command-details summary {{ cursor: pointer; color: #c4b5fd; font-weight: 700; }}
.command-details pre {{ white-space: pre-wrap; overflow-wrap: anywhere; margin-top: 9px; padding: 12px; background: #07111f; border: 1px solid #263b56; border-radius: 6px; }}
.telemetry-note {{ margin-top: 12px; padding: 10px 12px; border-left: 3px solid #f59e0b; background: #172033; color: #cbd5e1; }}

</style>
</head>
<body><div class="shell">
<div class="hero"><div class="brand"><div class="shield">P</div><div><h1>PurplePOC Detection Validation Report</h1><div class="subtitle">{html.escape(str(run['scenario']))} <span style="opacity:.72;margin-left:10px;">| by Jan Fischbach</span></div></div></div><div class="rate"><span class="badge">MISSED {summary['MISSED']} / {scored}</span><span class="muted">Detection Rate</span><b>{detection_rate if detection_rate is not None else 0}%</b></div></div>
<div class="card meta">
<div class="item"><span class="label">Run ID</span><span class="mono">{html.escape(str(run['id']))}</span></div><div class="item"><span class="label">Host</span>{html.escape(str(run['host']))}</div><div class="item"><span class="label">Domain</span>{html.escape(str(run['domain_name']))}</div><div class="item"><span class="label">Operator</span>{html.escape(str(run['operator']))}</div><div class="item"><span class="label">Scenario</span>{html.escape(str(run['scenario']))}</div>
</div>
<div class="dash">
<div class="card chart-card"><div class="chart-title">Detection Scorecard</div><div class="donut-wrap"><div class="donut"><div class="donut-center">{detection_rate if detection_rate is not None else 0}%<small>{summary['DETECTED']} / {scored}</small></div></div><div class="legend"><div class="legend-row"><span class="dot" style="background:#22c55e"></span><span>Detected</span><b>{summary['DETECTED']}</b></div><div class="legend-row"><span class="dot" style="background:#ef4444"></span><span>Missed</span><b>{summary['MISSED']}</b></div><div class="legend-row"><span class="dot" style="background:#64748b"></span><span>Not Executed</span><b>{summary['NOT_EXECUTED']}</b></div><div class="legend-row"><span class="dot" style="background:#eab308"></span><span>No Expectation</span><b>{summary['NO_EXPECTATION']}</b></div></div></div></div>
<div class="card chart-card"><div class="chart-title">Tests by MITRE Category</div><div class="segments">{tactic_segments}</div><div class="legend">{tactic_legend}</div></div>
<div class="card chart-card"><div class="chart-title">Expected Events per Test</div><div class="bars">{expected_bars}</div></div>
</div>
<div class="card note">Detection = at least one expected event observed in the step's telemetry window. MISSED can also mean the required auditing / Sysmon is not enabled on the host.</div>
<div class="card results"><div class="results-head"><div><h2>Technique Results</h2><div class="muted">Grouped by MITRE tactic. Expand a category, then a test, for backend/action metadata, Atomic GUID/test details and raw stdout/stderr.</div></div></div>{''.join(grouped_html)}</div>
<div class="card"><h2>Cleanup Summary</h2><div class="detail-grid"><div><span class="label">Total actions</span>{csum.get('total',0)}</div><div><span class="label">Clean</span>{csum.get('clean',0)}</div><div><span class="label">Pending</span>{csum.get('pending',0)}</div><div><span class="label">Failed</span>{csum.get('failed',0)}</div></div></div>
<div class="footer">PurplePOC v1.0.12 &nbsp;•&nbsp; Detection Validation Report</div>
</div></body></html>
"""

    with open(
        out / "report.html",
        "w",
        encoding="utf-8"
    ) as f:
        f.write(page)

    return out
'@

# --------------------------------------------------------------------
# rich_app.py
# --------------------------------------------------------------------

Write-File "rich_app.py" @'
import argparse
import getpass
import os
import platform
import re
import socket
import subprocess
import time
import traceback
import webbrowser
import yaml
from collections import deque
from pathlib import Path

from rich import box
from rich.console import Console, Group
from rich.layout import Layout
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text


ROOT = Path(__file__).resolve().parent
LOG_DIR = ROOT / "logs"

# Windows PowerShell / conhost flickers badly when Rich repaints at high FPS.
# Limit redraws and refresh only when output actually changes.
UI_REFRESH_HZ = 2.0
UI_REFRESH_INTERVAL = 1.0 / UI_REFRESH_HZ
LOG_DIR.mkdir(parents=True, exist_ok=True)
console = Console()


def write_rich_log(message):
    path = LOG_DIR / "rich-ui.log"
    with path.open("a", encoding="utf-8") as handle:
        handle.write(
            f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n"
        )
    return path
VERSION = (
    (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if (ROOT / "VERSION").exists()
    else "1.0.12"
)
AUTHOR = "Jan Fischbach"
DATE = "August 2026"


def _domain():
    return os.environ.get("USERDNSDOMAIN") or "(not domain joined)"


def _operator():
    return getpass.getuser()


def _host():
    return socket.gethostname()


def logo_panel():
    title = Text()
    title.append("PURPLE", style="bold bright_magenta")
    title.append("POC", style="bold white")

    subtitle = Text(
        "Purple Team Detection Validation",
        style="bright_magenta"
    )

    meta = Text()
    meta.append(f"by {AUTHOR}", style="grey70")
    meta.append("  |  ", style="grey42")
    meta.append(f"v{VERSION}", style="bright_magenta")
    meta.append("  |  ", style="grey42")
    meta.append(DATE, style="grey70")

    return Panel(
        Group(title, subtitle, meta),
        border_style="magenta",
        box=box.ROUNDED,
        padding=(0, 2),
    )


def metadata_panel(scenario, run_id="-"):
    grid = Table.grid(expand=True)
    for ratio in (1, 1, 1, 1, 2):
        grid.add_column(ratio=ratio)

    grid.add_row(
        f"[cyan]SCENARIO[/cyan]\n{scenario}",
        f"[cyan]HOST[/cyan]\n{_host()}",
        f"[cyan]DOMAIN[/cyan]\n{_domain()}",
        f"[cyan]OPERATOR[/cyan]\n{_operator()}",
        f"[bright_magenta]RUN ID[/bright_magenta]\n{run_id}",
    )

    return Panel(
        grid,
        border_style="magenta",
        box=box.ROUNDED,
        padding=(0, 1),
    )


def system_panel():
    table = Table.grid(padding=(0, 1))
    table.add_column(style="cyan", width=14)
    table.add_column(style="white")

    atomic_setup = ROOT / "Setup-AtomicRedTeam.ps1"
    guided_setup = ROOT / "Setup-GuidedTools.ps1"

    values = [
        ("User", f"{os.environ.get('USERDOMAIN','')}\\{_operator()}"),
        ("Host", _host()),
        ("Domain", _domain()),
        ("OS", platform.system() + " " + platform.release()),
        ("Architecture", platform.machine()),
        ("Session", "Elevated / High Integrity"),
        ("Python", platform.python_version()),
        ("Atomic Setup", "READY" if atomic_setup.exists() else "MISSING"),
        ("GUIDED Setup", "READY" if guided_setup.exists() else "MISSING"),
        ("Time", time.strftime("%Y-%m-%d %H:%M:%S")),
    ]

    for key, value in values:
        table.add_row(key, str(value))

    return Panel(
        table,
        title="[cyan]SYSTEM INFO[/cyan]",
        border_style="cyan",
        box=box.ROUNDED,
    )


def next_steps_panel():
    return Panel(
        "[white]1.[/white] Review execution output\n"
        "[white]2.[/white] Open generated HTML report\n"
        "[white]3.[/white] Review Evidence + Cleanup",
        title="[bright_magenta]NEXT STEPS[/bright_magenta]",
        border_style="magenta",
        box=box.ROUNDED,
    )


def pipeline_panel(stages, active):
    table = Table.grid(padding=(0, 1))
    table.add_column(width=3)
    table.add_column()

    for index, stage in enumerate(stages):
        if index < active:
            marker, style = "●", "green"
        elif index == active:
            marker, style = "◉", "cyan"
        else:
            marker, style = "○", "grey50"

        table.add_row(
            f"[{style}]{marker}[/{style}]",
            f"[{style}]{stage}[/{style}]",
        )

    return Panel(
        table,
        title="[bright_magenta]EXECUTION PIPELINE[/bright_magenta]",
        border_style="magenta",
        box=box.ROUNDED,
    )


def load_scenario_model(scenario_name, techniques=None, tactics=None, tests=None):
    path = ROOT / "scenarios" / f"{scenario_name}.yaml"
    if not path.exists():
        return {"by_test_id": {}, "tactic_order": [], "tactic_totals": {}}

    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    steps = data.get("steps", [])

    techniques = {str(x).upper() for x in (techniques or []) if str(x).strip()}
    tactics = {str(x).lower().replace(" ", "_") for x in (tactics or []) if str(x).strip()}
    tests = {str(x).upper() for x in (tests or []) if str(x).strip()}

    by_test_id = {}
    tactic_order = []
    tactic_totals = {}

    for index, step in enumerate(steps, start=1):
        test_id = f"T-{index:03d}"
        tactic = step.get("tactic", "uncategorized")

        if techniques and str(step.get("technique", "")).upper() not in techniques:
            continue
        if tactics and str(tactic).lower() not in tactics:
            continue
        if tests and test_id.upper() not in tests:
            continue

        if tactic not in tactic_order:
            tactic_order.append(tactic)

        tactic_totals[tactic] = tactic_totals.get(tactic, 0) + 1
        by_test_id[test_id] = {
            "technique": step.get("technique", "-"),
            "name": step.get("name", step.get("id", test_id)),
            "tactic": tactic,
            "mode": step.get("mode", "auto").upper(),
        }

    return {
        "by_test_id": by_test_id,
        "tactic_order": tactic_order,
        "tactic_totals": tactic_totals,
    }


def empty_progress_state(model):
    return {
        "model": model,
        "current_test_id": None,
        "current_technique": "-",
        "current_name": "Waiting for scenario execution",
        "current_tactic": None,
        "current_mode": "-",
        "status_by_test": {},
        "recent_failures": [],
    }


def update_progress_state(state, line):
    stripped = (line or "").strip()

    match = re.match(
        r"^(T-\d{3})\s+(T\d+(?:\.\d+)*)\s+(.+)$",
        stripped,
    )

    if match:
        test_id = match.group(1)
        meta = state["model"]["by_test_id"].get(test_id, {})

        state["current_test_id"] = test_id
        state["current_technique"] = match.group(2)
        state["current_name"] = meta.get("name", match.group(3).strip())
        state["current_tactic"] = meta.get("tactic")
        state["current_mode"] = meta.get("mode", "-")
        return

    status_match = re.match(r"^STATUS\s+([A-Z_]+)", stripped)

    if status_match and state.get("current_test_id"):
        status = status_match.group(1)
        test_id = state["current_test_id"]
        state["status_by_test"][test_id] = status

        if status == "FAILED":
            meta = state["model"]["by_test_id"].get(test_id, {})
            label = (
                f"{test_id}  "
                f"{meta.get('technique', state['current_technique'])}  "
                f"{meta.get('name', state['current_name'])}"
            )
            if label not in state["recent_failures"]:
                state["recent_failures"].append(label)
                state["recent_failures"] = state["recent_failures"][-4:]


def tactic_stats(state, tactic):
    total = state["model"]["tactic_totals"].get(tactic, 0)
    done = failed = skipped = 0

    for test_id, meta in state["model"]["by_test_id"].items():
        if meta.get("tactic") != tactic:
            continue

        status = state["status_by_test"].get(test_id)

        if status in {"COMPLETED", "FAILED", "SKIPPED", "PREVENTED", "ABORTED", "POLICY_BLOCKED"}:
            done += 1
        if status == "FAILED":
            failed += 1
        if status == "SKIPPED":
            skipped += 1

    return total, done, failed, skipped


def progress_bar(done, total, width=30):
    ratio = 0 if total <= 0 else min(1.0, max(0.0, done / total))
    filled = int(round(width * ratio))
    return (
        "[bright_cyan]" + ("█" * filled) + "[/bright_cyan]"
        + "[grey23]" + ("░" * (width - filled)) + "[/grey23]"
    )


def mitre_progress_panel(state):
    model = state["model"]
    table = Table(expand=True, box=None, padding=(0, 1))
    table.add_column("MITRE TACTIC", style="white", min_width=22)
    table.add_column("PROGRESS", ratio=2)
    table.add_column("DONE", justify="right", width=9)
    table.add_column("STATE", min_width=19)

    labels = {
        "discovery": "Discovery",
        "execution": "Execution",
        "persistence": "Persistence",
        "privilege_escalation": "Privilege Escalation",
        "defense_evasion": "Defense Evasion",
        "credential_access": "Credential Access",
        "lateral_movement": "Lateral Movement",
        "exfiltration": "Exfiltration",
        "collection": "Collection",
        "command_and_control": "Command & Control",
        "uncategorized": "Uncategorized",
    }

    for tactic in model["tactic_order"]:
        total, done, failed, skipped = tactic_stats(state, tactic)

        if tactic == state.get("current_tactic"):
            style = "bold bright_magenta"
            status_text = "[bright_magenta]RUNNING[/bright_magenta]"
        elif done >= total and total:
            style = "green"
            status_text = "[green]COMPLETE[/green]"
        elif done:
            style = "cyan"
            status_text = "[cyan]IN PROGRESS[/cyan]"
        else:
            style = "grey70"
            status_text = "[grey50]PENDING[/grey50]"

        if failed:
            status_text += f"  [red]{failed} fail[/red]"
        if skipped:
            status_text += f"  [yellow]{skipped} skip[/yellow]"

        table.add_row(
            f"[{style}]{labels.get(tactic, tactic.replace('_', ' ').title())}[/{style}]",
            progress_bar(done, total),
            f"{done}/{total}",
            status_text,
        )

    total_tests = len(model["by_test_id"])
    completed = sum(
        1 for status in state["status_by_test"].values()
        if status in {"COMPLETED", "FAILED", "SKIPPED", "PREVENTED", "ABORTED", "POLICY_BLOCKED"}
    )

    current = Table.grid(expand=True, padding=(0, 1))
    current.add_column(style="cyan", width=16)
    current.add_column(style="white")
    current.add_row(
        "Current",
        f"[bright_magenta]{state.get('current_test_id') or '-'}[/bright_magenta]  "
        f"{state.get('current_technique') or '-'}  "
        f"{state.get('current_name') or '-'}",
    )
    current.add_row("Mode", str(state.get("current_mode") or "-"))
    current.add_row(
        "Overall",
        f"{progress_bar(completed, total_tests, 38)}  {completed}/{total_tests}",
    )

    blocks = [
        Panel(
            current,
            title="[bright_magenta]CURRENT TECHNIQUE[/bright_magenta]",
            border_style="magenta",
            box=box.ROUNDED,
        ),
        table,
    ]

    if state["recent_failures"]:
        blocks.append(
            Panel(
                "\n".join(f"[red]●[/red] {item}" for item in state["recent_failures"]),
                title="[red]RECENT FAILURES[/red]",
                border_style="red",
                box=box.ROUNDED,
            )
        )

    return Panel(
        Group(*blocks),
        title="[cyan]MITRE ATT&CK EXECUTION COVERAGE[/cyan]",
        border_style="cyan",
        box=box.ROUNDED,
        padding=(0, 1),
    )


def build_layout(scenario, run_id, stages, active, state):
    layout = Layout()
    layout.split_column(
        Layout(name="header", size=6),
        Layout(name="meta", size=5),
        Layout(name="body"),
    )

    layout["header"].update(logo_panel())
    layout["meta"].update(metadata_panel(scenario, run_id))

    layout["body"].split_row(
        Layout(name="left", ratio=2),
        Layout(name="right", ratio=1),
    )

    layout["left"].split_column(
        Layout(name="pipeline", size=10),
        Layout(name="mitre"),
    )

    layout["right"].split_column(
        Layout(name="system", ratio=2),
        Layout(name="next", ratio=1),
    )

    layout["pipeline"].update(pipeline_panel(stages, active))
    layout["mitre"].update(mitre_progress_panel(state))
    layout["system"].update(system_panel())
    layout["next"].update(next_steps_panel())

    return layout


def python_exe():
    configured = os.environ.get("PURPLEPOC_PYTHON")
    if configured and Path(configured).exists():
        return configured

    runtime_file = ROOT / "data" / "python-runtime.txt"
    if runtime_file.exists():
        candidate = runtime_file.read_text(encoding="utf-8").strip()
        if candidate and Path(candidate).exists():
            return candidate

    return str(ROOT / ".venv" / "Scripts" / "python.exe")


def last_run_id():
    p = ROOT / "data" / "last_run.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else "-"


def stream_command(cmd, scenario, stages, active, run_id="-", techniques=None, tactics=None, tests=None):
    model = load_scenario_model(scenario, techniques, tactics, tests)
    state = empty_progress_state(model)

    child_env = os.environ.copy()
    child_env["PYTHONUNBUFFERED"] = "1"
    child_env["PYTHONIOENCODING"] = "utf-8"

    proc = subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=None,
        text=True,
        bufsize=1,
        env=child_env,
    )

    last_refresh = 0.0
    last_activity = time.monotonic()

    with Live(
        build_layout(scenario, run_id, stages, active, state),
        console=console,
        auto_refresh=False,
        screen=False,
        transient=False,
        vertical_overflow="crop",
    ) as live:
        live.refresh()
        last_refresh = time.monotonic()

        while True:
            line = proc.stdout.readline()
            changed = False

            if line:
                clean_line = line.rstrip()
                update_progress_state(state, clean_line)
                changed = True
                last_activity = time.monotonic()

            now = time.monotonic()

            # Quiet commands still cause a slow dashboard heartbeat so the
            # operator can see the process is alive without console spam.
            if (
                not changed
                and proc.poll() is None
                and (now - last_activity) >= 2.0
            ):
                changed = True
                last_activity = now

            if changed and (now - last_refresh) >= UI_REFRESH_INTERVAL:
                current_run_id = (
                    last_run_id()
                    if run_id in ("-", "", None)
                    else run_id
                )

                live.update(
                    build_layout(
                        scenario,
                        current_run_id,
                        stages,
                        active,
                        state,
                    ),
                    refresh=True,
                )
                last_refresh = now

            if proc.poll() is not None:
                rest = proc.stdout.read()

                if rest:
                    for extra in rest.splitlines():
                        update_progress_state(state, extra)

                current_run_id = (
                    last_run_id()
                    if run_id in ("-", "", None)
                    else run_id
                )

                live.update(
                    build_layout(
                        scenario,
                        current_run_id,
                        stages,
                        active,
                        state,
                    ),
                    refresh=True,
                )
                break

    return proc.returncode


def selector_args(techniques=None, tactics=None, tests=None):
    args = []
    for value in techniques or []:
        args.extend(["--technique", value])
    for value in tactics or []:
        args.extend(["--tactic", value])
    for value in tests or []:
        args.extend(["--test", value])
    return args


def list_tests(scenario, techniques=None, tactics=None, tests=None):
    model = load_scenario_model(scenario, techniques, tactics, tests)

    if not model["by_test_id"]:
        console.print("[red]No tests match the supplied selectors.[/red]")
        return 2

    table = Table(
        title=f"PurplePOC test catalog - {scenario}",
        show_lines=True,
        header_style="bold cyan",
    )
    table.add_column("Test ID", style="bright_magenta", width=8)
    table.add_column("MITRE", style="cyan", width=12)
    table.add_column("Tactic", width=22)
    table.add_column("Mode", width=8)
    table.add_column("Name")

    for test_id, item in model["by_test_id"].items():
        table.add_row(
            test_id,
            str(item.get("technique") or "-"),
            str(item.get("tactic") or "-").replace("_", " ").title(),
            str(item.get("mode") or "-"),
            str(item.get("name") or "-"),
        )

    console.print(table)
    console.print(
        f"[green]{len(model['by_test_id'])} matching test(s)[/green]"
    )
    return 0


def run(scenario, skip_guided=False, phase="all", techniques=None, tactics=None, tests=None):
    py = python_exe()
    selected_args = selector_args(techniques, tactics, tests)

    stages = [
        "Administrator privileges confirmed",
        "Environment validation",
        "Self-tests",
        "Preflight",
        "Scenario execution",
        "Report generation",
    ]

    test_dir = ROOT / "tests"

    if not test_dir.exists() or not any(test_dir.glob("test_*.py")):
        log = write_rich_log(
            "Self-test stage failed: no generated tests found."
        )
        console.clear()
        console.print(logo_panel())
        console.print(
            Panel(
                "[bold red]SELF-TEST SUITE MISSING[/bold red]\n\n"
                f"Expected: {test_dir}\n"
                f"Diagnostic log: {log}",
                border_style="red",
                box=box.DOUBLE,
            )
        )
        return 5

    rc = stream_command(
        [py, "-u", "-m", "pytest", str(test_dir), "-q", "-s"],
        scenario,
        stages,
        2,
        techniques=techniques,
        tactics=tactics,
        tests=tests,
    )
    if rc:
        meaning = "pytest found no tests" if rc == 5 else "self-tests failed"
        write_rich_log(
            f"Self-test stage returned code {rc}: {meaning}"
        )
        return rc

    rc = stream_command(
        [py, "-u", str(ROOT / "controller.py"), "preflight"],
        scenario,
        stages,
        3,
        techniques=techniques,
        tactics=tactics,
        tests=tests,
    )
    if rc:
        return rc

    if phase == "guided":
        scenario_cmd = [
            py,
            "-u",
            str(ROOT / "controller.py"),
            "run",
            "--scenario",
            scenario,
            "--phase",
            "guided",
        ] + selected_args

        rc = subprocess.call(
            scenario_cmd,
            cwd=str(ROOT)
        )
        if rc:
            return rc
        run_id = last_run_id()

    elif skip_guided or phase == "auto":
        scenario_cmd = [
            py,
            "-u",
            str(ROOT / "controller.py"),
            "run",
            "--scenario",
            scenario,
        ]

        if phase == "auto":
            scenario_cmd += ["--phase", "auto"]
        else:
            scenario_cmd += ["--skip-guided"]

        scenario_cmd += selected_args

        rc = stream_command(
            scenario_cmd,
            scenario,
            stages,
            4,
            last_run_id(),
            techniques,
            tactics,
            tests,
        )

        if rc:
            return rc

        run_id = last_run_id()

    else:
        # Phase 1 stays inside the Rich Live dashboard.
        auto_cmd = [
            py,
            "-u",
            str(ROOT / "controller.py"),
            "run",
            "--scenario",
            scenario,
            "--phase",
            "auto",
        ] + selected_args

        rc = stream_command(
            auto_cmd,
            scenario,
            stages,
            4,
            last_run_id(),
            techniques,
            tactics,
            tests,
        )

        if rc:
            return rc

        run_id = last_run_id()

        # Only the GUIDED phase needs direct keyboard access.
        console.clear()
        console.print(logo_panel())
        console.print(metadata_panel(scenario, run_id))
        console.print(
            Panel(
                "[green]AUTO / ATOMIC PHASE COMPLETE[/green]\n"
                "[cyan]Switching to interactive GUIDED phase[/cyan]\n\n"
                "The Rich dashboard will return automatically for report generation.",
                title="[bright_magenta]GUIDED TESTS[/bright_magenta]",
                border_style="magenta",
                box=box.ROUNDED,
            )
        )

        guided_cmd = [
            py,
            "-u",
            str(ROOT / "controller.py"),
            "run",
            "--scenario",
            scenario,
            "--phase",
            "guided",
            "--resume-run-id",
            run_id,
        ] + selected_args

        rc = subprocess.call(
            guided_cmd,
            cwd=str(ROOT)
        )

        if rc:
            return rc

    rc = stream_command(
        [py, "-u", str(ROOT / "controller.py"), "report"],
        scenario,
        stages,
        5,
        run_id,
        techniques,
        tactics,
        tests,
    )
    if rc:
        return rc

    report = ROOT / "reports" / run_id / "report.html"

    console.clear()
    console.print(logo_panel())
    console.print(metadata_panel(scenario, run_id))
    console.print(
        Panel(
            f"[bold green]RUN COMPLETE[/bold green]\n\n"
            f"[cyan]Run ID[/cyan]  {run_id}\n"
            f"[cyan]Report[/cyan]  {report}",
            title="[green]SUCCESS[/green]",
            border_style="green",
            box=box.DOUBLE,
        )
    )

    if report.exists():
        webbrowser.open(report.as_uri())

    return 0


def main():
    # GUIDED tests are disabled by default.
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", default="full")
    parser.add_argument(
        "--technique",
        action="append",
        default=[],
        help="Run/list all tests for this MITRE technique. Repeatable.",
    )
    parser.add_argument(
        "--tactic",
        action="append",
        default=[],
        help="Run/list all tests for this MITRE tactic. Repeatable.",
    )
    parser.add_argument(
        "--test",
        action="append",
        default=[],
        help="Run/list an exact PurplePOC test ID such as T-052. Repeatable.",
    )
    parser.add_argument(
        "--phase",
        choices=["all", "auto", "guided"],
        default="all",
        help="Execution phase. GUIDED remains opt-in.",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List matching tests and exit without execution.",
    )

    guided_group = parser.add_mutually_exclusive_group()
    guided_group.add_argument(
        "--guided",
        action="store_true",
        help="Enable interactive GUIDED tests. Disabled by default.",
    )
    guided_group.add_argument(
        "--skip-guided",
        action="store_true",
        help="Skip GUIDED tests explicitly (default behavior).",
    )

    args = parser.parse_args()

    if args.list:
        raise SystemExit(
            list_tests(
                args.scenario,
                args.technique,
                args.tactic,
                args.test,
            )
        )

    use_guided = bool(getattr(args, "guided", False)) or args.phase == "guided"

    raise SystemExit(
        run(
            args.scenario,
            skip_guided=(not use_guided),
            phase=args.phase,
            techniques=args.technique,
            tactics=args.tactic,
            tests=args.test,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        detail = traceback.format_exc()
        path = write_rich_log(detail)
        console.clear()
        console.print(logo_panel())
        console.print(
            Panel(
                "[bold red]PURPLEPOC UI CRASH[/bold red]\n\n"
                + detail
                + f"\nDiagnostic log: {path}",
                border_style="red",
                box=box.DOUBLE,
            )
        )
        raise
'@

# --------------------------------------------------------------------
# tests/test_smoke.py
# --------------------------------------------------------------------

Write-File "tests\test_smoke.py" @'
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]


def test_required_runtime_files_exist():
    required = [
        "VERSION",
        "UI.ps1",
        "Bootstrap.ps1",
        "Start-PurplePOC.ps1",
        "Setup-AtomicRedTeam.ps1",
        "Setup-GuidedTools.ps1",
        "controller.py",
        "rich_app.py",
        "config.yaml",
        "requirements.txt",
    ]

    for relative in required:
        assert (ROOT / relative).is_file(), relative


def test_version_is_consistent():
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")
    ui = (ROOT / "UI.ps1").read_text(encoding="utf-8")

    assert version == "1.0.12"
    assert 'else "1.0.12"' in rich
    assert "v1.0.12" in ui


def test_rich_ui_assets_exist():
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    assert "from rich.layout import Layout" in rich
    assert "from rich.live import Live" in rich
    assert "EXECUTION PIPELINE" in rich
    assert "SYSTEM INFO" in rich
    assert "NEXT STEPS" in rich


def test_full_scenario_is_mitre_categorized():
    data = yaml.safe_load(
        (ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8")
    )

    assert data["steps"]

    for step in data["steps"]:
        assert step.get("technique")
        assert step.get("tactic")
        assert step.get("mode") in {"auto", "guided"}


def test_auto_atomic_precedes_guided():
    data = yaml.safe_load(
        (ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8")
    )

    steps = data["steps"]
    guided = [
        i for i, step in enumerate(steps)
        if step.get("mode") == "guided"
    ]

    assert guided
    first_guided = min(guided)

    assert all(
        step.get("mode") == "auto"
        for step in steps[:first_guided]
    )


def test_atomic_tests_use_exact_guids():
    data = yaml.safe_load(
        (ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8")
    )

    atomic = [
        step
        for step in data["steps"]
        if step.get("backend") == "atomic"
    ]

    assert atomic

    for step in atomic:
        assert step.get("atomic_technique")
        assert step.get("atomic_guid")


def test_skip_guided_support_exists():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    start = (ROOT / "Start-PurplePOC.ps1").read_text(encoding="utf-8")
    guided = (ROOT / "core" / "guided.py").read_text(encoding="utf-8")

    assert "--skip-guided" in controller
    assert "[switch]$SkipGuided" in start
    assert "skip-all" in guided


def test_report_is_expandable_and_categorized():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")

    assert "View execution details" in reporting
    assert "Atomic Red Team details" in reporting
    assert "Raw stdout" in reporting
    assert "Raw stderr" in reporting
    assert "tactic-row" in reporting


def test_setup_scripts_are_nonempty():
    for relative in (
        "Setup-AtomicRedTeam.ps1",
        "Setup-GuidedTools.ps1",
    ):
        path = ROOT / relative
        assert path.exists()
        assert path.stat().st_size > 200

def test_rich_ui_keeps_auto_phase_in_dashboard():
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")

    assert '"--phase",' in rich
    assert '"auto",' in rich
    assert '"guided",' in rich
    assert '"--resume-run-id",' in rich
    assert 'choices=["all", "auto", "guided"]' in controller
    assert 'if phase == "auto" and mode != "auto"' in controller
    assert 'if phase == "guided" and mode != "guided"' in controller


def test_rich_ui_uses_low_flicker_refresh_mode():
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    assert "UI_REFRESH_HZ = 2.0" in rich
    assert "auto_refresh=False" in rich
    assert "screen=False" in rich
    assert "transient=False" in rich
    assert "time.monotonic()" in rich


def test_rich_ui_uses_mitre_progress_dashboard():
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    assert "MITRE ATT&CK EXECUTION COVERAGE" in rich
    assert "def mitre_progress_panel(" in rich
    assert "def progress_bar(" in rich
    assert "CURRENT TECHNIQUE" in rich
    assert "RECENT FAILURES" in rich
    assert "def output_panel(" not in rich


def test_rich_app_python_syntax_compiles():
    rich_path = ROOT / "rich_app.py"
    source = rich_path.read_text(encoding="utf-8")
    compile(source, str(rich_path), "exec")


def test_guided_parser_is_mutually_exclusive_and_default_off():
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")
    assert "add_mutually_exclusive_group" in rich
    assert '"--guided"' in rich
    assert '"--skip-guided"' in rich
    assert 'getattr(args, "guided", False)' in rich
    assert "skip_guided=(not use_guided)" in rich



def test_controller_guided_flags_belong_to_run_subparser():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")

    assert "guided_group = run_parser.add_mutually_exclusive_group()" in controller
    assert '"--guided"' in controller
    assert '"--skip-guided"' in controller

    # Regression guard for the old argparse bug:
    # --skip-guided must not be registered on the root parser.
    assert 'parser.add_argument(\n        "--skip-guided"' not in controller

def test_controller_guided_default_policy():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")

    assert "effective_skip_guided = bool(" in controller
    assert "not args.guided" in controller
    assert 'args.phase != "guided"' in controller


def test_controller_python_syntax_compiles():
    controller_path = ROOT / "controller.py"
    source = controller_path.read_text(encoding="utf-8")
    compile(source, str(controller_path), "exec")


def test_expanded_execution_priv_esc_and_lateral_coverage():
    scenario = yaml.safe_load(
        (ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8")
    )
    steps = scenario["steps"]

    by_tactic = {}
    for step in steps:
        by_tactic.setdefault(step["tactic"], []).append(step)

    assert len(by_tactic["execution"]) >= 11
    assert len(by_tactic["privilege_escalation"]) >= 3
    assert len(by_tactic["lateral_movement"]) >= 5

    execution_ids = {x["id"] for x in by_tactic["execution"]}
    assert "atomic_mshta_remote_hta" in execution_ids
    assert "atomic_regsvr32_remote" in execution_ids
    assert "atomic_rundll32_remote" in execution_ids
    assert "atomic_cmstp_remote" in execution_ids
    assert "atomic_hh_remote" in execution_ids

    lateral_ids = {x["id"] for x in by_tactic["lateral_movement"]}
    assert "atomic_admin_share_local" in lateral_ids
    assert "atomic_psexec_localhost" in lateral_ids
    assert "atomic_wmi_remote_loopback" in lateral_ids


def test_defense_evasion_audit_and_security_process_coverage():
    scenario = yaml.safe_load(
        (ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8")
    )
    defense = [x for x in scenario["steps"] if x["tactic"] == "defense_evasion"]
    ids = {x["id"] for x in defense}
    assert "atomic_disable_event_channel" in ids
    assert "atomic_eventlog_acl_modify" in ids
    assert "atomic_clear_eventlog" in ids
    assert "simulate_av_process_kill" in ids

    sim = next(x for x in defense if x["id"] == "simulate_av_process_kill")
    cmd = sim["command"].lower()
    for real_process in ["msmpeng", "sense", "csfalcon", "crowdstrike", "sentinelone"]:
        assert real_process not in cmd


def test_exfiltration_coverage():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    exfil = [x for x in scenario["steps"] if x["tactic"] == "exfiltration"]
    techniques = {x["technique"] for x in exfil}
    assert len(exfil) >= 7
    assert {"T1041","T1048","T1048.003","T1567","T1020"} <= techniques
    combined = "\n".join(x.get("command","") for x in exfil).lower()
    assert "purplepoc-exfil" in combined
    assert "documents" not in combined and "desktop" not in combined


def test_controller_isolates_test_and_telemetry_exceptions():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    assert "def _write_crash_log(" in controller
    assert "traceback.format_exc()" in controller
    assert "UNEXPECTED TEST EXCEPTION" in controller
    assert "TELEMETRY COLLECTION ERROR" in controller
    assert "Scenario execution continues with next test" in controller
    assert 'logs_dir / f"crash-{run_id}.log"' in controller


def test_exfiltration_is_visible_in_report_and_live_dashboard():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    rich_app = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    assert '"exfiltration": "Exfiltration"' in reporting
    assert '"exfiltration": "#06b6d4"' in reporting
    assert '"exfiltration": "Exfiltration"' in rich_app

    # Regression guard: report must append unexpected/new tactics rather than
    # silently discarding them because of a hard-coded list.
    assert "observed_tactics" in reporting
    assert "if key not in tactic_order" in reporting


def test_every_scenario_step_has_description_and_siem_rule():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    for step in scenario["steps"]:
        assert step.get("description")
        assert step.get("siem_rule", {}).get("event_ids")
        assert step.get("siem_rule", {}).get("logic")

def test_report_contains_analyst_and_siem_sections():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    assert "What this test does" in reporting
    assert "Suggested SIEM detection" in reporting
    assert "Relevant Event IDs / telemetry" in reporting
    assert "Correlation logic" in reporting
    assert "analyst-box" in reporting
    assert "siem-box" in reporting


def test_all_atomic_scenario_tests_are_allowlisted():
    config = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))

    allowed = {
        (x.get("technique"), str(x.get("guid", "")).lower())
        for x in config.get("atomic", {}).get("tests", [])
    }

    missing = []
    for step in scenario["steps"]:
        if step.get("backend") != "atomic":
            continue
        key = (
            step.get("atomic_technique"),
            str(step.get("atomic_guid", "")).lower()
        )
        if key not in allowed:
            missing.append((step.get("id"), key))

    assert not missing, f"Atomic scenario tests missing from allowlist: {missing}"


def test_defense_evasion_eventlog_atomics_are_allowlisted():
    config = yaml.safe_load((ROOT / "config.yaml").read_text(encoding="utf-8"))
    allowed = {
        (x.get("technique"), str(x.get("guid", "")).lower())
        for x in config.get("atomic", {}).get("tests", [])
    }

    assert ("T1685.001", "b26a3340-dad7-4360-9176-706269c74103") in allowed
    assert ("T1685.001", "8e81d090-0cd6-4d46-863c-eec11311298f") in allowed
    assert ("T1685.005", "e6abb60e-26b8-41da-8aae-0c35174b0967") in allowed


def test_controller_has_atomic_allowlist_preflight():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    assert "def validate_atomic_scenario_allowlist" in controller
    assert "Atomic allowlist consistency" in controller
    assert "POLICY_BLOCKED" in controller


def test_selective_execution_cli_is_wired_end_to_end():
    starter = (ROOT / "Start-PurplePOC.ps1").read_text(encoding="utf-8")
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    for token in ["-Technique", "-Tactic", "-Test", "-List", "-Help", "-Phase"]:
        assert token in starter

    for token in ["--technique", "--tactic", "--test"]:
        assert token in controller
        assert token in rich

    assert "selected_steps" in controller
    assert "original_index" in controller
    assert "list_tests" in rich


def test_filtered_report_design_only_inserts_selected_steps():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    assert "for original_index, step in selected_steps" in controller
    assert 'test_id = f"T-{original_index:03d}"' in controller


def test_stream_command_accepts_selector_context():
    import ast

    rich_source = (ROOT / "rich_app.py").read_text(encoding="utf-8")
    tree = ast.parse(rich_source)

    fn = next(
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "stream_command"
    )

    args = [item.arg for item in fn.args.args]
    assert "techniques" in args
    assert "tactics" in args
    assert "tests" in args


def test_phase_auto_is_forwarded_to_controller():
    rich_source = (ROOT / "rich_app.py").read_text(encoding="utf-8")
    assert 'scenario_cmd += ["--phase", "auto"]' in rich_source


def test_report_policy_blocked_css_uses_escaped_fstring_braces():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    assert ".status.policy_blocked {{ background:#5b3b8a; color:#f1e8ff; }}" in reporting
    assert ".status.policy_blocked { background:#5b3b8a; color:#f1e8ff; }" not in reporting


def test_report_crash_logging_is_present():
    controller = (ROOT / "controller.py").read_text(encoding="utf-8")
    assert 'report-crash-{run_id}.log' in controller
    assert "[FAIL] Report generation error:" in controller


def test_all_analyst_report_css_braces_are_fstring_escaped():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    start = reporting.index("/* v2.1 analyst readability */")
    end = reporting.index("</style>", start)
    block = reporting[start:end]

    # Remove valid doubled braces; no single CSS braces may remain.
    remainder = block.replace("{{", "").replace("}}", "")
    assert "{" not in remainder
    assert "}" not in remainder

    assert ".main-row td {{" in block
    assert ".detail-row > td {{" in block
    assert ".analyst-box, .siem-box {{" in block
    assert ".siem-box {{" in block


def test_every_step_has_structured_execution_details():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    required = {"process","input","operation","destination","network","artifacts","implementation","purpose","command"}
    for step in scenario["steps"]:
        details = step.get("execution_details") or {}
        assert required <= set(details), (step.get("id"), required - set(details))


def test_exfiltration_execution_details_are_truthful_about_network_activity():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    by_id = {x["id"]: x for x in scenario["steps"]}
    assert "no http request" in by_id["exfil_http_loopback"]["execution_details"]["network"].lower()
    assert "not transmitted" in by_id["exfil_c2_pattern"]["execution_details"]["network"].lower()
    assert "dns queries are attempted" in by_id["exfil_dns_pattern"]["execution_details"]["network"].lower()
    assert "no web-service upload" in by_id["exfil_web_service"]["execution_details"]["network"].lower()
    assert "not transmitted" in by_id["exfil_automated"]["execution_details"]["network"].lower()


def test_report_renders_exact_execution_plan():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    for token in [
        "Exact PurplePOC execution plan",
        "Source process",
        "Input / source",
        "Operation",
        "Destination",
        "Network action / target",
        "Artifacts created / touched",
        "Show exact command / Atomic invocation",
    ]:
        assert token in reporting


def test_bootstrap_does_not_claim_ready_after_failed_dependency_install():
    bootstrap = (ROOT / "Bootstrap.ps1").read_text(encoding="utf-8")
    assert "Test-PythonDependencies" in bootstrap
    assert "pip dependency installation failed" in bootstrap
    assert "Final Python dependency verification FAILED" in bootstrap
    assert "skipping pip/network access" in bootstrap


def test_atomic_setup_has_offline_fast_path():
    atomic = (ROOT / "Setup-AtomicRedTeam.ps1").read_text(encoding="utf-8")
    assert "Fast/offline path" in atomic
    assert "skipping PSGallery" in atomic
    assert "skipping download" in atomic
    assert "raw.githubusercontent.com cannot be resolved" in atomic
    assert 'status = "READY"' in atomic


def test_bootstrap_python_probe_uses_temp_script_on_ps51():
    bootstrap = (ROOT / "Bootstrap.ps1").read_text(encoding="utf-8")
    assert "PurplePOC-python-probe-" in bootstrap
    assert "[System.IO.File]::WriteAllText" in bootstrap
    assert "& $Python $ProbeFile 1>$OutFile 2>$ErrFile" in bootstrap
    assert '$ErrorActionPreference = "Continue"' in bootstrap
    assert "$ErrorActionPreference = $SavedErrorActionPreference" in bootstrap
    assert "-c $Probe" not in bootstrap


def test_offline_runtime_fallback_is_wired_end_to_end():
    bootstrap = (ROOT / "Bootstrap.ps1").read_text(encoding="utf-8")
    starter = (ROOT / "Start-PurplePOC.ps1").read_text(encoding="utf-8")
    rich = (ROOT / "rich_app.py").read_text(encoding="utf-8")

    assert "Select-PurplePOCPythonRuntime" in bootstrap
    assert "PurplePOC\\.venv\\Scripts\\python.exe" in bootstrap
    assert "python-runtime.txt" in bootstrap
    assert "PURPLEPOC_PYTHON" in bootstrap

    assert "python-runtime.txt" in starter
    assert "PURPLEPOC_PYTHON" in starter

    assert 'os.environ.get("PURPLEPOC_PYTHON")' in rich
    assert '"python-runtime.txt"' in rich


def test_atomic_setup_module_error_string_is_ps51_parser_safe():
    atomic = (ROOT / "Setup-AtomicRedTeam.ps1").read_text(encoding="utf-8")
    assert 'failed for ${Module}:' in atomic
    assert 'failed for $Module:' not in atomic


def test_start_has_core_readiness_gate():
    starter = (ROOT / "Start-PurplePOC.ps1").read_text(encoding="utf-8")
    assert "Core readiness gate" in starter
    assert "Atomic Red Team is not in a verified READY state." in starter
    assert '$AtomicStatus.status -ne "READY"' in starter
    assert "import yaml,rich,requests,pytest" in starter


def test_atomic_setup_removes_stale_status_before_validation():
    atomic = (ROOT / "Setup-AtomicRedTeam.ps1").read_text(encoding="utf-8")
    assert "Do not leave a stale READY status behind" in atomic
    assert "Remove-Item $AtomicStatusFile" in atomic


def test_all_steps_have_multisource_detection_guidance():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    required = {"endpoint","ad_dc","network","application","correlation","enrichment"}
    for step in scenario["steps"]:
        sources = step.get("detection_sources") or {}
        assert required <= set(sources), (step.get("id"), required - set(sources))


def test_dns_exfiltration_includes_network_dns_and_correlation_sources():
    scenario = yaml.safe_load((ROOT / "scenarios" / "full.yaml").read_text(encoding="utf-8"))
    by_id = {x["id"]: x for x in scenario["steps"]}
    dns = by_id["exfil_dns_pattern"]["detection_sources"]
    assert any("Sysmon 22" in x for x in dns["endpoint"])
    assert any("Firewall/NDR" in x for x in dns["network"])
    assert any("DNS Server" in x or "resolver" in x.lower() for x in dns["application"])
    assert "unique subdomains" in dns["correlation"]
    assert "NXDOMAIN" in dns["correlation"]


def test_report_renders_multisource_detection_section():
    reporting = (ROOT / "core" / "reporting.py").read_text(encoding="utf-8")
    for token in ["Detection sources & SIEM correlation","Endpoint / EDR","AD / Domain Controller","Network / Firewall / NDR","Application / DNS / Proxy / Cloud","SIEM CORRELATION LOGIC","KEY ENRICHMENT FIELDS","multisource-box"]:
        assert token in reporting


def test_v300_gui_files_exist():
    assert (ROOT / "gui" / "main.py").exists()
    assert (ROOT / "Start-PurplePOC-GUI.ps1").exists()

def test_v300_gui_core_wiring():
    gui=(ROOT / "gui" / "main.py").read_text(encoding="utf-8")
    for token in ["controller.py","--test","--tactic","--technique","MITRE Test Browser","Run Builder","certipy-ad","impacket","ldap3"]:
        assert token in gui

def test_v300_pyside_dependency():
    assert "PySide6==" in (ROOT / "requirements.txt").read_text(encoding="utf-8")


def test_v301_bootstrap_requires_pyside6():
    bootstrap = (ROOT / "Bootstrap.ps1").read_text(encoding="utf-8")
    assert "'PySide6': 'PySide6'" in bootstrap

def test_v301_gui_revalidates_after_bootstrap():
    starter = (ROOT / "Start-PurplePOC-GUI.ps1").read_text(encoding="utf-8")
    assert "PySide6 is still unavailable after Bootstrap." in starter
    assert starter.count("import PySide6,yaml,rich") >= 2


def test_v302_gui_launcher_keeps_console_open_and_logs_failures():
    starter=(ROOT/"Start-PurplePOC-GUI.ps1").read_text(encoding="utf-8")
    assert "-NoExit -NoProfile" in starter
    assert "gui-start-" in starter
    assert "PurplePOC GUI startup FAILED" in starter
    assert "Press ENTER to keep this console available for diagnosis." in starter

def test_v302_gui_python_crash_log():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "gui-crash-" in gui
    assert "traceback.format_exc()" in gui


def test_v303_pyside_supports_python314():
    req = (ROOT / "requirements.txt").read_text(encoding="utf-8")
    assert "PySide6>=6.10.1,<6.11" in req
    assert "PySide6==6.9.2" not in req


def test_v100_gui_branding_and_test_launch_controls():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "PurplePOC 1.0" in gui
    assert "by Jan Fischbach" in gui
    assert "Run selected" in gui
    assert "Run validation" in gui
    assert "QProcess.ProcessState.NotRunning" in gui
    assert "errorOccurred.connect" in gui
    assert "waitForStarted(5000)" in gui
    assert "--non-interactive" in gui

def test_v100_browser_can_launch_selected_tests():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "run_requested=Signal(list)" in gui
    assert "self.browser.run_requested.connect(self.start_selected)" in gui
    assert "browser.run_requested.connect(lambda _ids:self.show_page(2))" in gui


def test_v101_live_execution_dashboard():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    for token in ["class LiveStatusPanel","EXECUTION PIPELINE","CURRENT TECHNIQUE","MITRE TACTIC","RECENT FAILURES","Scenario RUNNING","Report PENDING","def feed(self,text)"]:
        assert token in gui
    assert "a=['-u',str(ROOT/'controller.py')" in gui
    assert "by Jan Fischbach" in gui


def test_v102_builder_preserves_runtime_and_state():
    builder = Path(__file__).resolve().parents[1].parent
    # Generated project cannot inspect the outer builder directly; this test
    # validates the documented upgrade contract from generated README instead.
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "upgrade-safe" in readme.lower()
    assert ".venv" in readme


def test_v102_bootstrap_searches_multiple_existing_runtimes():
    bootstrap = (ROOT / "Bootstrap.ps1").read_text(encoding="utf-8")
    assert "Checking existing runtime" in bootstrap
    assert "Programs\\Python" in bootstrap
    assert "PURPLEPOC_PYTHON" in bootstrap
    assert "python-runtime.txt" in bootstrap


def test_v103_readme_contains_execution_policy_bypass_help():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "ExecutionPolicy Bypass" in readme
    assert "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass" in readme


def test_v104_mitre_table_is_scroll_free_and_dynamic_height():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)" in gui
    assert "table_height=header_height+(row_height*len(tactics))+6" in gui
    assert "self.table.setFixedHeight(max(250,min(340,table_height)))" in gui

def test_v104_execution_pipeline_is_compacted():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "cur.setMaximumHeight(88)" in gui
    assert "self.overall.setFixedHeight(11)" in gui
    assert "self.recent.setMaximumHeight(60)" in gui


def test_v105_runbuilder_has_clean_header():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    runner=gui[gui.index("class Runner(QWidget):"):gui.index("class Reports(QWidget):")]
    assert "PurplePOC 1.0 | by Jan Fischbach" not in runner
    assert "Run Builder" in runner


def test_v106_all_steps_have_protocol_ports_and_analyst_recipe():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    for step in scenario["steps"]:
        ds=step.get("detection_sources") or {}
        assert ds.get("protocols_ports"), step["id"]
        recipe=ds.get("analyst_recipe") or {}
        assert len(recipe.get("steps") or []) >= 7, step["id"]
        assert recipe.get("minimum_fields"), step["id"]
        assert recipe.get("false_positive_checks"), step["id"]

def test_v106_ldap_smb_wmi_ports_are_explicit():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    by_id={x["id"]:x for x in scenario["steps"]}
    ldap=" ".join(by_id["ad_rootdse"]["detection_sources"]["protocols_ports"])
    smb=" ".join(by_id["share_discovery"]["detection_sources"]["protocols_ports"])
    wmi=" ".join(by_id["atomic_wmi_remote_loopback"]["detection_sources"]["protocols_ports"])
    assert "389" in ldap and "636" in ldap and "3268" in ldap and "3269" in ldap
    assert "445" in smb
    assert "135" in wmi and "49152-65535" in wmi

def test_v106_report_renders_analyst_cookbook():
    reporting=(ROOT/"core"/"reporting.py").read_text(encoding="utf-8")
    for token in [
        "Analyst cookbook - build & validate the SIEM rule",
        "PROTOCOLS / PORTS",
        "CORRELATION WINDOW",
        "STEP-BY-STEP",
        "MINIMUM FIELDS TO EXTRACT / NORMALIZE",
        "EVIDENCE TO ATTACH TO THE OFFENSE",
        "FALSE-POSITIVE CHECKS",
    ]:
        assert token in reporting


def test_v107_dashboard_has_interactive_mitre_explorer():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    for token in [
        "class TacticButton",
        "click a tactic",
        "mitreExplorer",
        "DESCRIPTION",
        "PURPOSE / WHAT IT VALIDATES",
        "PROTOCOLS / PORTS",
        "Open in MITRE Tests",
        "open_browser_requested=Signal(str)",
    ]:
        assert token in gui

def test_v107_dashboard_can_jump_to_filtered_browser():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "def set_tactic_filter(self,tactic)" in gui
    assert "dashboard.open_browser_requested.connect(self.open_tactic_browser)" in gui
    assert "self.browser.set_tactic_filter(tactic)" in gui


def test_v108_interactive_dashboard_imports_qsplitter():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    widget_import=gui.split("from PySide6.QtWidgets import",1)[1].split("\n",1)[0]
    assert "QSplitter" in widget_import
    assert "QSplitter(Qt.Horizontal)" in gui


def test_v109_execution_descriptions_are_specific():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    execution=[x for x in scenario["steps"] if x.get("tactic")=="execution"]
    assert len(execution)==11
    generic="Executes a controlled command or LOLBin behavior to validate process/script telemetry."
    for step in execution:
        assert step.get("description") and step["description"] != generic, step["id"]
        details=step.get("execution_details") or {}
        assert details.get("operation") and details.get("purpose"), step["id"]
        assert "mapped controlled ATT&CK execution behavior" not in details.get("operation",""), step["id"]

def test_v109_security_process_enumeration_is_read_only():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    by_id={x["id"]:x for x in scenario["steps"]}
    step=by_id["security_process_enumeration"]
    assert step["technique"]=="T1518.001"
    assert step["mode"]=="auto"
    cmd=step["command"].lower()
    assert "get-ciminstance" in cmd
    assert "stop-process" not in cmd and "stop-service" not in cmd

def test_v109_security_process_stop_targets_only_dummy_child():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    by_id={x["id"]:x for x in scenario["steps"]}
    step=by_id["simulate_av_process_kill"]
    cmd=step["command"].lower()
    assert "start-process powershell.exe" in cmd
    assert "stop-process -id $p.id" in cmd
    for forbidden in ["msmpeng","sense","csfalcon","crowdstrike","sentinelone"]:
        assert forbidden not in cmd

def test_v109_gui_protocol_list_uses_ascii_dash():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "join('- '+str(x) for x in ports)" in gui


def test_v1010_all_test_descriptions_are_specific():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    banned=[
        "enumerates system/domain context to create attack discovery telemetry",
        "executes a controlled command or lolbin behavior",
        "executes a controlled action",
        "exercises controlled behavior",
        "exercises the mapped controlled",
        "creates a temporary persistence mechanism",
        "simulates administrative-share, wmi, or remote-execution behavior",
        "guided credential-access validation. purplepoc does not automatically dump credentials",
    ]
    assert len(scenario["steps"])==75
    for step in scenario["steps"]:
        text=" ".join([
            str(step.get("description") or ""),
            str((step.get("execution_details") or {}).get("operation") or ""),
            str((step.get("execution_details") or {}).get("purpose") or ""),
        ]).lower()
        for phrase in banned:
            assert phrase not in text, (step["id"], phrase)
        assert len(step.get("description") or "") >= 70, step["id"]
        assert len((step.get("execution_details") or {}).get("operation") or "") >= 35, step["id"]
        assert len((step.get("execution_details") or {}).get("purpose") or "") >= 45, step["id"]

def test_v1010_wmi_description_states_exact_action():
    scenario=yaml.safe_load((ROOT/"scenarios"/"full.yaml").read_text(encoding="utf-8"))
    by_id={x["id"]:x for x in scenario["steps"]}
    wmi=by_id["wmi"]
    text=(wmi["description"]+" "+wmi["execution_details"]["operation"]).lower()
    assert "wmic.exe process call create" in text
    assert "cmd.exe /c exit 0" in text
    assert "no remote host" in wmi["execution_details"]["purpose"].lower()

def test_v1010_gui_shows_exact_action():
    gui=(ROOT/"gui"/"main.py").read_text(encoding="utf-8")
    assert "EXACT ACTION / WHAT PURPLEPOC RUNS" in gui
    assert "Operation: " in gui
    assert "Implementation: " in gui
    assert "Invocation: " in gui


def test_v1011_gui_launcher_uses_standard_black_console_banner():
    starter=(ROOT/"Start-PurplePOC-GUI.ps1").read_text(encoding="utf-8")
    assert 'Set-PurplePOCConsoleTheme "Windows PowerShell (Elevated) - PurplePOC GUI"' in starter
    assert 'Write-Banner "PurplePOC Desktop GUI"' in starter

def test_v1011_console_theme_paints_full_buffer_black():
    ui=(ROOT/"UI.ps1").read_text(encoding="utf-8")
    assert "$RawUI.BackgroundColor = [ConsoleColor]::Black" in ui
    assert "$RawUI.SetBufferContents($Rectangle, $Cell)" in ui
    assert "[ConsoleColor]::Black" in ui


def test_v1012_proxy_parameter_is_wired_end_to_end():
    bootstrap=(ROOT/"Bootstrap.ps1").read_text(encoding="utf-8")
    atomic=(ROOT/"Setup-AtomicRedTeam.ps1").read_text(encoding="utf-8")
    guided=(ROOT/"Setup-GuidedTools.ps1").read_text(encoding="utf-8")
    gui=(ROOT/"Start-PurplePOC-GUI.ps1").read_text(encoding="utf-8")
    cli=(ROOT/"Start-PurplePOC.ps1").read_text(encoding="utf-8")

    assert '[string]$Proxy' in bootstrap
    assert '"--proxy", $Proxy' in bootstrap
    assert '& $AtomicSetup -Proxy $Proxy' in bootstrap
    assert '& $GuidedSetup -Quiet -Proxy $Proxy' in bootstrap

    assert '[string]$Proxy' in atomic
    assert '$NuGetArgs["Proxy"] = $Proxy' in atomic
    assert '$ModuleArgs["Proxy"] = $Proxy' in atomic
    assert '$WebArgs["Proxy"] = $Proxy' in atomic

    assert '[string]$Proxy' in guided
    assert '"--proxy", $Proxy' in guided

    assert '[string]$Proxy' in gui
    assert 'Bootstrap.ps1" -Proxy $Proxy' in gui

    assert '[string]$Proxy' in cli
    assert '-Proxy http://proxy:8080' in cli

def test_v1012_proxy_does_not_require_local_dns_resolution():
    bootstrap=(ROOT/"Bootstrap.ps1").read_text(encoding="utf-8")
    atomic=(ROOT/"Setup-AtomicRedTeam.ps1").read_text(encoding="utf-8")
    assert '-not $PyPiDns -and [string]::IsNullOrWhiteSpace($Proxy)' in bootstrap
    assert '[string]::IsNullOrWhiteSpace($Proxy)' in atomic

'@

Confirm-GeneratedFile "tests\test_smoke.py" -Critical | Out-Null

# --------------------------------------------------------------------
# controller.py
# --------------------------------------------------------------------

Write-File "controller.py" @'
import argparse
import getpass
import os
import socket
import sys
import uuid
from datetime import datetime, timezone
import traceback
from pathlib import Path

import yaml

from core.database import (
    init_db,
    insert_run,
    insert_step,
    update_run_end,
    insert_observation
)

from core.auto import execute as auto_execute
from adapters.atomic import execute as atomic_execute, AtomicPolicyError
from core.guided import run_guided
from core.telemetry import collect_security_events
from core.reporting import generate
from core.cleanup import (
    retry_pending,
    summary as cleanup_summary,
    reset as cleanup_reset,
)


ROOT = Path(__file__).resolve().parent
RUNTIME = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "PurplePOC"
LAST_RUN_FILE = ROOT / "data" / "last_run.txt"

def _write_crash_log(run_id, test_id, step, exc):
    """Append an unexpected per-test exception to a persistent diagnostic log."""
    try:
        logs_dir = ROOT / "logs"
        logs_dir.mkdir(parents=True, exist_ok=True)
        path = logs_dir / f"crash-{run_id}.log"

        with path.open("a", encoding="utf-8", errors="replace") as fh:
            fh.write("\n" + "=" * 78 + "\n")
            fh.write(f"RUN_ID: {run_id}\n")
            fh.write(f"TEST_ID: {test_id}\n")
            fh.write(f"STEP_ID: {step.get('id', '-')}\n")
            fh.write(f"NAME: {step.get('name', '-')}\n")
            fh.write(f"TECHNIQUE: {step.get('technique', '-')}\n")
            fh.write(f"TACTIC: {step.get('tactic', '-')}\n")
            fh.write(f"MODE: {step.get('mode', '-')}\n")
            fh.write(f"ACTION: {step.get('action', '-')}\n")
            if step.get("atomic_guid"):
                fh.write(f"ATOMIC_GUID: {step.get('atomic_guid')}\n")
            fh.write(f"EXCEPTION: {type(exc).__name__}: {exc}\n")
            fh.write("TRACEBACK:\n")
            fh.write(traceback.format_exc())
            fh.write("\n")

        return str(path)
    except Exception:
        return None


def _section_title(value):
    return str(value or "uncategorized").replace("_", " ").upper()


def _print_tactic_header(tactic, count=None):
    title = _section_title(tactic)
    suffix = f"  |  {count} TESTS" if count is not None else ""

    print()
    print("=" * 78)
    print(f"  {title}{suffix}")
    print("=" * 78)


def _print_result_header(test_id, technique, name, mode):
    print()
    print(f"  {test_id:<7} {technique:<11} {name}")
    print(f"  MODE      {mode.upper()}")
    print("  " + "-" * 74)


def _print_result_summary(status, exit_code, duration, event_count):
    exit_text = "-" if exit_code is None else str(exit_code)

    print(
        f"  STATUS    {status:<12} "
        f"EXIT {exit_text:<4} "
        f"TIME {duration:>7.2f}s   "
        f"EVENTS {event_count}"
    )


def _clean_output_lines(value):
    if not value:
        return []

    lines = []
    skip_clixml = False

    for raw in str(value).splitlines():
        line = raw.rstrip()
        stripped = line.strip()

        if not stripped:
            continue

        if stripped.startswith("#< CLIXML"):
            skip_clixml = True
            continue

        if skip_clixml:
            if stripped.startswith("<"):
                continue
            skip_clixml = False

        if stripped.startswith("<"):
            continue

        if stripped.startswith("PathToAtomicsFolder ="):
            continue

        if stripped.startswith("Running Atomic Tests"):
            continue

        if stripped.startswith("Progress:"):
            continue

        lines.append(line)

    return lines


def _summarize_account_context(lines):
    result = []
    user = None
    sid = None
    groups = []

    for line in lines:
        stripped = line.strip()

        if "\\" in stripped and "S-1-" in stripped:
            parts = stripped.split()

            if not user and parts:
                user = parts[0]

            for part in parts:
                if part.startswith("S-1-"):
                    sid = part
                    break

        if (
            "Administrators" in stripped
            or "Authenticated Users" in stripped
            or "Users" in stripped
        ):
            groups.append(stripped)

    if user:
        result.append(f"User        {user}")

    if sid:
        result.append(f"SID         {sid}")

    if groups:
        compact = []
        for group in groups[:4]:
            if group not in compact:
                compact.append(group)
        result.append("Groups")
        result.extend(f"  - {item}" for item in compact)

    return result


def _summarize_atomic_output(lines):
    priority = []
    other = []

    interesting = (
        "Executing test:",
        "Done executing test:",
        "Executing cleanup for test:",
        "Done executing cleanup for test:",
        "SUCCESS:",
        "FAILED",
        "Method execution successful.",
        "CreateService SUCCESS",
        "OpenService FAILED",
        "StartService:",
        "ReturnValue =",
        "ProcessId =",
        "Hello, from PowerShell!",
    )

    for line in lines:
        stripped = line.strip()

        if stripped.startswith(interesting):
            priority.append(stripped)
        else:
            other.append(line)

    merged = priority[:10]

    for line in other:
        if len(merged) >= 12:
            break

        if line.strip() not in merged:
            merged.append(line)

    return merged


def _print_output(
    label,
    value,
    max_lines=10,
    atomic=False,
    action=None,
    evidence_hint=None
):
    lines = _clean_output_lines(value)

    if not lines:
        return

    if atomic:
        lines = _summarize_atomic_output(lines)
    elif action == "whoami":
        summary = _summarize_account_context(lines)
        if summary:
            lines = summary

    print()
    print(f"  {label.upper()}")
    print("  " + "-" * 60)

    shown = lines[:max_lines]

    for line in shown:
        print(f"    {line}")

    if len(lines) > max_lines:
        hint = evidence_hint or "per-test evidence file"
        print(f"    ... more output available in {hint}")



def load_yaml(path):
    with open(
        path,
        "r",
        encoding="utf-8"
    ) as f:
        return yaml.safe_load(f)


def validate_atomic_scenario_allowlist(scenario_name="full"):
    """Return Atomic scenario tests that are missing from config.yaml allowlist."""
    config = load_yaml(ROOT / "config.yaml")
    scenario = load_yaml(ROOT / "scenarios" / f"{scenario_name}.yaml")

    allowed = {
        (
            item.get("technique"),
            str(item.get("guid", "")).lower()
        )
        for item in config.get("atomic", {}).get("tests", [])
    }

    missing = []

    for step in scenario.get("steps", []):
        if step.get("backend") != "atomic":
            continue

        key = (
            step.get("atomic_technique"),
            str(step.get("atomic_guid", "")).lower()
        )

        if key not in allowed:
            missing.append({
                "id": step.get("id"),
                "technique": step.get("atomic_technique"),
                "guid": step.get("atomic_guid"),
                "name": step.get("name"),
            })

    return missing


def preflight():
    print("[+] PurplePOC preflight")

    print(
        "[PASS] Host:",
        socket.gethostname()
    )

    domain = os.environ.get(
        "USERDNSDOMAIN"
    )

    if domain:
        print(
            "[PASS] Domain:",
            domain
        )
    else:
        print(
            "[WARN] Host does not appear domain joined"
        )

    missing = validate_atomic_scenario_allowlist("full")

    if missing:
        print(
            f"[FAIL] Atomic allowlist consistency: "
            f"{len(missing)} scenario test(s) are not allowlisted"
        )

        for item in missing:
            print(
                "[FAIL]   "
                f"{item.get('technique')} / {item.get('guid')} / "
                f"{item.get('name')}"
            )

        return 1

    print(
        "[PASS] Atomic allowlist consistency: "
        "all scenario Atomic tests are allowlisted"
    )

    return 0


def run_scenario(name, non_interactive=False, skip_guided=False, phase="all", resume_run_id=None, techniques=None, tactics=None, tests=None):
    init_db()

    # Unattended when explicitly requested (--non-interactive) or when there is
    # no console to prompt on (piped stdin / scheduled task / CI). In that case
    # guided steps are auto-skipped. PurplePOC still never auto-executes them.
    interactive = (not non_interactive) and sys.stdin.isatty()

    config = load_yaml(
        ROOT / "config.yaml"
    )

    scenario_path = (
        ROOT
        / "scenarios"
        / f"{name}.yaml"
    )

    scenario = load_yaml(
        scenario_path
    )

    missing_atomic = validate_atomic_scenario_allowlist(name)

    if missing_atomic:
        details = "; ".join(
            f"{item.get('technique')} / {item.get('guid')}"
            for item in missing_atomic
        )
        raise RuntimeError(
            "Atomic scenario/allowlist consistency check failed before execution: "
            + details
        )

    techniques = {str(x).upper() for x in (techniques or []) if str(x).strip()}
    tactics = {str(x).lower().replace(" ", "_") for x in (tactics or []) if str(x).strip()}
    tests = {str(x).upper() for x in (tests or []) if str(x).strip()}

    indexed_steps = list(
        enumerate(
            scenario.get("steps", []),
            start=1
        )
    )

    def selected(original_index, step):
        test_id = f"T-{original_index:03d}"

        if techniques and str(step.get("technique", "")).upper() not in techniques:
            return False

        if tactics and str(step.get("tactic", "")).lower() not in tactics:
            return False

        if tests and test_id.upper() not in tests:
            return False

        return True

    selected_steps = [
        (original_index, step)
        for original_index, step in indexed_steps
        if selected(original_index, step)
    ]

    if not selected_steps:
        raise RuntimeError(
            "Selection matched zero scenario tests. "
            "Use Start-PurplePOC.ps1 -List to inspect available tests."
        )

    run_id = resume_run_id or str(
        uuid.uuid4()
    )

    host = socket.gethostname()

    domain = (
        os.environ.get(
            "USERDNSDOMAIN"
        )
        or config.get(
            "scope",
            {}
        ).get(
            "domain"
        )
    )

    operator = getpass.getuser()

    started = datetime.now(
        timezone.utc
    )

    if not resume_run_id:
        insert_run((
            run_id,
            scenario.get(
                "name",
                name
            ),
            host,
            domain,
            operator,
            started.isoformat(),
            None
        ))

        LAST_RUN_FILE.write_text(
            run_id,
            encoding="utf-8"
        )

    context = {
        "run_id": run_id,
        "host": host,
        "domain": domain,
        "operator": operator,
        "target": host
    }

    print()
    print(
        "[+] Run ID:",
        run_id
    )

    stop_scenario = False
    skip_remaining_guided = bool(skip_guided)
    current_tactic = None

    for original_index, step in selected_steps:
        step_id = str(uuid.uuid4())
        test_id = f"T-{original_index:03d}"

        mode = step.get(
            "mode",
            "auto"
        )

        if phase == "auto" and mode != "auto":
            continue

        if phase == "guided" and mode != "guided":
            continue

        tactic = step.get(
            "tactic",
            "uncategorized"
        )

        if tactic != current_tactic:
            current_tactic = tactic

            tactic_count = sum(
                1
                for _, item in selected_steps
                if item.get("tactic", "uncategorized") == tactic
            )

            _print_tactic_header(
                tactic,
                tactic_count
            )

        name_display = step.get(
            "name",
            step.get(
                "id"
            )
        )

        technique = step.get(
            "technique"
        )

        tool = step.get(
            "tool"
        )

        target = context.get(
            "target"
        )

        _print_result_header(
            test_id,
            technique,
            name_display,
            mode
        )

        step_start = datetime.now(
            timezone.utc
        )

        status = "UNKNOWN"
        exit_code = None
        stdout = ""
        stderr = ""

        context["test_id"] = test_id

        if mode == "auto":
            try:
                if step.get("backend") == "atomic":
                    result = atomic_execute(
                        step["atomic_technique"],
                        step["atomic_guid"],
                        test_id=test_id
                    )
                else:
                    result = auto_execute(
                        step["action"],
                        context
                    )

                exit_code = result.get("exit_code")
                stdout = result.get("stdout", "")
                stderr = result.get("stderr", "")

                status = (
                    "COMPLETED"
                    if exit_code == 0
                    else "FAILED"
                )

            except AtomicPolicyError as exc:
                # Policy/configuration mismatch: the test was not executed and
                # must not be scored as an attack execution failure.
                exit_code = None
                status = "POLICY_BLOCKED"
                stdout = ""
                stderr = f"ATOMIC POLICY BLOCKED: {exc}"

                crash_path = _write_crash_log(
                    run_id,
                    test_id,
                    step,
                    exc
                )

                print(f"  POLICY    {stderr}")

                if crash_path:
                    print(f"  CRASHLOG  {crash_path}")

                print(
                    "  CONTINUE  Test not executed; scenario continues"
                )

            except Exception as exc:
                # A broken Atomic/action must never terminate the complete run.
                exit_code = 1
                status = "FAILED"
                stdout = ""
                stderr = (
                    f"UNEXPECTED TEST EXCEPTION: "
                    f"{type(exc).__name__}: {exc}"
                )

                crash_path = _write_crash_log(
                    run_id,
                    test_id,
                    step,
                    exc
                )

                print(
                    f"  ERROR     {stderr}"
                )

                if crash_path:
                    print(
                        f"  CRASHLOG  {crash_path}"
                    )

                print(
                    "  CONTINUE  Scenario execution continues with next test"
                )

            step_end = datetime.now(timezone.utc)

        elif mode == "guided":
            if skip_remaining_guided:
                guided = {
                    "status": "SKIPPED",
                    "note": "all guided tests skipped"
                }
            else:
                guided = run_guided(
                    step,
                    context,
                    interactive
                )

            status = guided.get(
                "status",
                "UNKNOWN"
            )

            if guided.get("stop_scenario"):
                stop_scenario = True

            if guided.get("skip_all_guided"):
                skip_remaining_guided = True

            step_start = guided.get(
                "started",
                step_start
            )

            step_end = guided.get(
                "ended",
                datetime.now(
                    timezone.utc
                )
            )

        else:
            status = "SKIPPED"

            step_end = datetime.now(
                timezone.utc
            )

        try:
            events = collect_security_events(
                step_start,
                step_end
            )
        except Exception as telemetry_exc:
            events = []
            telemetry_error = (
                f"TELEMETRY COLLECTION ERROR: "
                f"{type(telemetry_exc).__name__}: {telemetry_exc}"
            )

            if stderr:
                stderr = stderr + "\n" + telemetry_error
            else:
                stderr = telemetry_error

            crash_path = _write_crash_log(
                run_id,
                test_id,
                step,
                telemetry_exc
            )

            print(f"  WARN      {telemetry_error}")

            if crash_path:
                print(f"  CRASHLOG  {crash_path}")

        duration_seconds = max(
            0.0,
            (step_end - step_start).total_seconds()
        )

        insert_step((
            step_id,
            run_id,
            test_id,
            name_display,
            technique,
            step.get("tactic"),
            mode.upper(),
            tool,
            step.get("backend"),
            step.get("action"),
            step.get("atomic_guid"),
            target,
            status,
            exit_code,
            stdout,
            stderr,
            len(events),
            step_start.isoformat(),
            step_end.isoformat(),
            duration_seconds
        ))

        insert_observation(
            step_id,
            {
                "source": "windows",
                "telemetry_seen": bool(events),
                "alert_seen": False,
                "prevented": (status == "PREVENTED"),
                "raw": {
                    "test_id": test_id,
                    "events": events
                }
            }
        )

        console_cfg = config.get("console", {})

        _print_result_summary(
            status,
            exit_code,
            duration_seconds,
            len(events)
        )

        is_atomic = step.get("backend") == "atomic"

        if console_cfg.get(
            "show_command_output",
            True
        ):
            _print_output(
                "Output",
                stdout,
                max_lines=int(
                    console_cfg.get(
                        "output_preview_max_lines",
                        10
                    )
                ),
                atomic=is_atomic,
                action=step.get("action"),
                evidence_hint=(
                    f"reports/<run-id>/evidence/{test_id}/stdout.txt"
                )
            )

        if stderr:
            _print_output(
                "Error Output",
                stderr,
                max_lines=int(
                    console_cfg.get(
                        "error_preview_max_lines",
                        6
                    )
                ),
                atomic=is_atomic,
                action=step.get("action"),
                evidence_hint=(
                    f"reports/<run-id>/evidence/{test_id}/stderr.txt"
                )
            )

        if status == "FAILED" and stderr:
            reason = stderr.strip().splitlines()[0] if stderr.strip() else ""
            if reason:
                print(f"  REASON    : {reason}")

        if stop_scenario:
            print()
            print("[+] Operator requested scenario stop")
            print("[+] Proceeding to cleanup and report generation")
            break

    if phase == "auto":
        print()
        print("[+] AUTO/Atomic phase completed")
        print("[+] Run remains open for GUIDED phase")
        return run_id

    ended = datetime.now(
        timezone.utc
    )

    update_run_end(
        run_id,
        ended.isoformat()
    )

    print()
    print(
        "[+] Scenario completed"
    )

    cleanup_cfg = config.get("cleanup", {})

    if cleanup_cfg.get("enabled", True):
        print()
        print("[+] Final cleanup verification")

        if cleanup_cfg.get("retry_pending_at_end", True):
            retry_pending()

        csum = cleanup_summary()

        print(f"        Total:   {csum['total']}")
        print(f"        Clean:   {csum['clean']}")
        print(f"        Pending: {csum['pending']}")
        print(f"        Failed:  {csum['failed']}")

    return run_id


def report():
    run_id = LAST_RUN_FILE.read_text(
        encoding="utf-8"
    ).strip()

    try:
        out = generate(
            run_id
        )
    except Exception as exc:
        import traceback
        logs = ROOT / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        path = logs / f"report-crash-{run_id}.log"
        path.write_text(
            traceback.format_exc(),
            encoding="utf-8",
            errors="replace"
        )
        print(
            f"[FAIL] Report generation error: "
            f"{type(exc).__name__}: {exc}"
        )
        print(
            f"[FAIL] Diagnostic log: {path}"
        )
        raise

    print(
        "[+] Report:",
        out / "report.html"
    )

    return out


def main():
    parser = argparse.ArgumentParser()

    sub = parser.add_subparsers(
        dest="command",
        required=True
    )

    sub.add_parser(
        "preflight"
    )

    run_parser = sub.add_parser(
        "run"
    )

    run_parser.add_argument(
        "--scenario",
        default="full"
    )

    run_parser.add_argument(
        "--non-interactive",
        "-y",
        dest="non_interactive",
        action="store_true",
        help="Run unattended; guided steps are auto-skipped (never executed)."
    )

    guided_group = run_parser.add_mutually_exclusive_group()

    guided_group.add_argument(
        "--guided",
        action="store_true",
        help="Enable interactive GUIDED tests. Disabled by default."
    )

    guided_group.add_argument(
        "--skip-guided",
        action="store_true",
        help="Skip all GUIDED tests while still running AUTO/Atomic tests."
    )

    run_parser.add_argument(
        "--phase",
        choices=["all", "auto", "guided"],
        default="all",
        help="Run the full scenario, AUTO/Atomic phase only, or GUIDED phase only."
    )

    run_parser.add_argument(
        "--resume-run-id",
        default=None,
        help="Resume an existing run for the GUIDED phase."
    )

    run_parser.add_argument(
        "--technique",
        action="append",
        default=[],
        help="Select MITRE technique. Repeat for multiple techniques."
    )

    run_parser.add_argument(
        "--tactic",
        action="append",
        default=[],
        help="Select MITRE tactic. Repeat for multiple tactics."
    )

    run_parser.add_argument(
        "--test",
        action="append",
        default=[],
        help="Select exact PurplePOC test ID such as T-052. Repeat for multiple tests."
    )

    sub.add_parser(
        "report"
    )

    args = parser.parse_args()

    if args.command == "preflight":
        raise SystemExit(
            preflight()
        )

    if args.command == "run":
        # GUIDED is opt-in for normal/full runs. An explicit
        # "--phase guided" is also considered an intentional guided run.
        effective_skip_guided = bool(
            args.skip_guided
            or (
                not args.guided
                and args.phase != "guided"
            )
        )

        run_scenario(
            args.scenario,
            args.non_interactive,
            effective_skip_guided,
            args.phase,
            args.resume_run_id,
            args.technique,
            args.tactic,
            args.test
        )

    if args.command == "report":
        report()


if __name__ == "__main__":
    main()
'@

# --------------------------------------------------------------------
# Setup-AtomicRedTeam.ps1
# --------------------------------------------------------------------

Write-File "Setup-AtomicRedTeam.ps1" @'
[CmdletBinding()]
param(
    [switch]$Force,
    [string]$Proxy
)

$ErrorActionPreference = "Stop"

$PurplePOCRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$PurplePOCRoot\UI.ps1"

$ProxyConfigFile = Join-Path $PurplePOCRoot "data\proxy.txt"

if (
    [string]::IsNullOrWhiteSpace($Proxy) `
    -and (Test-Path $ProxyConfigFile)
) {
    $Proxy = (Get-Content $ProxyConfigFile -Raw).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:PIP_PROXY = $Proxy

    try {
        $ProxyObject = New-Object System.Net.WebProxy -ArgumentList $Proxy
        [System.Net.WebRequest]::DefaultWebProxy = $ProxyObject
    }
    catch {}

    Write-Info "Proxy" "configured"
}

$AtomicBase = Join-Path $PurplePOCRoot "tools\atomic-red-team"
$AtomicDefinitions = Join-Path $AtomicBase "atomics"
$AtomicStatusDir = Join-Path $PurplePOCRoot "data"
$AtomicStatusFile = Join-Path $AtomicStatusDir "atomic-status.json"

New-Item -ItemType Directory -Path $AtomicStatusDir -Force | Out-Null

function Test-InternetName {
    param([string]$Name)

    try {
        [void][System.Net.Dns]::GetHostAddresses($Name)
        return $true
    }
    catch {
        return $false
    }
}

function Get-AtomicTechniqueFolders {
    if (-not (Test-Path $AtomicDefinitions)) {
        return @()
    }

    return @(
        Get-ChildItem `
            -Path $AtomicDefinitions `
            -Directory `
            -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^T\d{4}' }
    )
}

# Do not leave a stale READY status behind from an earlier successful run.
if (Test-Path $AtomicStatusFile) {
    Remove-Item $AtomicStatusFile -Force -ErrorAction SilentlyContinue
}

Write-Section "Atomic Red Team Setup" Magenta

try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor `
        [Net.SecurityProtocolType]::Tls12
} catch {}

$ExistingModule = Get-Module -ListAvailable -Name invoke-atomicredteam |
    Select-Object -First 1
$ExistingYamlModule = Get-Module -ListAvailable -Name powershell-yaml |
    Select-Object -First 1
$TechniqueFolders = Get-AtomicTechniqueFolders

# Fast/offline path: if everything required already exists, never touch PSGallery,
# GitHub, NuGet, or the network.
if (
    -not $Force `
    -and $ExistingModule `
    -and $ExistingYamlModule `
    -and @($TechniqueFolders).Count -gt 0
) {
    Write-Pass "invoke-atomicredteam module already available"
    Write-Pass "powershell-yaml module already available"
    Write-Pass "Atomic Red Team definitions already present"
    Write-Info "Technique folders" "$(@($TechniqueFolders).Count)"
}
else {
    $NeedsModule = (-not $ExistingModule) -or (-not $ExistingYamlModule)
    $NeedsDefinitions = (@($TechniqueFolders).Count -eq 0)

    if ($NeedsModule) {
        if (
            -not (Test-InternetName -Name "www.powershellgallery.com") `
            -and [string]::IsNullOrWhiteSpace($Proxy)
        ) {
            throw "Required PowerShell module is missing and www.powershellgallery.com cannot be resolved."
        }

        try {
            $NuGet = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue

            if (-not $NuGet) {
                Write-Step "Installing NuGet package provider"
                $NuGetArgs = @{
                    Name = "NuGet"
                    Scope = "CurrentUser"
                    Force = $true
                    Confirm = $false
                    ErrorAction = "Stop"
                }

                if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
                    $NuGetArgs["Proxy"] = $Proxy
                }

                Install-PackageProvider @NuGetArgs | Out-Null
            }
            else {
                Write-Pass "NuGet provider already available"
            }
        }
        catch {
            throw "NuGet provider setup failed: $($_.Exception.Message)"
        }

        try {
            $Repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($Repo -and $Repo.InstallationPolicy -ne "Trusted") {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            }
        }
        catch {
            Write-Warning "Could not set PSGallery as trusted: $($_.Exception.Message)"
        }

        foreach ($Module in @("invoke-atomicredteam", "powershell-yaml")) {
            $Installed = Get-Module -ListAvailable -Name $Module | Select-Object -First 1

            if ($Force -or -not $Installed) {
                Write-Step "Installing PowerShell module: $Module"

                try {
                    $ModuleArgs = @{
                        Name = $Module
                        Scope = "CurrentUser"
                        Force = $true
                        AllowClobber = $true
                        Confirm = $false
                        ErrorAction = "Stop"
                    }

                    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
                        $ModuleArgs["Proxy"] = $Proxy
                    }

                    Install-Module @ModuleArgs
                }
                catch {
                    throw "PowerShell module installation failed for ${Module}: $($_.Exception.Message)"
                }
            }
            else {
                Write-Pass "Module already available: $Module"
            }
        }
    }
    else {
        Write-Pass "Required PowerShell modules already available - skipping PSGallery"
    }

    Import-Module invoke-atomicredteam -Force -ErrorAction Stop

    if ($Force -or $NeedsDefinitions) {
        if (
            -not (Test-InternetName -Name "raw.githubusercontent.com") `
            -and [string]::IsNullOrWhiteSpace($Proxy)
        ) {
            throw "Atomic definitions are missing and raw.githubusercontent.com cannot be resolved."
        }

        Write-Step "Loading official Atomic Red Team atomics-folder installer"

        $InstallerUrl = "https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicsfolder.ps1"

        $WebArgs = @{
            Uri = $InstallerUrl
            UseBasicParsing = $true
            TimeoutSec = 30
            ErrorAction = "Stop"
        }

        if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
            $WebArgs["Proxy"] = $Proxy
        }

        $InstallerResponse = Invoke-WebRequest @WebArgs

        if (-not $InstallerResponse.Content) {
            throw "Official Atomic installer returned empty content."
        }

        & ([scriptblock]::Create($InstallerResponse.Content))

        if (-not (Get-Command Install-AtomicsFolder -ErrorAction SilentlyContinue)) {
            $SavedPurplePOCRoot = $PurplePOCRoot
            $SavedAtomicBase = $AtomicBase
            $SavedAtomicDefinitions = $AtomicDefinitions
            $SavedAtomicStatusDir = $AtomicStatusDir
            $SavedAtomicStatusFile = $AtomicStatusFile

            Invoke-Expression $InstallerResponse.Content

            $PurplePOCRoot = $SavedPurplePOCRoot
            $AtomicBase = $SavedAtomicBase
            $AtomicDefinitions = $SavedAtomicDefinitions
            $AtomicStatusDir = $SavedAtomicStatusDir
            $AtomicStatusFile = $SavedAtomicStatusFile
        }

        if (-not (Get-Command Install-AtomicsFolder -ErrorAction SilentlyContinue)) {
            throw "Install-AtomicsFolder was not defined by the official installer script."
        }

        New-Item -ItemType Directory -Path $AtomicBase -Force | Out-Null

        Write-Step "Installing Atomic Red Team definitions"
        Write-Info "Network source" "raw.githubusercontent.com / Atomic Red Team"
        Write-Info "Install path" $AtomicBase
        Write-Info "Status" "Download/extraction may take several minutes on first install"

        Install-AtomicsFolder `
            -InstallPath $AtomicBase `
            -DownloadPath $AtomicBase `
            -Force:$Force

        $PurplePOCRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
        $AtomicBase = Join-Path $PurplePOCRoot "tools\atomic-red-team"
        $AtomicDefinitions = Join-Path $AtomicBase "atomics"
        $AtomicStatusDir = Join-Path $PurplePOCRoot "data"
        $AtomicStatusFile = Join-Path $AtomicStatusDir "atomic-status.json"
    }
    else {
        Write-Pass "Atomic definitions already present - skipping download"
    }

    $TechniqueFolders = Get-AtomicTechniqueFolders
}

# Authoritative verification.
$ModuleOk = [bool](Get-Module -ListAvailable -Name invoke-atomicredteam)
$YamlOk = [bool](Get-Module -ListAvailable -Name powershell-yaml)
$TechniqueFolders = Get-AtomicTechniqueFolders

if (-not $ModuleOk) {
    throw "Atomic Red Team setup failed: invoke-atomicredteam module unavailable."
}
if (-not $YamlOk) {
    throw "Atomic Red Team setup failed: powershell-yaml module unavailable."
}
if (@($TechniqueFolders).Count -eq 0) {
    throw "Atomic Red Team setup failed: no technique folders detected under $AtomicDefinitions"
}

$Status = @{
    status = "READY"
    timestamp = (Get-Date).ToString("o")
    module = "invoke-atomicredteam"
    module_available = $ModuleOk
    yaml_module_available = $YamlOk
    atomic_base = $AtomicBase
    atomics_root = $AtomicDefinitions
    atomics_root_exists = (Test-Path $AtomicDefinitions)
    technique_folder_count = @($TechniqueFolders).Count
    offline_reuse = (-not $Force)
}

$Status |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        -Path $AtomicStatusFile `
        -Encoding UTF8

Write-Pass "Atomic Red Team READY"
Write-Info "Base" $AtomicBase
Write-Info "Atomics" $AtomicDefinitions
Write-Info "Technique folders" "$(@($TechniqueFolders).Count)"

'@


Confirm-GeneratedFile "Setup-AtomicRedTeam.ps1" -Critical | Out-Null


# --------------------------------------------------------------------
# Setup-GuidedTools.ps1
# --------------------------------------------------------------------

Write-File "Setup-GuidedTools.ps1" @'
[CmdletBinding()]
param(
    [switch]$Quiet,
    [string]$Proxy
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$Root\UI.ps1"
$ProxyConfigFile = Join-Path $Root "data\proxy.txt"

if (
    [string]::IsNullOrWhiteSpace($Proxy) `
    -and (Test-Path $ProxyConfigFile)
) {
    $Proxy = (Get-Content $ProxyConfigFile -Raw).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:PIP_PROXY = $Proxy

    try {
        $ProxyObject = New-Object System.Net.WebProxy -ArgumentList $Proxy
        [System.Net.WebRequest]::DefaultWebProxy = $ProxyObject
    }
    catch {}

    Write-Info "Proxy" "configured"
}

$Venv = Join-Path $env:LOCALAPPDATA "PurplePOC\.venv"
$Python = Join-Path $Venv "Scripts\python.exe"

function Show-Info {
    param([string]$Text)
    if (-not $Quiet) { Write-Host $Text }
}

if (-not (Test-Path $Python)) {
    throw "PurplePOC venv is missing. Run Bootstrap.ps1 first."
}

if (-not $Quiet) { Write-Section "GUIDED Tool Setup" DarkCyan }

# Certipy is installed from PyPI into PurplePOC's private venv.
if (-not $Quiet) { Write-Step "Ensuring Certipy is available" }
$CertipyArgs = @(
    "-m", "pip", "install",
    "--disable-pip-version-check",
    "--upgrade", "certipy-ad"
)

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $CertipyArgs += @("--proxy", $Proxy)
}

& $Python @CertipyArgs

if ($LASTEXITCODE -ne 0) {
    Write-Warning "Certipy installation failed. ADCS GUIDED tests will show the tool as unavailable."
}

# Create expected folders for operator-approved tools. PurplePOC deliberately
# does not fetch credential/domain-compromise binaries or invoke their
# high-risk functions. The GUIDED UI tells the operator where each approved
# engagement tool belongs and records its SHA256 when present.
$Folders = @(
    "tools\rubeus",
    "tools\mimikatz",
    "tools\impacket",
    "tools\seatbelt",
    "tools\sharpup"
)

foreach ($Folder in $Folders) {
    $Path = Join-Path $Root $Folder
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

if (-not $Quiet) { Write-Pass "GUIDED tool staging paths prepared" }
Show-Info "    Rubeus     tools\rubeus\Rubeus.exe"
Show-Info "    Mimikatz   tools\mimikatz\mimikatz.exe"
Show-Info "    secretsdump tools\impacket\secretsdump.py"
Show-Info "    Seatbelt   tools\seatbelt\Seatbelt.exe"
Show-Info "    SharpUp    tools\sharpup\SharpUp.exe"
Show-Info ""
Show-Info "[+] Certipy is bootstrap-managed; critical operator tools are engagement-staged and integrity-recorded."
'@


Confirm-GeneratedFile "Setup-GuidedTools.ps1" -Critical | Out-Null


# --------------------------------------------------------------------
# UI.ps1
# --------------------------------------------------------------------

Write-File "UI.ps1" @'
$script:PurplePOCTranscriptPath = $null
$script:PurplePOCCrashLogPath = $null

function Initialize-PurplePOCLogging {
    param(
        [string]$Root,
        [string]$Component = "runtime"
    )

    if (-not $Root) {
        return
    }

    $LogDir = Join-Path $Root "logs"
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $Transcript = Join-Path $LogDir ("purplepoc-{0}-{1}.log" -f $Component, $Stamp)
    $CrashLog = Join-Path $LogDir ("crash-{0}-{1}.log" -f $Component, $Stamp)
    $Latest = Join-Path $LogDir "latest.log"

    $script:PurplePOCTranscriptPath = $Transcript
    $script:PurplePOCCrashLogPath = $CrashLog

    # Avoid nested transcripts when Start -> Bootstrap / Validate -> Bootstrap.
    if ($env:PURPLEPOC_TRANSCRIPT_ACTIVE -ne "1") {
        try {
            Start-Transcript -Path $Transcript -Append -Force | Out-Null
            $env:PURPLEPOC_TRANSCRIPT_ACTIVE = "1"
            $env:PURPLEPOC_TRANSCRIPT_PATH = $Transcript
        }
        catch {
            Add-Content -Path $CrashLog -Value (
                "[{0}] TRANSCRIPT_START_FAILED {1}" -f `
                (Get-Date -Format "o"), $_.Exception.Message
            )
        }
    }
    else {
        $Transcript = $env:PURPLEPOC_TRANSCRIPT_PATH
        $script:PurplePOCTranscriptPath = $Transcript
    }

    try {
        if ($Transcript -and (Test-Path $Transcript)) {
            Copy-Item -Path $Transcript -Destination $Latest -Force
        }
        else {
            Set-Content -Path $Latest -Value (
                "PurplePOC logging initialized at {0}" -f (Get-Date -Format "o")
            ) -Encoding UTF8
        }
    }
    catch {}

    return @{
        transcript = $script:PurplePOCTranscriptPath
        crash = $script:PurplePOCCrashLogPath
        latest = $Latest
    }
}

function Stop-PurplePOCLogging {
    if ($env:PURPLEPOC_TRANSCRIPT_ACTIVE -eq "1") {
        try {
            Stop-Transcript | Out-Null
        }
        catch {}

        $env:PURPLEPOC_TRANSCRIPT_ACTIVE = $null
        $env:PURPLEPOC_TRANSCRIPT_PATH = $null
    }
}

function Write-CrashLog {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [string]$Stage = "unknown",
        [string]$RunId = "",
        [string]$Root = ""
    )

    if (-not $script:PurplePOCCrashLogPath -and $Root) {
        $LogDir = Join-Path $Root "logs"
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $script:PurplePOCCrashLogPath = Join-Path $LogDir ("crash-{0}.log" -f $Stamp)
    }

    $Path = $script:PurplePOCCrashLogPath

    if (-not $Path) {
        return
    }

    $Lines = @(
        "============================================================"
        "PurplePOC CRASH REPORT"
        "============================================================"
        "Timestamp : $(Get-Date -Format o)"
        "Stage     : $Stage"
        "Run ID    : $RunId"
        "Host      : $env:COMPUTERNAME"
        "User      : $env:USERDOMAIN\$env:USERNAME"
        "PSVersion : $($PSVersionTable.PSVersion)"
        "LastExit  : $LASTEXITCODE"
        ""
        "Exception:"
        "$($ErrorRecord.Exception.Message)"
        ""
        "Position:"
        "$($ErrorRecord.InvocationInfo.PositionMessage)"
        ""
        "Script stack:"
        "$($ErrorRecord.ScriptStackTrace)"
        ""
        "Full error:"
        "$($ErrorRecord | Out-String)"
    )

    $Lines | Set-Content -Path $Path -Encoding UTF8

    return $Path
}

function Write-Section {
    param(
        [string]$Title,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    Write-Host ""
    Write-Host ("=" * 68) -ForegroundColor DarkGray
    Write-Host ("  " + $Title) -ForegroundColor $Color
    Write-Host ("=" * 68) -ForegroundColor DarkGray
}

function Write-Step {
    param([string]$Message)

    Write-Host "[+] " -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

function Write-Pass {
    param([string]$Message)

    Write-Host "[PASS] " -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor White
}

function Write-WarnFancy {
    param([string]$Message)

    Write-Host "[WARN] " -NoNewline -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)

    Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
}

function Write-Info {
    param(
        [string]$Label,
        [string]$Value
    )

    Write-Host ("{0,-18}" -f ($Label + ":")) -NoNewline -ForegroundColor DarkCyan
    Write-Host $Value -ForegroundColor Gray
}

function Set-PurplePOCConsoleTheme {
    param([string]$Title = "PurplePOC Elevated Execution Console")

    try {
        $Host.UI.RawUI.WindowTitle = $Title
    }
    catch {}

    try {
        $RawUI = $Host.UI.RawUI
        $RawUI.BackgroundColor = [ConsoleColor]::Black
        $RawUI.ForegroundColor = [ConsoleColor]::White

        # Paint the complete existing buffer black as well. Merely changing
        # BackgroundColor is not enough when an elevated powershell.exe starts
        # with the classic blue Windows PowerShell console background.
        $Buffer = $RawUI.BufferSize

        if ($Buffer.Width -gt 0 -and $Buffer.Height -gt 0) {
            $Rectangle = New-Object System.Management.Automation.Host.Rectangle `
                0, 0, ($Buffer.Width - 1), ($Buffer.Height - 1)

            $Cell = New-Object System.Management.Automation.Host.BufferCell `
                ' ', `
                ([ConsoleColor]::White), `
                ([ConsoleColor]::Black), `
                ([System.Management.Automation.Host.BufferCellType]::Complete)

            $RawUI.SetBufferContents($Rectangle, $Cell)
        }
    }
    catch {}

    try {
        Clear-Host
    }
    catch {}
}

function Write-ElevatedSessionCard {
    param([string]$Scenario,[string]$RunId = "")
    $Domain = if ($env:USERDNSDOMAIN) { $env:USERDNSDOMAIN } else { "(not domain joined)" }

    Write-Host ""
    Write-Host ("+" + ("-" * 74) + "+") -ForegroundColor DarkCyan
    Write-Host "|  PurplePOC Elevated Execution Environment" -ForegroundColor Cyan
    Write-Host ("+" + ("-" * 74) + "+") -ForegroundColor DarkCyan
    Write-Info "User" "$env:USERDOMAIN\$env:USERNAME"
    Write-Info "Host" $env:COMPUTERNAME
    Write-Info "Domain" $Domain
    Write-Info "Scenario" $Scenario
    if ($RunId) { Write-Info "Run ID" $RunId }
    Write-Info "Session" "Elevated / High Integrity"
    Write-Info "Started" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Host ("+" + ("-" * 74) + "+") -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-ExecutionStage {
    param([string]$Title,[int]$Number,[int]$Total)
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host ("  [{0}/{1}] {2}" -f $Number,$Total,$Title) -ForegroundColor Magenta
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}

function Write-ScenarioModeBadge {
    param([string]$Scenario,[bool]$SkipGuided)
    Write-Host "  Scenario : " -NoNewline -ForegroundColor DarkCyan
    Write-Host $Scenario -ForegroundColor White
    Write-Host "  GUIDED   : " -NoNewline -ForegroundColor DarkCyan
    if ($SkipGuided) { Write-Host "SKIPPED" -ForegroundColor Yellow }
    else { Write-Host "INTERACTIVE" -ForegroundColor Green }
    Write-Host ""
}


function Write-Banner {
    param(
        [string]$Subtitle = "Purple Team Detection Validation"
    )

    Clear-Host

    Write-Host ""
    Write-Host "  PPPP   U   U  RRRR   PPPP   L      EEEEE  PPPP    OOO    CCC " -ForegroundColor Magenta
    Write-Host "  P   P  U   U  R   R  P   P  L      E      P   P  O   O  C    " -ForegroundColor Magenta
    Write-Host "  PPPP   U   U  RRRR   PPPP   L      EEEE   PPPP   O   O  C    " -ForegroundColor Magenta
    Write-Host "  P      U   U  R  R   P      L      E      P      O   O  C    " -ForegroundColor Magenta
    Write-Host "  P       UUU   R   R  P      LLLLL  EEEEE  P       OOO    CCC " -ForegroundColor Magenta
    Write-Host ""
    Write-Host ("  " + $Subtitle) -ForegroundColor Cyan
    Write-Host "  by Jan Fischbach" -NoNewline -ForegroundColor DarkGray
    Write-Host "  |  " -NoNewline -ForegroundColor DarkGray
    Write-Host "v1.0.12" -NoNewline -ForegroundColor Magenta
    Write-Host "  |  August 2026" -ForegroundColor DarkGray
    Write-Host ""
}
'@
# --------------------------------------------------------------------
# Bootstrap.ps1
# --------------------------------------------------------------------

Write-File "Bootstrap.ps1" @'
[CmdletBinding()]
param(
    [string]$Proxy
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

. "$Root\UI.ps1"

$ProxyConfigFile = Join-Path $Root "data\proxy.txt"

if (
    [string]::IsNullOrWhiteSpace($Proxy) `
    -and (Test-Path $ProxyConfigFile)
) {
    $Proxy = (Get-Content $ProxyConfigFile -Raw).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:PIP_PROXY = $Proxy

    try {
        $ProxyObject = New-Object System.Net.WebProxy -ArgumentList $Proxy
        [System.Net.WebRequest]::DefaultWebProxy = $ProxyObject
    }
    catch {}

    Write-Info "Proxy" "configured"
}

$Logging = Initialize-PurplePOCLogging -Root $Root -Component "bootstrap"

function Test-PythonDependencies {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Python
    )

    # Avoid `python -c` entirely on Windows PowerShell 5.1. Passing Python code
    # through the native-command argument parser is fragile because embedded
    # quotes can be stripped/re-tokenized. A temporary .py file is deterministic.
    $ProbeFile = Join-Path $env:TEMP ("PurplePOC-python-probe-" + [guid]::NewGuid().ToString() + ".py")
    $OutFile = Join-Path $env:TEMP ("PurplePOC-python-probe-" + [guid]::NewGuid().ToString() + ".out")
    $ErrFile = Join-Path $env:TEMP ("PurplePOC-python-probe-" + [guid]::NewGuid().ToString() + ".err")

    $ProbeSource = @"
import importlib.util
required = {
    'yaml': 'pyyaml',
    'rich': 'rich',
    'requests': 'requests',
    'pytest': 'pytest',
    'PySide6': 'PySide6',
}
missing = [pkg for mod, pkg in required.items() if importlib.util.find_spec(mod) is None]
print(','.join(missing) if missing else 'OK')
raise SystemExit(10 if missing else 0)
"@

    try {
        [System.IO.File]::WriteAllText(
            $ProbeFile,
            $ProbeSource,
            (New-Object System.Text.UTF8Encoding($false))
        )

        # Temporarily relax only around the native probe. A non-zero Python exit
        # is expected when packages are missing and must be handled as data.
        $SavedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        try {
            & $Python $ProbeFile 1>$OutFile 2>$ErrFile
            $Code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $SavedErrorActionPreference
        }

        $OutputText = ""
        $ErrorText = ""

        if (Test-Path $OutFile) {
            $OutputText = Get-Content -Path $OutFile -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path $ErrFile) {
            $ErrorText = Get-Content -Path $ErrFile -Raw -ErrorAction SilentlyContinue
        }

        $Combined = @(
            $OutputText
            $ErrorText
        ) | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }

        return @{
            Ready = ($Code -eq 0)
            ExitCode = $Code
            Output = (($Combined -join "`n").Trim())
        }
    }
    finally {
        Remove-Item $ProbeFile,$OutFile,$ErrFile -Force -ErrorAction SilentlyContinue
    }
}

function Test-DnsResolution {
    param([string]$Name)

    try {
        [void][System.Net.Dns]::GetHostAddresses($Name)
        return $true
    }
    catch {
        return $false
    }
}

function Select-PurplePOCPythonRuntime {
    param(
        [string]$ProjectRoot
    )

    $Candidates = New-Object System.Collections.Generic.List[string]

    function Add-Candidate([string]$Path) {
        if (
            -not [string]::IsNullOrWhiteSpace($Path) `
            -and -not $Candidates.Contains($Path)
        ) {
            $Candidates.Add($Path)
        }
    }

    Add-Candidate (Join-Path $ProjectRoot ".venv\Scripts\python.exe")
    Add-Candidate $env:PURPLEPOC_PYTHON

    $RuntimeFile = Join-Path $ProjectRoot "data\python-runtime.txt"
    if (Test-Path $RuntimeFile) {
        Add-Candidate ((Get-Content $RuntimeFile -Raw -ErrorAction SilentlyContinue).Trim())
    }

    Add-Candidate (Join-Path $env:LOCALAPPDATA "PurplePOC\.venv\Scripts\python.exe")

    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($PythonCommand) {
        Add-Candidate $PythonCommand.Source
    }

    $LocalPythonRoot = Join-Path $env:LOCALAPPDATA "Programs\Python"
    if (Test-Path $LocalPythonRoot) {
        Get-ChildItem `
            -Path $LocalPythonRoot `
            -Filter python.exe `
            -File `
            -Recurse `
            -ErrorAction SilentlyContinue |
        ForEach-Object {
            Add-Candidate $_.FullName
        }
    }

    foreach ($Candidate in $Candidates) {
        if (-not (Test-Path $Candidate)) {
            continue
        }

        Write-Info "Checking existing runtime" $Candidate
        $State = Test-PythonDependencies -Python $Candidate

        if ($State.Ready) {
            return @{
                Python = $Candidate
                DependencyState = $State
                Reused = ($Candidate -ne (Join-Path $ProjectRoot ".venv\Scripts\python.exe"))
            }
        }
    }

    return $null
}


Write-Banner "Environment Bootstrap"
Write-Section "Bootstrap" Cyan

Write-Step "Checking Python"

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail "Python is missing and winget is unavailable."
        throw "Python is missing and winget is unavailable."
    }

    Write-Step "Installing Python 3.12"

    winget install `
        --id Python.Python.3.12 `
        -e `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Python installation failed with exit code $LASTEXITCODE"
        throw "Python installation failed."
    }

    $env:PATH =
        [System.Environment]::GetEnvironmentVariable(
            "PATH",
            "Machine"
        ) +
        ";" +
        [System.Environment]::GetEnvironmentVariable(
            "PATH",
            "User"
        )
}

Write-Pass "Python available"

$ProjectPython = "$Root\.venv\Scripts\python.exe"
$SharedPython = Join-Path $env:LOCALAPPDATA "PurplePOC\.venv\Scripts\python.exe"
$RuntimeSelection = Select-PurplePOCPythonRuntime -ProjectRoot $Root

if ($RuntimeSelection) {
    $Python = $RuntimeSelection.Python

    if ($RuntimeSelection.Reused) {
        Write-Pass "Reusable PurplePOC Python runtime found"
        Write-Info "Runtime" $Python
        Write-WarnFancy "Project-local .venv is incomplete; using existing shared PurplePOC runtime offline."
    }
    else {
        Write-Pass "Project virtual environment already present and complete"
    }

    Write-Pass "Python dependencies already available - skipping pip/network access"
}
else {
    if (-not (Test-Path $ProjectPython)) {
        Write-Step "Creating Python virtual environment"

        python -m venv "$Root\.venv"

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ProjectPython)) {
            Write-Fail "Virtual environment creation failed"
            throw "Virtual environment creation failed."
        }

        Write-Pass "Virtual environment created"
    }
    else {
        Write-WarnFancy "Project virtual environment exists but required packages are incomplete."
    }

    $Python = $ProjectPython

    Write-Step "Checking Python + desktop GUI dependencies"
    $DependencyState = Test-PythonDependencies -Python $Python

    if ($DependencyState.Ready) {
        Write-Pass "Python dependencies already available - skipping pip/network access"
    }
    else {
        Write-WarnFancy "Python dependencies are incomplete: $($DependencyState.Output)"

        # One more offline opportunity: an older/shared PurplePOC runtime may
        # have become available after the project venv was created.
        if (Test-Path $SharedPython) {
            $SharedState = Test-PythonDependencies -Python $SharedPython
            if ($SharedState.Ready) {
                $Python = $SharedPython
                Write-Pass "Using shared PurplePOC runtime with complete dependencies"
                Write-Info "Runtime" $Python
            }
        }

        if ($Python -eq $ProjectPython -and -not $DependencyState.Ready) {
            $PyPiDns = Test-DnsResolution -Name "pypi.org"

            if (-not $PyPiDns -and [string]::IsNullOrWhiteSpace($Proxy)) {
                Write-Fail "Required Python packages are missing and pypi.org cannot be resolved."
                Write-Fail "No complete reusable PurplePOC/System Python runtime was found."
                Write-Fail "PurplePOC will not claim READY while dependencies are unavailable."
                Write-Info "Missing dependency probe" $DependencyState.Output
                Write-WarnFancy "Once dependencies are installed successfully, future PurplePOC upgrades preserve the .venv and will not reinstall them."
                throw "Offline bootstrap blocked: missing Python dependencies, no reusable runtime, and no DNS resolution for pypi.org."
            }

            Write-Step "Installing Python dependencies"

            $PythonVersion = & $Python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"
            if ($LASTEXITCODE -eq 0) {
                Write-Info "Python runtime version" $PythonVersion
            }

            $PipArgs = @(
                "-m", "pip", "install",
                "--disable-pip-version-check",
                "--retries", "2",
                "--timeout", "15"
            )

            if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
                $PipArgs += @("--proxy", $Proxy)
            }

            $PipArgs += @("-r", "$Root\requirements.txt")
            & $Python @PipArgs

            if ($LASTEXITCODE -ne 0) {
                Write-Fail "pip dependency installation failed with exit code $LASTEXITCODE"
                throw "Python dependency installation failed."
            }

            $DependencyState = Test-PythonDependencies -Python $Python

            if (-not $DependencyState.Ready) {
                Write-Fail "Python dependency verification failed after pip install."
                Write-Info "Dependency probe" $DependencyState.Output
                throw "Python dependencies are still incomplete after installation."
            }

            Write-Pass "Python dependencies installed and verified"
        }
    }
}

# Persist the selected runtime so Start-PurplePOC and rich_app use the same
# interpreter even when the project-local .venv is incomplete.
$RuntimePathFile = Join-Path $Root "data\python-runtime.txt"
New-Item -ItemType Directory -Path (Split-Path -Parent $RuntimePathFile) -Force | Out-Null
Set-Content -Path $RuntimePathFile -Value $Python -Encoding ASCII
$env:PURPLEPOC_PYTHON = $Python

Write-Section "Atomic Red Team" Magenta

$AtomicSetup = Join-Path $Root "Setup-AtomicRedTeam.ps1"

if (Test-Path $AtomicSetup) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
            & $AtomicSetup -Proxy $Proxy
        }
        else {
            & $AtomicSetup
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Atomic Red Team setup returned exit code $LASTEXITCODE"
            throw "Atomic Red Team setup failed."
        }
    }
    catch {
        Write-Fail "Atomic Red Team setup FAILED: $($_.Exception.Message)"
        throw
    }
}
else {
    Write-Fail "Setup-AtomicRedTeam.ps1 is missing."
    throw "Atomic setup file missing."
}

Write-Section "GUIDED Tool Preparation" DarkCyan

$GuidedSetup = Join-Path $Root "Setup-GuidedTools.ps1"

if (Test-Path $GuidedSetup) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
            & $GuidedSetup -Quiet -Proxy $Proxy
        }
        else {
            & $GuidedSetup -Quiet
        }
    }
    catch {
        # GUIDED tooling is optional because GUIDED execution is opt-in.
        Write-WarnFancy "Optional GUIDED tool preparation failed: $($_.Exception.Message)"
        Write-WarnFancy "AUTO/Atomic execution can continue if core checks pass."
    }
}
else {
    Write-WarnFancy "Setup-GuidedTools.ps1 is missing."
}

# Final verification is authoritative.
$DependencyState = Test-PythonDependencies -Python $Python
if (-not $DependencyState.Ready) {
    Write-Fail "Final Python dependency verification FAILED"
    throw "PurplePOC bootstrap verification failed."
}

$AtomicStatusFile = Join-Path $Root "data\atomic-status.json"
if (-not (Test-Path $AtomicStatusFile)) {
    Write-Fail "Atomic status file missing after setup."
    throw "PurplePOC bootstrap verification failed: Atomic status missing."
}

Write-Section "Bootstrap Summary" Green
Write-Pass "PurplePOC environment is READY"
Write-Info "Runtime" $Python
Write-Info "Project Root" $Root

'@
# --------------------------------------------------------------------
# Start-PurplePOC.ps1
# --------------------------------------------------------------------

Write-File "Start-PurplePOC-GUI.ps1" @'
[CmdletBinding()]
param(
    [string]$Proxy
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root
. "$Root\UI.ps1"

Set-PurplePOCConsoleTheme "Windows PowerShell (Elevated) - PurplePOC GUI"
Write-Banner "PurplePOC Desktop GUI"
$ProxyConfigFile = Join-Path $Root "data\proxy.txt"

if (
    [string]::IsNullOrWhiteSpace($Proxy) `
    -and (Test-Path $ProxyConfigFile)
) {
    $Proxy = (Get-Content $ProxyConfigFile -Raw).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:PIP_PROXY = $Proxy

    try {
        $ProxyObject = New-Object System.Net.WebProxy -ArgumentList $Proxy
        [System.Net.WebRequest]::DefaultWebProxy = $ProxyObject
    }
    catch {}

    Write-Info "Proxy" "configured"
}

$LogDir=Join-Path $Root "logs"
New-Item -ItemType Directory -Path $LogDir -Force|Out-Null
$GuiLog=Join-Path $LogDir ("gui-start-"+(Get-Date -Format "yyyyMMdd-HHmmss")+".log")
try{Start-Transcript -Path $GuiLog -Force|Out-Null}catch{}
try{
$Identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$Principal=New-Object Security.Principal.WindowsPrincipal($Identity)
if(-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 Write-WarnFancy "Administrator privileges required"
 $RelaunchArgs = "-NoExit -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
 if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
     $RelaunchArgs += " -Proxy `"$Proxy`""
 }
 Start-Process powershell.exe $RelaunchArgs -Verb RunAs
 exit
}
$RuntimeFile=Join-Path $Root "data\python-runtime.txt"
if($env:PURPLEPOC_PYTHON -and (Test-Path $env:PURPLEPOC_PYTHON)){$Python=$env:PURPLEPOC_PYTHON}elseif(Test-Path $RuntimeFile){$Python=(Get-Content $RuntimeFile -Raw).Trim()}else{$Python="$Root\.venv\Scripts\python.exe"}
if(-not (Test-Path $Python)){
 if(-not [string]::IsNullOrWhiteSpace($Proxy)){& "$Root\Bootstrap.ps1" -Proxy $Proxy}else{& "$Root\Bootstrap.ps1"}
 if(Test-Path $RuntimeFile){$Python=(Get-Content $RuntimeFile -Raw).Trim()}
}
$env:PURPLEPOC_PYTHON=$Python
Write-Info "GUI Python runtime" $Python
$Old=$ErrorActionPreference;$ErrorActionPreference="Continue"
try{& $Python -c "import PySide6,yaml,rich" *> $null;$Ready=($LASTEXITCODE -eq 0)}finally{$ErrorActionPreference=$Old}
if(-not $Ready){
 Write-Step "Installing/verifying GUI dependencies"
 if(-not [string]::IsNullOrWhiteSpace($Proxy)){& "$Root\Bootstrap.ps1" -Proxy $Proxy}else{& "$Root\Bootstrap.ps1"}
 if(Test-Path $RuntimeFile){$Python=(Get-Content $RuntimeFile -Raw).Trim()}
 $env:PURPLEPOC_PYTHON=$Python
 $Old=$ErrorActionPreference;$ErrorActionPreference="Continue"
 try{& $Python -c "import PySide6,yaml,rich" *> $null;$Ready=($LASTEXITCODE -eq 0)}finally{$ErrorActionPreference=$Old}
 if(-not $Ready){
  Write-Fail "PySide6 is still unavailable after Bootstrap."
  Write-Info "Runtime" $Python
  Write-WarnFancy "Check PyPI/DNS/proxy access or install PySide6 into this runtime."
  throw "PurplePOC GUI runtime validation failed."
 }
}
& $Python "$Root\gui\main.py"
if($LASTEXITCODE -ne 0){
 Write-Fail "PurplePOC Desktop exited with code $LASTEXITCODE"
 Write-WarnFancy "CLI remains available via .\Start-PurplePOC.ps1"
 throw "PurplePOC Desktop process failed with exit code $LASTEXITCODE"
}

}
catch{
 Write-Host ""
 Write-Fail "PurplePOC GUI startup FAILED"
 Write-Host $_.Exception.Message -ForegroundColor Red
 Write-Host "Diagnostic log:" -ForegroundColor Yellow
 Write-Host $GuiLog -ForegroundColor Cyan
 try{Add-Content -Path $GuiLog -Value ("`nEXCEPTION:`n"+($_|Out-String)) -Encoding UTF8}catch{}
 Write-Host ""
 Write-Host "Press ENTER to keep this console available for diagnosis." -ForegroundColor Yellow
 [void](Read-Host)
 exit 1
}
finally{try{Stop-Transcript|Out-Null}catch{}}

'@

Write-File "Start-PurplePOC.ps1" @'
[CmdletBinding()]
param(
    [string]$Scenario = "full",

    [Alias("Mitre")]
    [string[]]$Technique,

    [string[]]$Tactic,

    [string[]]$Test,

    [ValidateSet("All","Auto","Guided")]
    [string]$Phase = "All",

    [switch]$Guided,
    [switch]$SkipGuided,
    [switch]$List,
    [switch]$Help,

    [string]$Proxy,

    [switch]$ElevatedChild
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

. "$Root\UI.ps1"

$ProxyConfigFile = Join-Path $Root "data\proxy.txt"

if (
    [string]::IsNullOrWhiteSpace($Proxy) `
    -and (Test-Path $ProxyConfigFile)
) {
    $Proxy = (Get-Content $ProxyConfigFile -Raw).Trim()
}

if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
    $Proxy = $Proxy.Trim()
    $env:HTTP_PROXY = $Proxy
    $env:HTTPS_PROXY = $Proxy
    $env:PIP_PROXY = $Proxy

    try {
        $ProxyObject = New-Object System.Net.WebProxy -ArgumentList $Proxy
        [System.Net.WebRequest]::DefaultWebProxy = $ProxyObject
    }
    catch {}

    Write-Info "Proxy" "configured"
}

function Show-PurplePOCHelp {
    Write-Host ""
    Write-Host "PurplePOC 1.0.12 - Selective MITRE Execution" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor Magenta
    Write-Host "  .\Start-PurplePOC.ps1 [options]"
    Write-Host ""
    Write-Host "SELECTION" -ForegroundColor Magenta
    Write-Host "  -Technique T1048                 Run every test mapped to T1048"
    Write-Host "  -Technique T1048,T1041,T1567     Run multiple MITRE techniques"
    Write-Host "  -Tactic Exfiltration             Run the complete Exfiltration tactic"
    Write-Host "  -Test T-052                      Run exactly one PurplePOC test"
    Write-Host "  -List                            List available tests"
    Write-Host ""
    Write-Host "EXECUTION" -ForegroundColor Magenta
    Write-Host "  -Phase Auto                      AUTO/Atomic tests only"
    Write-Host "  -Phase Guided                    GUIDED tests only (explicit opt-in)"
    Write-Host "  -Guided                          Enable GUIDED phase after AUTO"
    Write-Host "  -SkipGuided                      Explicitly skip GUIDED tests"
    Write-Host "  -Proxy http://proxy:8080         Proxy for pip / PSGallery / GitHub downloads"
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor Magenta
    Write-Host "  .\Start-PurplePOC.ps1 -Technique T1048"
    Write-Host "  .\Start-PurplePOC.ps1 -Technique T1048,T1041 -Phase Auto"
    Write-Host "  .\Start-PurplePOC.ps1 -Tactic Exfiltration"
    Write-Host "  .\Start-PurplePOC.ps1 -Test T-052"
    Write-Host "  .\Start-PurplePOC.ps1 -List -Tactic Exfiltration"
    Write-Host "  .\Start-PurplePOC.ps1 -Technique T1048 -Proxy http://proxy:8080"
    Write-Host ""
    Write-Host "Selector semantics: OR within one selector type, AND across selector types." -ForegroundColor DarkGray
    Write-Host "Reports contain only the selected/executed test set." -ForegroundColor DarkGray
    Write-Host ""
}

if ($Help) {
    Show-PurplePOCHelp
    exit 0
}

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

function Add-QuotedArrayArgument {
    param(
        [System.Collections.Generic.List[string]]$Target,
        [string]$Name,
        [string[]]$Values
    )

    if ($Values) {
        foreach ($Value in $Values) {
            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                $Target.Add($Name)
                $Target.Add($Value)
            }
        }
    }
}

if (-not $IsAdmin) {
    Write-Banner "Purple Team Detection Validation"
    Write-WarnFancy "Administrator privileges required"
    Write-Step "Relaunching elevated PurplePOC application"

    $ElevatedArgs = New-Object 'System.Collections.Generic.List[string]'
    $ElevatedArgs.Add("-NoExit")
    $ElevatedArgs.Add("-NoProfile")
    $ElevatedArgs.Add("-ExecutionPolicy")
    $ElevatedArgs.Add("Bypass")
    $ElevatedArgs.Add("-File")
    $ElevatedArgs.Add("`"$PSCommandPath`"")
    $ElevatedArgs.Add("-Scenario")
    $ElevatedArgs.Add("`"$Scenario`"")

    Add-QuotedArrayArgument $ElevatedArgs "-Technique" $Technique
    Add-QuotedArrayArgument $ElevatedArgs "-Tactic" $Tactic
    Add-QuotedArrayArgument $ElevatedArgs "-Test" $Test

    if ($Phase -ne "All") {
        $ElevatedArgs.Add("-Phase")
        $ElevatedArgs.Add($Phase)
    }
    if ($Guided) { $ElevatedArgs.Add("-Guided") }
    if ($SkipGuided) { $ElevatedArgs.Add("-SkipGuided") }
    if ($List) { $ElevatedArgs.Add("-List") }

    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        $ElevatedArgs.Add("-Proxy")
        $ElevatedArgs.Add("`"$Proxy`"")
    }

    $ElevatedArgs.Add("-ElevatedChild")

    Start-Process `
        powershell.exe `
        ($ElevatedArgs -join " ") `
        -Verb RunAs

    exit
}

try {
    $Host.UI.RawUI.WindowTitle = "Windows PowerShell (Elevated) - PurplePOC"
    $Host.UI.RawUI.BackgroundColor = "Black"
    $Host.UI.RawUI.ForegroundColor = "White"
    Clear-Host
} catch {}

if (-not (Test-Path "$Root\.venv\Scripts\python.exe")) {
    Write-Banner "Preparing Rich UI Runtime"
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        & "$Root\Bootstrap.ps1" -Proxy $Proxy
    }
    else {
        & "$Root\Bootstrap.ps1"
    }
}

$RuntimePathFile = Join-Path $Root "data\python-runtime.txt"

if ($env:PURPLEPOC_PYTHON -and (Test-Path $env:PURPLEPOC_PYTHON)) {
    $Python = $env:PURPLEPOC_PYTHON
}
elseif (Test-Path $RuntimePathFile) {
    $Python = (Get-Content $RuntimePathFile -Raw).Trim()
}
else {
    $Python = "$Root\.venv\Scripts\python.exe"
}

if (-not (Test-Path $Python)) {
    Write-Banner "Preparing Rich UI Runtime"
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) {
        & "$Root\Bootstrap.ps1" -Proxy $Proxy
    }
    else {
        & "$Root\Bootstrap.ps1"
    }

    if (Test-Path $RuntimePathFile) {
        $Python = (Get-Content $RuntimePathFile -Raw).Trim()
    }
}

$env:PURPLEPOC_PYTHON = $Python

# Core readiness gate. A prior failed bootstrap must not be bypassed by simply
# launching Start-PurplePOC.ps1 again.
$AtomicStatusFile = Join-Path $Root "data\atomic-status.json"

if (-not (Test-Path $Python)) {
    Write-Fail "Selected PurplePOC Python runtime does not exist: $Python"
    throw "PurplePOC runtime validation failed."
}

$PythonReady = $false
$SavedEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    & $Python -c "import yaml,rich,requests,pytest" *> $null
    $PythonReady = ($LASTEXITCODE -eq 0)
}
finally {
    $ErrorActionPreference = $SavedEap
}

if (-not $PythonReady) {
    Write-Fail "Selected Python runtime is missing required PurplePOC packages."
    Write-Info "Runtime" $Python
    throw "PurplePOC runtime validation failed."
}

if (-not (Test-Path $AtomicStatusFile)) {
    Write-Fail "Atomic Red Team is not in a verified READY state."
    Write-WarnFancy "Run .\Bootstrap.ps1 after fixing connectivity/module issues."
    throw "PurplePOC Atomic readiness validation failed."
}

try {
    $AtomicStatus = Get-Content $AtomicStatusFile -Raw | ConvertFrom-Json
}
catch {
    Write-Fail "Atomic status file is unreadable."
    throw "PurplePOC Atomic readiness validation failed."
}

if ($AtomicStatus.status -ne "READY") {
    Write-Fail "Atomic Red Team status is not READY."
    throw "PurplePOC Atomic readiness validation failed."
}

$ArgsList = @(
    "$Root\rich_app.py",
    "--scenario",
    $Scenario
)

foreach ($Value in $Technique) {
    $ArgsList += @("--technique", $Value)
}
foreach ($Value in $Tactic) {
    $ArgsList += @("--tactic", $Value)
}
foreach ($Value in $Test) {
    $ArgsList += @("--test", $Value)
}

if ($Phase -ne "All") {
    $ArgsList += @("--phase", $Phase.ToLowerInvariant())
}

if ($Guided) {
    $ArgsList += "--guided"
}
elseif ($SkipGuided) {
    $ArgsList += "--skip-guided"
}

if ($List) {
    $ArgsList += "--list"
}

& $Python @ArgsList

if ($LASTEXITCODE -ne 0) {
    Write-Host ""

    if ($LASTEXITCODE -eq 2) {
        Write-Host "PurplePOC command-line argument error." -ForegroundColor Red
        Write-Host "Use: .\Start-PurplePOC.ps1 -Help" -ForegroundColor Yellow
    }
    elseif ($LASTEXITCODE -eq 5) {
        Write-Host "PurplePOC self-test stage returned pytest exit code 5 (no tests collected)." -ForegroundColor Red
        Write-Host "Check .\tests\test_smoke.py and .\logs\rich-ui.log." -ForegroundColor Yellow
    }

    Write-Host "PurplePOC exited with code $LASTEXITCODE" -ForegroundColor Red
    Write-Host "Press ENTER to keep this elevated console open for diagnosis." -ForegroundColor Yellow
    [void](Read-Host)
}

'@
# --------------------------------------------------------------------
# README.md
# --------------------------------------------------------------------

Write-File "gui\__init__.py" @'
"""PurplePOC desktop GUI."""
'@

Write-File "gui\main.py" @'
from __future__ import annotations
import json, os, sys, subprocess, re
from pathlib import Path
import yaml
from PySide6.QtCore import Qt, QProcess, Signal
from PySide6.QtGui import QColor
from PySide6.QtWidgets import QApplication,QCheckBox,QComboBox,QFrame,QGridLayout,QHBoxLayout,QLabel,QLineEdit,QListWidget,QListWidgetItem,QMainWindow,QMessageBox,QPushButton,QPlainTextEdit,QProgressBar,QStackedWidget,QTableWidget,QTableWidgetItem,QVBoxLayout,QWidget,QHeaderView,QSplitter
ROOT=Path(__file__).resolve().parents[1]; SCENARIO=ROOT/'scenarios'/'full.yaml'; DATA=ROOT/'data'; REPORTS=ROOT/'reports'
def pyexe():
 p=os.environ.get('PURPLEPOC_PYTHON')
 if p and Path(p).exists(): return p
 f=DATA/'python-runtime.txt'
 if f.exists():
  p=f.read_text(encoding='utf-8').strip()
  if p and Path(p).exists(): return p
 return str(ROOT/'.venv'/'Scripts'/'python.exe')
def load_steps():
 d=yaml.safe_load(SCENARIO.read_text(encoding='utf-8')) or {}; out=[]
 for i,x in enumerate(d.get('steps',[]),1): y=dict(x); y['test_id']=f'T-{i:03d}'; out.append(y)
 return out
def lab(v): return str(v or 'uncategorized').replace('_',' ').title()
class Nav(QPushButton):
 def __init__(self,t): super().__init__(t); self.setCheckable(True); self.setMinimumHeight(42)
class Card(QFrame):
 def __init__(self,t,v,s=''):
  super().__init__(); self.setObjectName('card'); l=QVBoxLayout(self)
  for text,obj in [(t.upper(),'cardTitle'),(str(v),'cardValue'),(s,'cardSub')]: q=QLabel(text); q.setObjectName(obj); l.addWidget(q)
class TacticButton(QPushButton):
 def __init__(self,tactic,count):
  super().__init__(f'{lab(tactic)}\n{count} tests'); self.tactic=tactic; self.setObjectName('tacticButton'); self.setCheckable(True); self.setMinimumHeight(72)

class Dashboard(QWidget):
 open_browser_requested=Signal(str)
 def __init__(self,items):
  super().__init__(); self.items=items; self.selected_tactic=None; r=QVBoxLayout(self)
  t=QLabel('Detection Validation'); t.setObjectName('pageTitle'); r.addWidget(t)
  by=QLabel('by Jan Fischbach'); by.setStyleSheet('color:#7dd3fc;font-weight:600'); r.addWidget(by)

  row=QHBoxLayout()
  for c in [Card('Tests',len(items),'full scenario'),Card('AUTO',sum(x.get('mode')=='auto' for x in items),'default'),Card('GUIDED',sum(x.get('mode')=='guided' for x in items),'opt-in'),Card('Tactics',len({x.get('tactic') for x in items}),'MITRE')]: row.addWidget(c)
  r.addLayout(row)

  h=QLabel('MITRE ATT&CK Coverage - click a tactic'); h.setObjectName('sectionTitle'); r.addWidget(h)
  counts={}
  for x in items: counts[x.get('tactic','uncategorized')]=counts.get(x.get('tactic','uncategorized'),0)+1

  self.tactic_buttons={}
  tg=QGridLayout(); tg.setHorizontalSpacing(8); tg.setVerticalSpacing(8)
  for i,(k,v) in enumerate(sorted(counts.items())):
   btn=TacticButton(k,v); btn.clicked.connect(lambda _checked=False,tac=k:self.select_tactic(tac)); self.tactic_buttons[k]=btn; tg.addWidget(btn,i//4,i%4)
  r.addLayout(tg)

  self.explorer=QFrame(); self.explorer.setObjectName('mitreExplorer'); ex=QVBoxLayout(self.explorer); ex.setContentsMargins(12,10,12,10)
  top=QHBoxLayout(); self.explorer_title=QLabel('Select a MITRE tactic to inspect its tests'); self.explorer_title.setObjectName('explorerTitle'); self.open_browser=QPushButton('Open in MITRE Tests'); self.open_browser.setEnabled(False); self.open_browser.clicked.connect(self.open_selected_tactic); top.addWidget(self.explorer_title); top.addStretch(); top.addWidget(self.open_browser); ex.addLayout(top)

  split=QSplitter(Qt.Horizontal); split.setObjectName('mitreSplit')
  self.test_table=QTableWidget(0,4); self.test_table.setObjectName('mitreExplorerTable'); self.test_table.setHorizontalHeaderLabels(['Test ID','MITRE','Mode','Test']); self.test_table.verticalHeader().setVisible(False); self.test_table.setEditTriggers(QTableWidget.NoEditTriggers); self.test_table.setSelectionBehavior(QTableWidget.SelectRows); self.test_table.setSelectionMode(QTableWidget.SingleSelection); self.test_table.horizontalHeader().setSectionResizeMode(0,QHeaderView.ResizeToContents); self.test_table.horizontalHeader().setSectionResizeMode(1,QHeaderView.ResizeToContents); self.test_table.horizontalHeader().setSectionResizeMode(2,QHeaderView.ResizeToContents); self.test_table.horizontalHeader().setSectionResizeMode(3,QHeaderView.Stretch); self.test_table.itemSelectionChanged.connect(self.show_selected_test)
  split.addWidget(self.test_table)

  detail=QFrame(); detail.setObjectName('mitreDetail'); dl=QVBoxLayout(detail)
  self.detail_name=QLabel('Test details'); self.detail_name.setObjectName('detailName'); self.detail_name.setWordWrap(True); dl.addWidget(self.detail_name)
  self.detail_meta=QLabel(''); self.detail_meta.setObjectName('detailMeta'); self.detail_meta.setWordWrap(True); dl.addWidget(self.detail_meta)
  desc_label=QLabel('DESCRIPTION'); desc_label.setObjectName('detailLabel'); dl.addWidget(desc_label)
  self.detail_desc=QLabel('Choose a tactic, then select a test.'); self.detail_desc.setObjectName('detailText'); self.detail_desc.setWordWrap(True); self.detail_desc.setAlignment(Qt.AlignTop|Qt.AlignLeft); dl.addWidget(self.detail_desc)
  purpose_label=QLabel('PURPOSE / WHAT IT VALIDATES'); purpose_label.setObjectName('detailLabel'); dl.addWidget(purpose_label)
  self.detail_purpose=QLabel('-'); self.detail_purpose.setObjectName('detailText'); self.detail_purpose.setWordWrap(True); self.detail_purpose.setAlignment(Qt.AlignTop|Qt.AlignLeft); dl.addWidget(self.detail_purpose)
  action_label=QLabel('EXACT ACTION / WHAT PURPLEPOC RUNS'); action_label.setObjectName('detailLabel'); dl.addWidget(action_label)
  self.detail_action=QLabel('-'); self.detail_action.setObjectName('detailAction'); self.detail_action.setWordWrap(True); self.detail_action.setTextInteractionFlags(Qt.TextSelectableByMouse); self.detail_action.setAlignment(Qt.AlignTop|Qt.AlignLeft); dl.addWidget(self.detail_action)
  ports_label=QLabel('PROTOCOLS / PORTS'); ports_label.setObjectName('detailLabel'); dl.addWidget(ports_label)
  self.detail_ports=QLabel('-'); self.detail_ports.setObjectName('detailPorts'); self.detail_ports.setWordWrap(True); self.detail_ports.setAlignment(Qt.AlignTop|Qt.AlignLeft); dl.addWidget(self.detail_ports)
  dl.addStretch()
  split.addWidget(detail); split.setSizes([620,600]); ex.addWidget(split)
  r.addWidget(self.explorer,1)

 def select_tactic(self,tactic):
  self.selected_tactic=tactic
  for key,button in self.tactic_buttons.items(): button.setChecked(key==tactic)
  rows=[x for x in self.items if x.get('tactic','uncategorized')==tactic]
  self.explorer_title.setText(f'{lab(tactic)} - {len(rows)} tests')
  self.open_browser.setEnabled(True)
  self.test_table.setRowCount(len(rows))
  for row,item in enumerate(rows):
   values=[item.get('test_id','-'),item.get('technique','-'),item.get('mode','-').upper(),item.get('name','-')]
   for col,value in enumerate(values):
    cell=QTableWidgetItem(str(value)); cell.setData(Qt.UserRole,item.get('test_id')); self.test_table.setItem(row,col,cell)
  if rows:
   self.test_table.selectRow(0); self.show_selected_test()

 def show_selected_test(self):
  row=self.test_table.currentRow()
  if row<0:return
  tid=self.test_table.item(row,0).data(Qt.UserRole)
  item=next((x for x in self.items if x.get('test_id')==tid),None)
  if not item:return
  self.detail_name.setText(f'{item.get("test_id","-")}  |  {item.get("technique","-")}  |  {item.get("name","-")}')
  self.detail_meta.setText(f'{lab(item.get("tactic"))}  |  {str(item.get("mode","-")).upper()}  |  {item.get("action",item.get("backend","native"))}')
  self.detail_desc.setText(str(item.get('description') or 'No description available.'))
  details=item.get('execution_details') or {}
  self.detail_purpose.setText(str(details.get('purpose') or details.get('operation') or item.get('description') or '-'))
  operation=str(details.get('operation') or '-')
  implementation=str(details.get('implementation') or '-')
  command=str(details.get('command') or item.get('command') or 'No explicit command recorded.')
  self.detail_action.setText('Operation: '+operation+'\n\nImplementation: '+implementation+'\n\nInvocation: '+command)
  ds=item.get('detection_sources') or {}; ports=ds.get('protocols_ports') or []
  self.detail_ports.setText('\n'.join('- '+str(x) for x in ports) if ports else 'No protocol/port guidance defined.')

 def open_selected_tactic(self):
  if self.selected_tactic:self.open_browser_requested.emit(self.selected_tactic)
class Browser(QWidget):
 run_requested=Signal(list)
 def __init__(self,items):
  super().__init__(); self.items=items; r=QVBoxLayout(self); t=QLabel('MITRE Test Browser'); t.setObjectName('pageTitle'); r.addWidget(t); f=QHBoxLayout(); self.search=QLineEdit(); self.search.setPlaceholderText('Search T1048, Kerberos, Exfiltration, ADCS...'); self.tactic=QComboBox(); self.tactic.addItem('All tactics','')
  for x in sorted({i.get('tactic','') for i in items}): self.tactic.addItem(lab(x),x)
  self.mode=QComboBox(); self.mode.addItems(['All modes','AUTO','GUIDED']); f.addWidget(self.search,2); f.addWidget(self.tactic,1); f.addWidget(self.mode,1); r.addLayout(f)
  self.table=QTableWidget(0,6); self.table.setHorizontalHeaderLabels(['Run','Test ID','MITRE','Tactic','Mode','Name']); self.table.horizontalHeader().setSectionResizeMode(5,QHeaderView.Stretch); self.table.setEditTriggers(QTableWidget.NoEditTriggers); r.addWidget(self.table)
  b=QHBoxLayout(); a=QPushButton('Select visible'); c=QPushButton('Clear'); run=QPushButton('Run selected'); run.setObjectName('primary'); b.addWidget(a); b.addWidget(c); b.addWidget(run); b.addStretch(); r.addLayout(b)
  self.search.textChanged.connect(self.refresh); self.tactic.currentIndexChanged.connect(self.refresh); self.mode.currentIndexChanged.connect(self.refresh); a.clicked.connect(self.select_all); c.clicked.connect(self.clear); run.clicked.connect(self.request_run); self.refresh()
 def filtered(self):
  q=self.search.text().lower().strip(); tac=self.tactic.currentData(); mode=self.mode.currentText(); out=[]
  for x in self.items:
   hay=' '.join([x['test_id'],x.get('technique',''),x.get('name',''),x.get('tactic',''),x.get('description','')]).lower()
   if q and q not in hay: continue
   if tac and x.get('tactic')!=tac: continue
   if mode!='All modes' and x.get('mode','').upper()!=mode: continue
   out.append(x)
  return out
 def refresh(self):
  old=set(self.selected()); rows=self.filtered(); self.table.setRowCount(len(rows))
  for r,x in enumerate(rows):
   cb=QCheckBox(); cb.setChecked(x['test_id'] in old); w=QWidget(); l=QHBoxLayout(w); l.setContentsMargins(8,0,0,0); l.addWidget(cb); l.addStretch(); self.table.setCellWidget(r,0,w)
   for c,v in enumerate([x['test_id'],x.get('technique','-'),lab(x.get('tactic')),x.get('mode','-').upper(),x.get('name','-')],1): self.table.setItem(r,c,QTableWidgetItem(str(v)))
 def selected(self):
  out=[]
  for r in range(self.table.rowCount()):
   w=self.table.cellWidget(r,0); cb=w.findChild(QCheckBox) if w else None
   if cb and cb.isChecked(): out.append(self.table.item(r,1).text())
  return out
 def select_all(self):
  for r in range(self.table.rowCount()): self.table.cellWidget(r,0).findChild(QCheckBox).setChecked(True)
 def clear(self):
  for r in range(self.table.rowCount()): self.table.cellWidget(r,0).findChild(QCheckBox).setChecked(False)
 def request_run(self):
  selected=self.selected()
  if not selected:
   QMessageBox.information(self,'PurplePOC','Select at least one test first.')
   return
  self.run_requested.emit(selected)
 def set_tactic_filter(self,tactic):
  index=self.tactic.findData(tactic)
  if index>=0:self.tactic.setCurrentIndex(index)
  self.search.clear(); self.mode.setCurrentIndex(0); self.refresh()
class LiveStatusPanel(QFrame):
 def __init__(self,items):
  super().__init__(); self.items=items; self.setObjectName('executionPanel'); self.buffer=''; self.active=None; self.finished=set(); self.total=0; self.done_total=0; self.failed=0; self.skipped=0; self.totals={}; self.done={}; self.fail={}
  root=QVBoxLayout(self); root.setContentsMargins(12,8,12,8); root.setSpacing(7)
  top=QHBoxLayout(); top.setContentsMargins(0,0,0,0); title=QLabel('EXECUTION PIPELINE'); title.setObjectName('execTitle'); self.pipeline=QLabel('Runtime READY | Scenario IDLE | Report PENDING'); self.pipeline.setObjectName('pipeline'); top.addWidget(title); top.addStretch(); top.addWidget(self.pipeline); root.addLayout(top)
  cur=QFrame(); cur.setObjectName('currentTechnique'); cur.setMaximumHeight(88); grid=QGridLayout(cur); grid.setContentsMargins(9,6,9,6); grid.setVerticalSpacing(3)
  grid.addWidget(QLabel('CURRENT TECHNIQUE'),0,0); self.current=QLabel('-'); self.current.setObjectName('currentId'); grid.addWidget(self.current,0,1)
  grid.addWidget(QLabel('MODE'),1,0); self.mode=QLabel('-'); grid.addWidget(self.mode,1,1)
  grid.addWidget(QLabel('OVERALL'),2,0); self.overall_text=QLabel('0 / 0'); self.overall_text.setObjectName('overallText'); grid.addWidget(self.overall_text,2,1)
  self.overall=QProgressBar(); self.overall.setObjectName('overallProgress'); self.overall.setRange(0,100); self.overall.setTextVisible(False); self.overall.setFixedHeight(11); grid.addWidget(self.overall,3,0,1,2); root.addWidget(cur)
  m=QHBoxLayout(); self.done_label=QLabel('DONE  0'); self.fail_label=QLabel('FAILED  0'); self.skip_label=QLabel('SKIPPED  0'); self.done_label.setObjectName('metricDone'); self.fail_label.setObjectName('metricFailed'); self.skip_label.setObjectName('metricSkipped'); m.addWidget(self.done_label); m.addWidget(self.fail_label); m.addWidget(self.skip_label); m.addStretch(); root.addLayout(m)
  self.table=QTableWidget(0,4); self.table.setObjectName('coverageTable'); self.table.setHorizontalHeaderLabels(['MITRE TACTIC','PROGRESS','DONE','STATE']); self.table.verticalHeader().setVisible(False); self.table.setEditTriggers(QTableWidget.NoEditTriggers); self.table.setMaximumHeight(245); self.table.horizontalHeader().setSectionResizeMode(0,QHeaderView.Stretch); self.table.horizontalHeader().setSectionResizeMode(1,QHeaderView.Stretch); self.table.horizontalHeader().setSectionResizeMode(2,QHeaderView.ResizeToContents); self.table.horizontalHeader().setSectionResizeMode(3,QHeaderView.ResizeToContents); root.addWidget(self.table)
  fr=QHBoxLayout(); ft=QLabel('RECENT FAILURES'); ft.setObjectName('failTitle'); self.recent=QListWidget(); self.recent.setObjectName('recentFailures'); self.recent.setMaximumHeight(74); fr.addWidget(ft); fr.addWidget(self.recent,1); root.addLayout(fr)
 def begin(self,run_items):
  self.buffer=''; self.active=None; self.finished=set(); self.total=len(run_items); self.done_total=0; self.failed=0; self.skipped=0; self.totals={}; self.done={}; self.fail={}
  for x in run_items:
   tac=x.get('tactic','uncategorized'); self.totals[tac]=self.totals.get(tac,0)+1; self.done[tac]=0; self.fail[tac]=0
  self.current.setText('-  Waiting for scenario execution'); self.mode.setText('-'); self.overall.setValue(0); self.overall_text.setText(f'0 / {self.total}'); self.recent.clear()
  order=['discovery','execution','persistence','privilege_escalation','defense_evasion','lateral_movement','exfiltration','credential_access']; tactics=sorted(self.totals,key=lambda x:(order.index(x) if x in order else 99,x)); self.rows={}; self.table.setRowCount(len(tactics))
  row_height=29
  self.table.verticalHeader().setDefaultSectionSize(row_height)
  header_height=32
  table_height=header_height+(row_height*len(tactics))+6
  self.table.setFixedHeight(max(250,min(340,table_height)))
  for row,tac in enumerate(tactics):
   self.rows[tac]=row; self.table.setItem(row,0,QTableWidgetItem(lab(tac))); bar=QProgressBar(); bar.setRange(0,max(1,self.totals[tac])); bar.setTextVisible(False); self.table.setCellWidget(row,1,bar); self.table.setItem(row,2,QTableWidgetItem(f'0/{self.totals[tac]}')); state=QTableWidgetItem('PENDING'); state.setForeground(QColor('#7f8da3')); self.table.setItem(row,3,state)
  self.pipeline.setText('Runtime READY | Scenario STARTING | Report PENDING'); self.refresh()
 def refresh(self):
  self.overall.setValue(int(self.done_total*100/self.total) if self.total else 0); self.overall_text.setText(f'{self.done_total} / {self.total}'); self.done_label.setText(f'DONE  {self.done_total}'); self.fail_label.setText(f'FAILED  {self.failed}'); self.skip_label.setText(f'SKIPPED  {self.skipped}')
  for tac,row in getattr(self,'rows',{}).items():
   done=self.done.get(tac,0); total=self.totals.get(tac,0); failed=self.fail.get(tac,0); bar=self.table.cellWidget(row,1); bar.setMaximum(max(1,total)); bar.setValue(done); self.table.item(row,2).setText(f'{done}/{total}'); state=self.table.item(row,3)
   if total and done>=total: state.setText('COMPLETE'+(f'  {failed} fail' if failed else '')); state.setForeground(QColor('#32d46a' if not failed else '#ff5c66'))
   elif self.active and self.active.get('tactic')==tac: state.setText('RUNNING'); state.setForeground(QColor('#e83edb'))
   else: state.setText('PENDING'); state.setForeground(QColor('#7f8da3'))
 def feed(self,text):
  data=self.buffer+text; lines=data.split('\n'); self.buffer=lines.pop()
  for line in lines:self.parse(line.rstrip('\r'))
 def parse(self,line):
  m=re.match(r'^\s*(T-\d{3})\s+(T\d{4}(?:\.\d{3})?)\s+(.+?)\s*$',line)
  if m:
   tid,tech,name=m.groups(); self.active=next((x for x in self.items if x.get('test_id')==tid),None)
   if self.active:self.current.setText(f'{tid}   {tech}   {name}'); self.mode.setText(str(self.active.get('mode','-')).upper()); self.refresh()
   return
  m=re.match(r'^\s*STATUS\s+([A-Z_]+)\s+EXIT',line)
  if m and self.active:
   status=m.group(1); tid=self.active.get('test_id')
   if tid in self.finished:return
   self.finished.add(tid); self.done_total+=1; tac=self.active.get('tactic','uncategorized'); self.done[tac]=self.done.get(tac,0)+1
   if status in ('FAILED','POLICY_BLOCKED'):
    self.failed+=1; self.fail[tac]=self.fail.get(tac,0)+1; self.recent.insertItem(0,f'{tid}  {self.active.get("technique","-")}  {self.active.get("name","-")}')
    while self.recent.count()>4:self.recent.takeItem(self.recent.count()-1)
   if status=='SKIPPED':self.skipped+=1
   self.refresh()
 def started(self): self.pipeline.setText('Runtime READY | Scenario RUNNING | Report PENDING')
 def finish(self,code):
  if self.buffer:self.parse(self.buffer); self.buffer=''
  self.pipeline.setText('Runtime READY | Scenario COMPLETE | Report PENDING' if code==0 else f'Runtime READY | Scenario FAILED ({code}) | Report PENDING')
  if code==0 and self.done_total>=self.total:self.mode.setText('COMPLETE')
 def start_failed(self): self.pipeline.setText('Runtime READY | Scenario START FAILED | Report PENDING')
 def stopped(self): self.pipeline.setText('Runtime READY | Scenario STOPPED | Report PENDING')
 def report_running(self): self.pipeline.setText('Runtime READY | Scenario COMPLETE | Report RUNNING')
 def report_done(self,ok): self.pipeline.setText('Runtime READY | Scenario COMPLETE | Report '+('COMPLETE' if ok else 'FAILED'))

class Runner(QWidget):
 def __init__(self,items,browser):
  super().__init__(); self.items=items; self.browser=browser; self.proc=None; self.pending_ids=[]; r=QVBoxLayout(self)
  t=QLabel('Run Builder'); t.setObjectName('pageTitle'); r.addWidget(t)
  g=QGridLayout(); self.tactic=QComboBox(); self.tactic.addItem('All tactics','')
  for x in sorted({i.get('tactic','') for i in items}): self.tactic.addItem(lab(x),x)
  self.tech=QLineEdit(); self.tech.setPlaceholderText('e.g. T1048')
  self.phase=QComboBox(); self.phase.addItems(['AUTO only','AUTO + GUIDED','GUIDED only'])
  self.use_sel=QCheckBox('Use selected tests from Test Browser'); self.use_sel.setChecked(True)
  g.addWidget(QLabel('Tactic'),0,0); g.addWidget(self.tactic,0,1); g.addWidget(QLabel('Technique'),0,2); g.addWidget(self.tech,0,3)
  g.addWidget(QLabel('Phase'),1,0); g.addWidget(self.phase,1,1); g.addWidget(self.use_sel,1,2,1,2); r.addLayout(g)
  self.selection=QLabel('Selection: full scenario'); self.selection.setStyleSheet('color:#9cb0c8'); r.addWidget(self.selection)
  b=QHBoxLayout(); self.run=QPushButton('Run validation'); self.run.setObjectName('primary'); self.stop=QPushButton('Stop'); self.stop.setEnabled(False); self.report=QPushButton('Generate report')
  b.addWidget(self.run); b.addWidget(self.stop); b.addWidget(self.report); b.addStretch(); r.addLayout(b)
  self.live=LiveStatusPanel(items); r.addWidget(self.live)
  self.status=QLabel('READY'); self.status.hide()
  self.progress=QProgressBar(); self.progress.hide()
  self.log=QPlainTextEdit(); self.log.setReadOnly(True); self.log.setObjectName('log'); self.log.setMaximumHeight(170); r.addWidget(self.log)
  self.run.clicked.connect(self.start); self.stop.clicked.connect(self.kill); self.report.clicked.connect(self.make_report)
  self.browser.run_requested.connect(self.start_selected)
 def current_selection(self):
  if self.pending_ids: return list(self.pending_ids)
  if self.use_sel.isChecked(): return self.browser.selected()
  return []
 def effective_items(self):
  selected=set(self.current_selection()); tac=self.tactic.currentData(); tech=self.tech.text().strip().upper(); phase=self.phase.currentText(); out=[]
  for x in self.items:
   if selected and x.get('test_id') not in selected: continue
   if tac and x.get('tactic')!=tac: continue
   if tech and str(x.get('technique','')).upper()!=tech: continue
   if phase=='AUTO only' and x.get('mode')!='auto': continue
   if phase=='GUIDED only' and x.get('mode')!='guided': continue
   out.append(x)
  return out
 def args(self):
  a=['-u',str(ROOT/'controller.py'),'run','--scenario','full']
  selected=self.current_selection()
  for tid in selected: a += ['--test',tid]
  if self.tactic.currentData(): a += ['--tactic',self.tactic.currentData()]
  if self.tech.text().strip(): a += ['--technique',self.tech.text().strip().upper()]
  p=self.phase.currentText()
  if p=='AUTO only':
   a += ['--phase','auto','--skip-guided','--non-interactive']
  elif p=='GUIDED only':
   a += ['--phase','guided']
  else:
   a += ['--guided']
  return a
 def start_selected(self,ids):
  self.pending_ids=list(ids)
  self.use_sel.setChecked(True)
  self.selection.setText('Selection: '+', '.join(ids))
  self.start()
 def start(self):
  if self.proc and self.proc.state()!=QProcess.ProcessState.NotRunning:
   QMessageBox.information(self,'PurplePOC','A validation run is already active.')
   return
  selected=self.current_selection()
  if self.use_sel.isChecked() and not selected and (not self.tactic.currentData()) and (not self.tech.text().strip()):
   answer=QMessageBox.question(self,'Run full scenario','No individual tests are selected. Run the full scenario?')
   if answer!=QMessageBox.StandardButton.Yes: return
  run_items=self.effective_items()
  if not run_items:
   QMessageBox.warning(self,'PurplePOC','The current selection matches no tests.')
   return
  a=self.args()
  self.pending_ids=[]
  self.selection.setText('Selection: '+(', '.join(selected) if selected else 'full/filter selection'))
  self.live.begin(run_items)
  self.log.clear(); self.log.appendPlainText('$ '+pyexe()+' '+' '.join(a))
  self.run.setEnabled(False); self.stop.setEnabled(True)
  self.proc=QProcess(self); self.proc.setProgram(pyexe()); self.proc.setArguments(a); self.proc.setWorkingDirectory(str(ROOT))
  self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
  self.proc.readyReadStandardOutput.connect(self.read)
  self.proc.errorOccurred.connect(self.process_error)
  self.proc.started.connect(self.live.started)
  self.proc.finished.connect(self.done)
  self.proc.start()
  if not self.proc.waitForStarted(5000):
   self.process_error(self.proc.error())
 def read(self):
  if not self.proc: return
  text=bytes(self.proc.readAllStandardOutput()).decode('utf-8',errors='replace')
  if text:
   self.log.moveCursor(self.log.textCursor().MoveOperation.End)
   self.log.insertPlainText(text)
   self.live.feed(text)
 def process_error(self,error):
  detail=self.proc.errorString() if self.proc else str(error)
  self.live.start_failed()
  self.run.setEnabled(True); self.stop.setEnabled(False)
  self.log.appendPlainText('\n[GUI] QProcess error: '+detail)
  QMessageBox.critical(self,'PurplePOC run failed','Could not start the test runner.\n\n'+detail+'\n\nThe command is shown in Live Output.')
 def done(self,code,_status):
  self.read()
  self.live.finish(code)
  self.run.setEnabled(True); self.stop.setEnabled(False)
  if code!=0:
   self.log.appendPlainText(f'\n[GUI] controller.py exited with {code}.')
 def kill(self):
  if self.proc and self.proc.state()!=QProcess.ProcessState.NotRunning:
   self.proc.kill(); self.live.stopped()
 def make_report(self):
  self.live.report_running(); QApplication.processEvents()
  p=subprocess.run([pyexe(),str(ROOT/'controller.py'),'report'],cwd=str(ROOT),capture_output=True,text=True)
  self.log.appendPlainText((p.stdout or '')+(p.stderr or '')); self.live.report_done(p.returncode==0)
  if p.returncode: QMessageBox.critical(self,'Report failed','Check live output / report crash log.')
class Reports(QWidget):
 def __init__(self):
  super().__init__(); r=QVBoxLayout(self); t=QLabel('Reports'); t.setObjectName('pageTitle'); r.addWidget(t); self.list=QListWidget(); r.addWidget(self.list,1); b=QHBoxLayout(); a=QPushButton('Refresh'); o=QPushButton('Open selected report'); b.addWidget(a); b.addWidget(o); b.addStretch(); r.addLayout(b); a.clicked.connect(self.refresh); o.clicked.connect(self.open); self.refresh()
 def refresh(self):
  self.list.clear()
  if REPORTS.exists():
   for p in sorted(REPORTS.rglob('report.html'),key=lambda x:x.stat().st_mtime,reverse=True): i=QListWidgetItem(str(p.relative_to(ROOT))); i.setData(Qt.UserRole,str(p)); self.list.addItem(i)
 def open(self):
  i=self.list.currentItem()
  if i: os.startfile(i.data(Qt.UserRole))
class Tools(QWidget):
 def __init__(self):
  super().__init__(); r=QVBoxLayout(self); t=QLabel('Tool Status'); t.setObjectName('pageTitle'); r.addWidget(t); self.table=QTableWidget(0,3); self.table.setHorizontalHeaderLabels(['Component','Status','Details']); self.table.horizontalHeader().setSectionResizeMode(2,QHeaderView.Stretch); r.addWidget(self.table); b=QPushButton('Refresh'); b.clicked.connect(self.refresh); r.addWidget(b); self.refresh()
 def refresh(self):
  rows=[('Python','READY' if Path(pyexe()).exists() else 'MISSING',pyexe())]; f=DATA/'atomic-status.json'
  if f.exists():
   try: d=json.loads(f.read_text(encoding='utf-8-sig')); rows.append(('Atomic Red Team',d.get('status','UNKNOWN'),str(d.get('technique_folder_count','?'))+' technique folders'))
   except Exception as e: rows.append(('Atomic Red Team','ERROR',str(e)))
  else: rows.append(('Atomic Red Team','MISSING','No atomic-status.json'))
  for pkg in ('certipy-ad','impacket','ldap3','PySide6'):
   p=subprocess.run([pyexe(),'-c',f"import importlib.metadata as m; print(m.version('{pkg}'))"],capture_output=True,text=True); rows.append((pkg,'READY' if p.returncode==0 else 'MISSING',(p.stdout or p.stderr).strip()))
  self.table.setRowCount(len(rows))
  for rr,row in enumerate(rows):
   for cc,v in enumerate(row): self.table.setItem(rr,cc,QTableWidgetItem(str(v)))
class Window(QMainWindow):
 def __init__(self):
  super().__init__(); items=load_steps(); self.setWindowTitle('PurplePOC 1.0 | Detection Validation | by Jan Fischbach'); self.resize(1480,900); self.setMinimumSize(1180,720); shell=QWidget(); self.setCentralWidget(shell); l=QHBoxLayout(shell); l.setContentsMargins(0,0,0,0); l.setSpacing(0); side=QFrame(); side.setObjectName('sidebar'); side.setFixedWidth(220); sl=QVBoxLayout(side); sl.setContentsMargins(16,18,16,18); brand=QLabel('PURPLEPOC'); brand.setObjectName('brand'); ver=QLabel('v1.0.12  |  by Jan Fischbach'); ver.setObjectName('version'); sl.addWidget(brand); sl.addWidget(ver); sl.addSpacing(18); self.stack=QStackedWidget(); browser=Browser(items); dashboard=Dashboard(items); pages=[('Dashboard',dashboard),('MITRE Tests',browser),('Run Builder',Runner(items,browser)),('Reports',Reports()),('Tools',Tools())]; self.nav=[]
  self.dashboard=dashboard; self.browser=browser; self.runner=pages[2][1]
  browser.run_requested.connect(lambda _ids:self.show_page(2))
  dashboard.open_browser_requested.connect(self.open_tactic_browser)
  for i,(name,page) in enumerate(pages): b=Nav(name); b.clicked.connect(lambda _=False,j=i:self.show_page(j)); sl.addWidget(b); self.nav.append(b); self.stack.addWidget(page)
  sl.addStretch(); foot=QLabel('Detection Validation\nby Jan Fischbach'); foot.setObjectName('sideFooter'); sl.addWidget(foot); l.addWidget(side); l.addWidget(self.stack,1); self.show_page(0)
 def show_page(self,i):
  self.stack.setCurrentIndex(i)
  for j,b in enumerate(self.nav): b.setChecked(i==j)
 def open_tactic_browser(self,tactic):
  self.browser.set_tactic_filter(tactic); self.show_page(1)
STYLE='QWidget{background:#08111d;color:#d8e2f0;font-family:"Segoe UI";font-size:10pt} #sidebar{background:#07101b;border-right:1px solid #18304a} #brand{color:#f000c8;font-size:22pt;font-weight:900;letter-spacing:2px} #version{color:#7dd3fc;font-family:Consolas} #sideFooter{color:#6f8298} Nav{text-align:left;padding-left:14px;border:1px solid transparent;border-radius:7px;color:#9cb0c8;background:transparent} Nav:hover{background:#102039;color:white} Nav:checked{background:#132844;color:white;border-left:3px solid #e600c7} #pageTitle{font-size:22pt;font-weight:800;color:#f8fafc} #sectionTitle{font-size:13pt;font-weight:700;color:#9bd4ff} #card,#tacticCard{background:#0d1b2d;border:1px solid #213b58;border-radius:10px} #cardTitle{color:#7890aa} #cardValue{color:white;font-size:24pt;font-weight:900} #cardSub{color:#6f8298} #tacticName{color:#8ecbff;font-weight:700} #tacticCount{color:#f5f7fa;font-size:20pt;font-weight:900} QLineEdit,QComboBox,QPlainTextEdit,QTableWidget,QListWidget{background:#0b1727;border:1px solid #25415f;border-radius:6px;padding:6px} QHeaderView::section{background:#102139;color:#9ec8ed;border:none;border-right:1px solid #1f3854;padding:8px;font-weight:700} QPushButton{background:#12243b;border:1px solid #2b4b6d;border-radius:6px;padding:8px 14px} QPushButton:hover{background:#193554} #primary{background:#8b0da8;border-color:#d31cda;color:white;font-weight:800} #log{font-family:Consolas;font-size:9pt} #status{color:#38e66b;font-family:Consolas;font-weight:800} QProgressBar::chunk{background:#9b20c7}'
STYLE += ' #executionPanel{background:#07121f;border:1px solid #174a78;border-radius:9px} #execTitle{color:#00b7ff;font-size:11pt;font-weight:800} #pipeline{color:#a7c6df;font-family:Consolas} #currentTechnique{background:#091827;border:1px solid #1d4162;border-radius:7px} #currentId{color:#f000c8;font-family:Consolas;font-weight:800} #overallText{color:#e8edf5;font-family:Consolas;font-weight:800} #metricDone{color:#32d46a;font-weight:800} #metricFailed{color:#ff5c66;font-weight:800} #metricSkipped{color:#f3c94c;font-weight:800} #coverageTable{background:#081522;border:0;gridline-color:#18354f} #recentFailures{background:#100f18;border:1px solid #5d1731;color:#ff7b86} #failTitle{color:#ff5263;font-weight:800} '
STYLE += ' #executionPanel{padding:0} #execTitle{margin:0;padding:0} #pipeline{margin:0;padding:0} #currentTechnique QLabel{padding:0 2px} #overallProgress{border:1px solid #294b68;border-radius:2px;background:#0b1727} #overallProgress::chunk{background:#a21ec9} #coverageTable{font-size:9.5pt} #coverageTable::item{padding:2px 5px} #coverageTable QProgressBar{min-height:12px;max-height:13px;border:1px solid #294b68;border-radius:2px;background:#0b1727} #coverageTable QProgressBar::chunk{background:#a21ec9} '
STYLE += ' #tacticButton{text-align:left;background:#0d1b2d;border:1px solid #213b58;border-radius:10px;padding:9px;color:#8ecbff;font-weight:800;font-size:10.5pt} #tacticButton:hover{background:#132844;border-color:#3b82b8} #tacticButton:checked{background:#17304e;border:2px solid #e600c7;color:#ffffff} #mitreExplorer{background:#091521;border:1px solid #244564;border-radius:9px} #explorerTitle{color:#8ecbff;font-size:12pt;font-weight:800} #mitreExplorerTable{background:#081522;border:1px solid #223f5b;gridline-color:#18354f} #mitreExplorerTable::item:selected{background:#173a5e;color:white} #mitreDetail{background:#0b1727;border:1px solid #294863;border-radius:7px} #detailName{color:#f000c8;font-size:13pt;font-weight:800} #detailMeta{color:#8fb4d6;font-family:Consolas} #detailLabel{color:#62c8ff;font-size:9pt;font-weight:800;margin-top:8px} #detailText{color:#dbe5f1;line-height:1.4} #detailPorts{color:#80e7cb;font-family:Consolas} '
STYLE += ' #detailAction{color:#d8c4ff;background:#091321;border:1px solid #2a405e;border-radius:5px;padding:8px;font-family:Consolas;font-size:9pt} '
def main():
 app=QApplication(sys.argv); app.setApplicationName('PurplePOC'); app.setStyleSheet(STYLE); w=Window(); w.show(); raise SystemExit(app.exec())
if __name__=='__main__':
 try:
  main()
 except Exception:
  import traceback
  from datetime import datetime
  log_dir=ROOT/'logs'
  log_dir.mkdir(parents=True,exist_ok=True)
  crash=log_dir/f"gui-crash-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"
  crash.write_text(traceback.format_exc(),encoding='utf-8',errors='replace')
  print(f"PurplePOC GUI crash log: {crash}",file=sys.stderr)
  raise

'@

Write-File "README.md" @'
# PurplePOC

PurplePOC is a Windows / Active Directory detection-validation orchestrator
for authorized Purple-Team and EDR/XDR/SIEM POC environments.

The project is generated by the PurplePOC builder script. After generation,
the actual runtime files are located in the `PurplePOC` directory.

---

# Validation compatibility fix

PurplePOC 1.6.0 removes the obsolete v1.4.9 unit test that expected Python
ANSI color constants. Those ANSI constants were intentionally removed in
v1.4.10 because Windows PowerShell 5.1 rendered them as raw escape text.

Validation now checks the actual supported design:

- PowerShell owns colorized banners/stage output.
- Python per-test rendering is ASCII-only.
- No ANSI escape sequences or Unicode progress/box characters are permitted
  in `controller.py`.

---

# Validation fix for expandable report

PurplePOC 1.6.0 fixes the expandable-report unit test so it validates the
generated `core/reporting.py` markup rather than the escaped builder-source
representation.

The report functionality itself is unchanged.

---

# Expandable report details and graceful GUIDED stop

PurplePOC 1.6.0 adds expandable detail panels below every test in the HTML
report.

For Atomic tests the detail panel includes:

- exact Atomic GUID;
- exact Atomic test parsed from execution output;
- backend and action metadata;
- notable execution results;
- expected and observed Windows events;
- raw stdout and stderr in nested expandable sections.

GUIDED `quit` no longer raises `KeyboardInterrupt`. It records the current
test as `ABORTED`, ends the scenario normally, then proceeds through cleanup
and report generation.

---

# Polished test result view

PurplePOC 1.6.0 makes individual test results easier to scan.

Each test now renders as a compact card:

```text
==============================================================================
  T-020   T1059.001   Atomic PowerShell Execution
  MODE    : AUTO
------------------------------------------------------------------------------
  RESULT  : COMPLETED
  EXIT    : 0
  TIME    : 19.91s
  EVENTS  : 0 Windows event(s)

  OUTPUT
  ------------------------------------------------------------
    Executing test: T1059.001-17 PowerShell Command Execution
    Hello, from PowerShell!
    Done executing test: T1059.001-17 PowerShell Command Execution
    Executing cleanup for test: T1059.001-17 PowerShell Command Execution
    Done executing cleanup for test: T1059.001-17 PowerShell Command Execution
```

PowerShell CLIXML/progress serialization, `PathToAtomicsFolder` chatter and
other low-value implementation noise are hidden from the console. The raw
stdout/stderr remains available in the evidence files and report.

---

# Windows PowerShell console compatibility

PurplePOC 1.6.0 keeps the colored PowerShell banner and stage UI, but Python
test-result output intentionally uses ASCII-only formatting.

Windows PowerShell 5.1 can display raw ANSI escape sequences such as `[90m`
and can misrender Unicode box-drawing characters depending on the terminal
and code page. The test renderer therefore uses plain separators and labels:

```text
==========================================================================
[T-001] T1033  Account Context  [AUTO]
--------------------------------------------------------------------------
  STATUS    : COMPLETED
  EXIT CODE : 0
  DURATION  : 0.08s
  EVIDENCE  : 0 Windows event(s)

  OUTPUT
  ------
    ...
```

This avoids mojibake while retaining the colored installer/bootstrap/validation
UI implemented in PowerShell.

---

# Console UI

PurplePOC 1.6.0 adds a shared colorized PowerShell interface for setup,
validation and execution.

The scripts now use:

```text
Magenta  - PurplePOC branding / major execution stages
Cyan     - active steps and preflight stages
Green    - PASS / READY / success
Yellow   - warnings and optional components
Red      - failures
DarkGray - separators / secondary structure
```

The UI remains standard PowerShell output and does not require any additional
GUI framework.

---

# Logging and crash recovery

PurplePOC 1.6.0 writes persistent PowerShell transcripts.

Runtime logs:

```text
logs\purplepoc-run-YYYYMMDD-HHMMSS.log
logs\purplepoc-validate-YYYYMMDD-HHMMSS.log
logs\purplepoc-bootstrap-YYYYMMDD-HHMMSS.log
logs\latest.log
```

Unhandled errors additionally create:

```text
logs\crash-run-YYYYMMDD-HHMMSS.log
```

The crash log contains:

```text
timestamp
stage
run ID
host
operator
PowerShell version
last exit code
exception
source position
PowerShell stack trace
full error record
```

When `Start-PurplePOC.ps1` needs administrator privileges, the elevated child
PowerShell is launched with `-NoExit`.

If the POC crashes:

1. the error is written to the crash log;
2. PurplePOC attempts registered cleanup actions;
3. a partial report is attempted when a Run ID exists;
4. the PowerShell window remains open;
5. the operator must press ENTER before the script returns.

To inspect the latest logs:

```powershell
Get-ChildItem .\logs | Sort-Object LastWriteTime -Descending
```

Open the newest log:

```powershell
Get-Content (
    Get-ChildItem .\logs\*.log |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
) -Tail 100
```

---

# MITRE tactic organization and Post-Exploitation Atomic Pack

PurplePOC 1.6 groups the complete test sequence by primary MITRE ATT&CK tactic.

Current groups include:

```text
Discovery
Execution
Persistence
Privilege Escalation
Defense Evasion
Credential Access
Lateral Movement
```

All AUTO and Atomic tests execute before the GUIDED section.

The Post-Exploitation Atomic Pack adds exact GUID-allowlisted tests for:

```text
T1012      Registry Query                       Discovery
T1055.004  APC Process Injection               Privilege Escalation
T1218.010  Regsvr32 local COM scriptlet        Defense Evasion
T1218.008  Odbcconf DLL proxy execution        Defense Evasion
T1112      Registry Modification               Defense Evasion
```

The report stores and displays the primary tactic and inserts tactic section
headers in the technique table.

## Skip all GUIDED tests

From PowerShell:

```powershell
.\Start-PurplePOC.ps1 -SkipGuided
```

Or directly:

```powershell
.\.venv\Scripts\python.exe .\controller.py run --scenario full --skip-guided
```

Inside a GUIDED prompt, use:

```text
skip-all
```

to skip the current and all remaining GUIDED tests while still performing
cleanup and report generation.

## GUIDED tool sources

PurplePOC records the official public source URL for GUIDED tooling and adds
an `open-source` action to the GUIDED menu.

Certipy remains bootstrap-managed.

High-risk credential/domain-compromise binaries remain operator-staged rather
than being automatically downloaded or executed. Their official source link,
expected staging path, status and SHA256 (when present) are shown by
PurplePOC.

---

# Expanded Defense Evasion coverage

PurplePOC 1.0.12 adds AUTO coverage for Windows event-log manipulation and
security-process termination behavior. The process-termination test uses only
a disposable PurplePOC-created process; it never kills Defender or a real EDR
agent. The Phant0m/EventLog-thread-kill Atomic is intentionally excluded
because its documented recovery requires a reboot.

---

# Expanded post-exploitation coverage

PurplePOC 1.0.12 expands the AUTO/Atomic scenario substantially:

- Execution adds MSHTA, Regsvr32, Rundll32, CMSTP and HH.exe proxy/download
  execution coverage.
- Privilege Escalation adds CMSTP UAC bypass and a SYSTEM startup scheduled task.
- Lateral Movement adds ADMIN$ activity, PsExec-to-localhost, WMI loopback
  remote execution and MSHTA UNC lateral-movement simulation.
- GUIDED tests remain disabled by default.

The new remote-content tests use official Atomic Red Team test resources and
the normal Atomic prerequisite/cleanup lifecycle.

---

# Self-test regression fix

PurplePOC 1.0.12 fixes a false-negative smoke test introduced in 1.9.4.
The parser itself was valid, but one regression assertion looked for escaped
newline text rather than the actual generated controller source, which caused
pytest to exit with code 1 during the Self-tests stage.

The smoke test now checks the corrected parser structure directly.

---

# Controller CLI / argparse fix

PurplePOC 1.0.12 fixes scenario startup exiting with code 2 before T-001.

Root cause: `--skip-guided` was accidentally registered on the root argparse
parser instead of the `run` subparser. Rich correctly launches the controller
as `controller.py run ... --skip-guided`, so argparse rejected the option in
that position.

Both `--guided` and `--skip-guided` now belong to the `run` subparser in a
mutually-exclusive group. Normal/full runs keep GUIDED disabled by default;
an explicit `--guided` or `--phase guided` is treated as operator opt-in.

Regression smoke tests now verify the parser ownership and compile
`controller.py` before runtime.

---

# Self-test compatibility fix

PurplePOC 1.0.12 removes stale smoke-test assertions left behind by the
1.9.0/1.9.1 guided-parser patches. Those tests were still expecting the old
`args.guided` source text and could stop startup with pytest exit code 1 even
though the corrected 1.9.2 parser itself was valid.

The smoke test now validates the actual 1.0.12 parser implementation and keeps
the Python syntax compilation check.

---

# GUIDED parser indentation fix

PurplePOC 1.0.12 fixes the generated `rich_app.py` indentation error in the
argument parser. The `--guided` and `--skip-guided` switches are now created
inside a mutually-exclusive argparse group, and the generated Python source
is covered by a syntax-compilation smoke test.

GUIDED remains disabled by default.

---

# GUIDED parser fix

PurplePOC 1.0.12 fixes the Rich UI crash caused by referencing `args.guided`
when the argparse option had not been registered in some generated builds.

`--guided` is now explicitly registered and access is also protected with
`getattr(..., False)`, so GUIDED remains disabled by default without risking
an AttributeError.

---

# GUIDED execution policy

PurplePOC 1.0.12 is unattended by default: AUTO/Atomic tests run normally,
while GUIDED tests are skipped unless the operator explicitly starts the tool
with `--guided`. Guided tool preparation can remain available without causing
the guided procedures themselves to execute.

---

# MITRE ATT&CK progress dashboard

PurplePOC 1.0.12 replaces the large raw-output area in the live Rich UI with a
MITRE ATT&CK execution dashboard.

Each tactic gets its own progress bar and live state. The dashboard also shows
the currently executing technique, overall progress, failed/skipped counters,
and a compact recent-failures panel.

Raw stdout/stderr is still retained in the evidence files and expandable HTML
report; it is simply no longer used as the primary live visualization.

---

# Rich live output and version fix

PurplePOC 1.0.12 fixes the dashboard appearing idle while scenario work was
actually running in the background.

Child Python processes now use unbuffered stdout (`python -u` and
`PYTHONUNBUFFERED=1`), so controller/pytest output reaches the Rich dashboard
immediately.

The dashboard also shows a small `Process running...` heartbeat during quiet
operations and resolves the Run ID as soon as `last_run.txt` becomes
available.

The generated VERSION file and Rich fallback version are synchronized to
1.7.6.

---

# Rich UI flicker fix

PurplePOC 1.0.12 changes the Rich Live renderer for Windows PowerShell/conhost.

The previous UI repainted the entire full-screen layout up to eight times per
second using the alternate screen buffer. On classic Windows PowerShell this
can visibly flicker.

The UI now:

- refreshes only when output changed;
- throttles redraws to 2 Hz;
- disables the alternate screen buffer;
- keeps the rendered dashboard persistent instead of repeatedly swapping
  buffers.

This keeps the dashboard visually stable while still updating quickly enough
for live execution status.

---

# Rich AUTO / GUIDED phase handoff

PurplePOC 1.0.12 fixes the behavior where the Rich UI disappeared as soon as
the scenario started in interactive mode.

The scenario is now split into two phases while retaining a single Run ID:

1. AUTO + Atomic tests run inside the full-screen Rich Live dashboard.
2. Only when the first GUIDED test is reached does PurplePOC hand the terminal
   to the interactive prompt layer.
3. After the GUIDED phase completes or `skip-all` is selected, the Rich UI
   returns for report generation and the final success screen.

`-SkipGuided` remains fully dashboard-driven for the entire run.

---

# Rich UI self-test runtime fix

PurplePOC 1.0.12 fixes the Rich UI abort with exit code `5`.

Pytest uses exit code 5 when no tests are collected. The v1.7.x builder had
stopped generating the `tests` directory while the Rich UI still invoked
pytest as its first validation stage.

The builder now generates and validates `tests\test_smoke.py`, includes it
in package integrity checks, and writes Rich runtime diagnostics to:

```text
logs\rich-ui.log
```

---

# Builder generation boundary fix

PurplePOC 1.0.12 fixes the actual generator bug behind the missing
`Setup-AtomicRedTeam.ps1`.

Two PowerShell here-string closing delimiters had been joined to surrounding
content. Since a PowerShell here-string terminator must be on its own line,
the Atomic setup generator was being swallowed into the preceding generated
file instead of executing as a builder command.

The corrected builder now immediately verifies both setup scripts after
generation and prints their size and SHA256.

A final package manifest is written to:

```text
data\build-integrity.json
```

with READY/MISSING state, size and SHA256 for every required file.

---

# Runtime integrity and version synchronization

PurplePOC 1.0.12 synchronizes the displayed version with the generated
`VERSION` file and validates critical generated files before packaging.

If `Setup-AtomicRedTeam.ps1` is missing at runtime, Bootstrap no longer
terminates with a command-not-found exception. It records `MISSING_SETUP` in
`data/atomic-status.json` and tells the operator to check for incomplete
extraction or AV/EDR quarantine.

PurplePOC intentionally does not recreate a file that a security product may
have removed during a detection-validation engagement.

---

# Rich terminal application

PurplePOC 1.0.12 uses a real Python Rich terminal application for the elevated
runtime instead of trying to reproduce the dashboard with `Write-Host`.

The Rich UI provides a branded header, scenario/host/domain/operator/Run ID
cards, execution pipeline, live scrolling output, system information and
next-step panels.

For the closest full-screen dashboard experience use:

```powershell
.\Start-PurplePOC.ps1 -SkipGuided
```

Interactive GUIDED tests still require direct keyboard input. PurplePOC keeps
the Rich header and context, then temporarily hands the terminal to the
interactive GUIDED prompts before returning to report generation.

---

# Console result renderer

PurplePOC 1.0.12 replaces the old verbose scenario output with a compact
structured renderer.

The elevated console now stays on a black background and each MITRE tactic is
shown as a clear section, followed by compact per-test cards.

Example:

```text
==============================================================================
  DISCOVERY  |  17 TESTS
==============================================================================

  T-001   T1033       Account Context
  MODE      AUTO
  --------------------------------------------------------------------------
  STATUS    COMPLETED    EXIT 0    TIME    0.08s   EVENTS 0

  OUTPUT
  ------------------------------------------------------------
    User        corp\info
    SID         S-1-5-21-...
    Groups
      - BUILTIN\Administrators
      - NT AUTHORITY\Authenticated Users
```

Large command output is summarized in the console. Full stdout/stderr remains
available in the per-test evidence files and the HTML report.

---

# Elevated execution console

PurplePOC 1.0.12 gives the elevated PowerShell child process the same branded
presentation as the installer and bootstrap experience.

The elevated session includes the PurplePOC banner, administrator-ready
state, operator/host/domain/scenario session card, GUIDED-mode badge,
numbered execution stages, run summary and the existing crash/cleanup UI.

The window title is set to `PurplePOC Elevated Execution Console`.

---

# Quick Start

## 1. Build / update PurplePOC

Open PowerShell in the directory that contains the builder file.

Example:

```powershell
cd C:\Users\info\OneDrive\Documents
```

For version 1.3.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\PurplePOC-1.3.1-readme-commands.ps1"
```

The builder creates or updates:

```text
.\PurplePOC\
```

---

# 2. Enter the PurplePOC directory

```powershell
cd .\PurplePOC
```

---

# 3. Allow scripts for the current PowerShell process

This does not change the permanent system-wide Execution Policy.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Check the active policies if required:

```powershell
Get-ExecutionPolicy -List
```

---

# 4. Bootstrap the environment

Bootstrap installs/prepares the Python runtime, venv and PurplePOC
dependencies.

```powershell
.\Bootstrap.ps1
```

If the local Execution Policy blocks direct execution:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Bootstrap.ps1"
```

---

# 5. Prepare GUIDED test tools

Normally Bootstrap already calls this automatically.

To run it manually:

```powershell
.\Setup-GuidedTools.ps1
```

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Setup-GuidedTools.ps1"
```

PurplePOC prepares the expected staging folders and bootstrap-safe
dependencies.

Typical locations:

```text
tools\rubeus\Rubeus.exe
tools\mimikatz\mimikatz.exe
tools\impacket\secretsdump.py
tools\seatbelt\Seatbelt.exe
tools\sharpup\SharpUp.exe
```

Certipy is installed into the PurplePOC Python environment where supported.

---

# 6. Validate PurplePOC

Run the self-tests before starting a POC:

```powershell
.\Validate-PurplePOC.ps1
```

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Validate-PurplePOC.ps1"
```

A healthy validation should end with:

```text
TESTS PASSED
```

---

# 7. Start PurplePOC

Default full scenario:

```powershell
.\Start-PurplePOC.ps1
```

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Start-PurplePOC.ps1"
```

The start script performs:

```text
Bootstrap
-> Self-Test
-> Preflight
-> Scenario execution
-> AUTO tests
-> GUIDED tests
-> Evidence collection
-> Report generation
```

---

# 8. Start a specific scenario

Full:

```powershell
.\Start-PurplePOC.ps1 -Scenario full
```

If additional scenario files are present, use the scenario filename without
`.yaml`.

Example:

```powershell
.\Start-PurplePOC.ps1 -Scenario discovery
```

---

# 9. Atomic Red Team automatic setup

PurplePOC automatically prepares Atomic Red Team during Bootstrap.

Manual setup/reinstall:

```powershell
.\Setup-AtomicRedTeam.ps1
```

Force reinstall/update of the local Atomic definitions:

```powershell
.\Setup-AtomicRedTeam.ps1 -Force
```

Atomic installation uses Red Canary's official
`install-atomicsfolder.ps1` helper and `Install-AtomicsFolder`; it does not
assume `Install-AtomicRedTeam` is exported by the PowerShell module.

PurplePOC installs the official `invoke-atomicredteam` PowerShell module,
`powershell-yaml`, and the Atomic Red Team definitions.

The Atomic definitions are stored under:

```text
tools\atomic-red-team\atomics\
```

PurplePOC executes only exact Atomic Red Team test GUIDs configured under
`config.yaml -> atomic.tests`.

The adapter passes each configured GUID via `-TestGuids`; PurplePOC no longer
runs every Atomic that belongs to the same MITRE technique.

The default AUTO set includes:

```text
T1059.001 PowerShell
T1053.005 Scheduled Task
T1547.001 Registry Run Keys
T1543.003 Windows Service
T1047     WMI
T1057     Process Discovery
T1082     System Information Discovery
```

For each Atomic test PurplePOC can:

```text
validate allowlist
-> obtain Atomic prerequisites
-> execute the allowlisted Atomic
-> collect Windows evidence
-> run Atomic cleanup
-> save stdout/stderr under the T-ID
-> include the result in HTML/JSON/CSV
```

Critical credential/domain-compromise techniques are intentionally not part
of the Atomic AUTO allowlist.

---

# 10. GUIDED test controls

GUIDED tests show an interactive prompt.

Available actions:

```text
help
open-tool
arm
skip
quit
```

## help

Displays:

- purpose of the test
- preparation guidance
- expected Windows / EDR / SIEM telemetry
- tool path
- tool status
- version and SHA256 where available

Enter:

```text
help
```

## open-tool

Opens the expected staging directory for the tool.

Enter:

```text
open-tool
```

The staging folder is opened even when the expected executable is still
missing.

## arm

Starts the test telemetry window.

Enter:

```text
arm
```

Then execute the approved Purple-Team procedure.

After the operator-run test is finished, press ENTER and choose the result:

```text
completed
prevented
failed
aborted
```

## skip

Skips the current GUIDED test:

```text
skip
```

## quit

Stops the current run:

```text
quit
```

---

# 10. Build the distributable ZIP

From inside the generated `PurplePOC` directory:

```powershell
.\Build-PurplePOC.ps1
```

Or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Build-PurplePOC.ps1"
```

The ZIP is written to:

```text
..\dist\PurplePOC-<VERSION>.zip
```

---

# 11. Console command output

PurplePOC prints the actual result returned by AUTO/Atomic commands directly
below the execution status.

Example:

```text
[T-002] T1082 System Information Discovery (AUTO)
        Result: COMPLETED
        Output:
          Host Name:                 CLAUDE
          OS Name:                   Microsoft Windows 11 Pro
          OS Version:                10.0.x
          System Type:               x64-based PC
        Exit Code: 0
        Duration: 6.19s
        Evidence: 2 Windows event(s)
```

The preview size can be changed in `config.yaml`:

```yaml
console:
  show_command_output: true
  output_preview_max_lines: 20
  output_preview_max_chars: 4000
  error_preview_max_lines: 10
  error_preview_max_chars: 2000
```

Long output is truncated only in the console. The full stdout/stderr remains
stored under the test evidence directory, for example:

```text
reports\<RUN-ID>\evidence\T-002\stdout.txt
reports\<RUN-ID>\evidence\T-002\stderr.txt
```

---

# 12. Cleanup behavior

PurplePOC 1.4.4 keeps a persistent cleanup registry during each run.

For tests that create temporary state, the cleanup action is registered
before the change is made. This allows PurplePOC to retry cleanup at the end
of the run even if the normal per-test cleanup failed.

Covered AUTO changes include:

```text
Scheduled Tasks
Registry Run values
Temporary Windows Services
Allowlisted Atomic Red Team cleanup actions
```

The runtime/framework itself is retained by default:

```text
Python venv
Atomic Red Team definitions
Invoke-AtomicRedTeam module
PurplePOC files
```

At the end of a run the console shows:

```text
Final cleanup verification

Total:   4
Clean:   4
Pending: 0
Failed:  0
```

The report directory also contains:

```text
cleanup-report.json
```

Cleanup configuration:

```yaml
cleanup:
  enabled: true
  retry_pending_at_end: true
  retain_framework: true
  write_summary: true
```

If a process is interrupted, rerunning the scenario or calling the cleanup
logic during the next normal run can retry entries left in the persistent
cleanup registry.

---

# 13. Reports

After a successful run, reports are generated directly below the project:

```text
PurplePOC\reports\<RUN-ID>\
```

Important files:

```text
report.html
report.json
techniques.csv
events.csv
evidence\
```

Each test has a human-readable Test ID:

```text
T-001
T-002
T-003
...
```

Per-test evidence is grouped under:

```text
reports\<RUN-ID>\evidence\T-001\
```

Possible files include:

```text
metadata.json
stdout.txt
stderr.txt
```

---

# 12. Typical complete workflow

From the directory that contains the builder:

```powershell
cd C:\Users\info\OneDrive\Documents
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\PurplePOC-1.3.1-readme-commands.ps1"
cd .\PurplePOC
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Validate-PurplePOC.ps1
.\Start-PurplePOC.ps1
```

---

# 13. If scripts are blocked

Error example:

```text
running scripts is disabled on this system
```

Use:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then retry the command.

Alternatively start a script explicitly with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\SCRIPT.ps1"
```

Example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Start-PurplePOC.ps1"
```

---

# 14. If a file cannot be found

Check the current working directory:

```powershell
Get-Location
```

List files:

```powershell
Get-ChildItem
```

Move one directory up:

```powershell
cd ..
```

Move into PurplePOC:

```powershell
cd .\PurplePOC
```

Check whether a script exists:

```powershell
Test-Path .\Start-PurplePOC.ps1
```

---

# 15. Check Python / venv

PurplePOC uses its own Python environment.

Check Python:

```powershell
python --version
```

Check the PurplePOC runtime:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\python.exe" --version
```

Check pip:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\python.exe" -m pip --version
```

---

# 16. Certipy troubleshooting

If Certipy installation failed during Bootstrap, first update the Python
packaging components:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\python.exe" -m pip install --upgrade pip setuptools wheel
```

Retry Certipy:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\python.exe" -m pip install --no-cache-dir certipy-ad
```

Check whether Certipy is available:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\certipy.exe" --version
```

If the executable does not exist, check the package:

```powershell
& "$env:LOCALAPPDATA\PurplePOC\.venv\Scripts\python.exe" -m pip show certipy-ad
```

---

# 17. Useful diagnostic commands

Current host:

```powershell
hostname
```

Current identity:

```powershell
whoami
```

Domain information:

```powershell
$env:USERDNSDOMAIN
```

Domain controller discovery:

```powershell
nltest /dsgetdc:$env:USERDNSDOMAIN
```

Process-creation audit configuration:

```powershell
auditpol /get /subcategory:"Process Creation"
```

PowerShell Operational log:

```powershell
Get-WinEvent -ListLog "Microsoft-Windows-PowerShell/Operational"
```

Sysmon log availability:

```powershell
Get-WinEvent -ListLog "Microsoft-Windows-Sysmon/Operational" -ErrorAction SilentlyContinue
```

---

# 18. Main files

```text
Start-PurplePOC.ps1
Bootstrap.ps1
Setup-GuidedTools.ps1
Validate-PurplePOC.ps1
Build-PurplePOC.ps1
controller.py
config.yaml
```

---

# 19. Test modes

## AUTO

PurplePOC executes the allowlisted validation step automatically.

## GUIDED

PurplePOC prepares the test, shows guidance, records tool metadata, arms the
telemetry window and waits for the Purple-Team operator to perform the
approved test.

## MANUAL

Reserved for tests that only need PurplePOC evidence/timing/reporting around
an operator-controlled action.

---

# 20. Important

PurplePOC should be used only in authorized security test environments.

GUIDED critical tests remain operator-controlled. PurplePOC provides the
workflow, evidence collection, test IDs and reporting around those tests.

## PurplePOC Desktop GUI

Launch with `./Start-PurplePOC-GUI.ps1`. The existing Rich/CLI frontend remains available via `Start-PurplePOC.ps1`. Both use the same controller, scenarios, evidence and reporting backend.


## PurplePOC 1.0 GUI run workflow

You can start tests in two ways:

1. Open **MITRE Tests**, select one or more checkboxes and click **Run selected**.
2. Open **Run Builder**, optionally choose tactic/technique/phase, then click **Run validation**.

If no individual tests or filters are selected, the GUI asks before starting the full scenario.
The live output panel shows the exact controller command and any start/runtime error.


## Upgrade-safe runtime (v1.0.12)

PurplePOC upgrades are now **upgrade-safe**. Re-running a newer builder in the
same directory preserves `.venv`, `data`, `reports`, `logs`, and downloaded
`tools` content instead of deleting the Python/Qt runtime on every upgrade.

Bootstrap also searches the project venv, persisted runtime path, shared
`%LOCALAPPDATA%\PurplePOC\.venv`, the current system Python, and local Python
installations before trying to download packages again.


## PowerShell execution policy

If script execution is blocked, launch the builder with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\PurplePOC-1.0.12-execution-bypass-header.ps1
```

Alternatively, for the current PowerShell process only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```


## Run Builder layout (v1.0.12)

The live execution area is more compact. The MITRE tactic table receives more
vertical space and dynamically sizes itself to the active tactics so the normal
eight-tactic full AUTO run is visible without an internal scrollbar.


## Analyst cookbook (v1.0.12)

Every test report now includes a practical analyst cookbook:
- exact or relevant protocols and ports,
- correlation window,
- numbered SIEM build/validation steps,
- minimum normalized fields,
- evidence to attach to the offense,
- false-positive checks.

Examples include LDAP 389/636 + Global Catalog 3268/3269, SMB 445/139,
Kerberos 88/464, DNS 53/853/DoH 443, WMI/RPC 135 + dynamic RPC
49152-65535, WinRM 5985/5986, and HTTP(S) 80/443 where applicable.


## Interactive MITRE dashboard (v1.0.12)

The dashboard MITRE tactic cards are clickable. Selecting a tactic opens an
inline test explorer showing the tactic's tests, MITRE technique, AUTO/GUIDED
mode, description, purpose and protocol/port context. The **Open in MITRE Tests**
button jumps to the full Test Browser with the selected tactic already filtered.


## GUI launcher console (v1.0.12)

`Start-PurplePOC-GUI.ps1` now uses the same PurplePOC console branding as the
CLI launcher. The launcher sets the entire PowerShell console buffer to black,
uses white default text, displays the magenta PurplePOC ASCII header, and keeps
`by Jan Fischbach | version | August 2026` in the standard banner.

This is applied again in the elevated child process, so UAC relaunches no
longer fall back to the classic blue Windows PowerShell background.


## Proxy parameter (v1.0.12)

Use `-Proxy` when PurplePOC must reach PyPI, PowerShell Gallery or GitHub
through an HTTP/HTTPS proxy.

```powershell
.\PurplePOC-1.0.12-proxy-support.ps1 -Proxy http://proxy.company.local:8080
```

```powershell
.\Start-PurplePOC-GUI.ps1 -Proxy http://proxy.company.local:8080
```

```powershell
.\Start-PurplePOC.ps1 -Technique T1048 -Proxy http://proxy.company.local:8080
```

An explicitly supplied builder proxy is stored in `data\proxy.txt` and reused
by later GUI/CLI/bootstrap runs. `-Proxy` always overrides the stored value.

Proxy-aware components:
- pip/PyPI (`--proxy` plus `HTTP_PROXY`, `HTTPS_PROXY`, `PIP_PROXY`)
- NuGet provider / PowerShell Gallery module installation
- Atomic Red Team installer download from GitHub
- Certipy installation

When a proxy is configured, local DNS failure for the remote package host is
not treated as a hard offline condition because the proxy may resolve the
destination name.

Avoid putting credentials in the proxy URL when possible because the proxy
value can be visible to local process/configuration inspection.

'@
# --------------------------------------------------------------------
# Package
# --------------------------------------------------------------------

$BuildManifestPath = Join-Path $Root "data\build-integrity.json"
$BuildManifestDir = Split-Path $BuildManifestPath -Parent
New-Item -ItemType Directory -Path $BuildManifestDir -Force | Out-Null

$BuildManifest = @()

$RequiredFiles = @(
    "VERSION",
    "UI.ps1",
    "Bootstrap.ps1",
    "Start-PurplePOC.ps1",
    "Setup-AtomicRedTeam.ps1",
    "Setup-GuidedTools.ps1",
    "controller.py",
    "rich_app.py",
    "tests\test_smoke.py",
    "requirements.txt",
    "config.yaml"
)

$MissingFiles = @()

foreach ($RequiredFile in $RequiredFiles) {
    $Candidate = Join-Path $Root $RequiredFile

    if (-not (Test-Path $Candidate -PathType Leaf)) {
        $MissingFiles += $RequiredFile

        $BuildManifest += @{
            file = $RequiredFile
            state = "MISSING"
            size = 0
            sha256 = $null
        }

        continue
    }

    $Item = Get-Item $Candidate
    $Hash = Get-FileHash -Path $Candidate -Algorithm SHA256

    $BuildManifest += @{
        file = $RequiredFile
        state = "READY"
        size = $Item.Length
        sha256 = $Hash.Hash
    }
}

$BuildManifest |
    ConvertTo-Json -Depth 4 |
    Set-Content `
        -Path $BuildManifestPath `
        -Encoding UTF8

if ($MissingFiles.Count -gt 0) {
    Write-Host "[FAIL] " -NoNewline -ForegroundColor Red
    Write-Host "Generated package is incomplete." -ForegroundColor Red

    foreach ($MissingFile in $MissingFiles) {
        Write-Host ("       Missing: " + $MissingFile) -ForegroundColor Red
    }

    throw "PurplePOC build integrity validation failed."
}

Write-Host "[PASS] " -NoNewline -ForegroundColor Green
Write-Host "Build integrity validation passed" -ForegroundColor White
Write-Host ("       Manifest: {0}" -f $BuildManifestPath) -ForegroundColor DarkGray

Write-Host "[+] " -NoNewline -ForegroundColor Cyan
Write-Host "Packaging $ProjectName $Version" -ForegroundColor White

$PackageStage = Join-Path $Base (".purplepoc-package-" + $Version)

if (Test-Path $PackageStage) {
    Remove-Item $PackageStage -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $PackageStage -Force | Out-Null

$PackageExclude = @(
    ".venv",
    "reports",
    "logs"
)

foreach ($Item in Get-ChildItem -LiteralPath $Root -Force) {
    if ($PackageExclude -contains $Item.Name) {
        continue
    }

    if ($Item.Name -eq "tools" -and $Item.PSIsContainer) {
        $ToolsTarget = Join-Path $PackageStage "tools"
        New-Item -ItemType Directory -Path $ToolsTarget -Force | Out-Null

        Get-ChildItem -LiteralPath $Item.FullName -Force |
            Where-Object { $_.Name -ne "atomic-red-team" } |
            Copy-Item -Destination $ToolsTarget -Recurse -Force

        continue
    }

    Copy-Item `
        -LiteralPath $Item.FullName `
        -Destination $PackageStage `
        -Recurse `
        -Force
}

Compress-Archive `
    -Path (Join-Path $PackageStage '*') `
    -DestinationPath $Zip `
    -Force

Remove-Item $PackageStage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host ("=" * 68) -ForegroundColor DarkGray
Write-Host "  Build complete" -ForegroundColor Green
Write-Host ("=" * 68) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Project : " -NoNewline -ForegroundColor DarkCyan
Write-Host $Root -ForegroundColor Gray
Write-Host "  Archive : " -NoNewline -ForegroundColor DarkCyan
Write-Host $Zip -ForegroundColor Gray
Write-Host ""
