<#
.SYNOPSIS
  Remote-provision the Kritical SCX Code store (KriticalSCXCodeStore) on a domain
  machine over WinRM, by wrapping the existing LOCAL installer
  (install\Install-KriticalSCXStore.ps1) inside Invoke-Command.

.DESCRIPTION
  RECOVERED FROM TRANSCRIPT — this exact command sequence was typed out in chat
  and never previously saved to disk as a real script. Reconstructed verbatim
  (commands only lightly generalised from a hardcoded 'golem' to a -ComputerName
  parameter, default 'golem') from Claude Code session transcript:
    C:\Users\joshl\.claude\projects\C--\0f744f2d-440f-4796-9ee1-8270f660256a.jsonl
  (session date 2026-07-04, "Kritical SCX mega-context store" build).

  GROUND TRUTH FROM THAT SESSION (do not assume more than this):
    - golem (192.168.1.250) answered ping + Test-WSMan: WinRM was reachable.
    - A READ-ONLY probe (Invoke-Command -ComputerName golem, checking the
      registry for a named SQL instance + whether sqlcmd exists) was attempted.
      It FAILED with Kerberos error 0x8009030e ("A specified logon session does
      not exist") because the assistant's shell was non-interactive and had no
      golem/domain logon session.
    - The actual remote INSTALL was never attempted at all in that session — the
      assistant only typed the command out for the operator to run themselves,
      with their own credential:
          $c = Get-Credential
          Invoke-Command -ComputerName golem -Credential $c `
            -FilePath "...\Kritical.SCXCode\install\Install-KriticalSCXStore.ps1" `
            -ArgumentList '-Mode','Install','-Apply','-Server','golem\KriticalSCXCode'
    - That same session's own gap ledger recorded this as outstanding:
        "WinRM E2E install test on Golem (192.168.1.250) — NOT run"

  THIS SCRIPT DOES NOT CHANGE THAT FACT. -Mode Probe (the reachability + SQL
  instance discovery check) is the only mode that was ever actually executed,
  and it failed on credentials. -Mode Install/Status/Repair/Uninstall are the
  literal remote-invocation pattern from the transcript, generalised into a
  reusable HR16 wrapper, but have NEVER been run end-to-end against golem by
  any agent. Treat them as unverified until an operator with a real golem/
  domain credential runs -Mode Probe successfully, then -Mode Install -Apply,
  and confirms with -Mode Status.

  All actual install/schema logic lives in the sibling script
  install\Install-KriticalSCXStore.ps1 (already real, committed, HR16-compliant,
  dry-run by default). This wrapper only adds the WinRM transport + the
  golem-specific reachability/discovery probe — it does not reimplement or
  guess at SQL Server installation steps.

.PARAMETER Mode
  Probe     - ping + Test-WSMan $ComputerName, then (if reachable) look for an
              existing named SQL instance + sqlcmd on $ComputerName. Read-only.
              This is the only mode that was ever actually run in the source
              session (and it failed on credentials, not on WinRM reachability).
  Status | Install | Repair | Uninstall
            - Invoke-Command's the LOCAL Install-KriticalSCXStore.ps1 onto
              $ComputerName with the same -Mode (dry-run unless -Apply, exactly
              like the local script). Requires -Credential. NEVER RUN in the
              source session or since — unverified end-to-end.

.PARAMETER ComputerName   Target machine. Default 'golem' (192.168.1.250 in this estate).
.PARAMETER Credential     PSCredential for the remote machine. Prompted via
                          Get-Credential if not supplied and the mode needs one
                          (exactly as the assistant told the operator to do in
                          the source session).
.PARAMETER Server         Remote SQL instance name passed through to the
                          installer. Default "$ComputerName\KriticalSCXCode"
                          (the literal value used in the source session).
.PARAMETER InstallerPath  Local path to Install-KriticalSCXStore.ps1 to ship
                          over WinRM. Default: sibling file in this same
                          install\ folder.
.PARAMETER Apply          Actually execute Install/Repair/Uninstall remotely.
                          Without it, the remote installer dry-runs (prints the
                          T-SQL / DROP statement, changes nothing) exactly like
                          running it locally without -Apply.

.EXAMPLE  pwsh Invoke-KritScxRemoteStoreProvision.ps1 -Mode Probe
.EXAMPLE  $c = Get-Credential
          pwsh Invoke-KritScxRemoteStoreProvision.ps1 -Mode Install -Credential $c            # dry-run
.EXAMPLE  pwsh Invoke-KritScxRemoteStoreProvision.ps1 -Mode Install -Credential $c -Apply      # create the DB + schema on golem
.EXAMPLE  pwsh Invoke-KritScxRemoteStoreProvision.ps1 -Mode Status -Credential $c
#>
[CmdletBinding()]
param(
  [ValidateSet('Probe', 'Status', 'Install', 'Repair', 'Uninstall')]
  [string]$Mode = 'Probe',
  [string]$ComputerName = 'golem',
  [System.Management.Automation.PSCredential]$Credential,
  [string]$Server,
  [string]$InstallerPath = (Join-Path $PSScriptRoot 'Install-KriticalSCXStore.ps1'),
  [switch]$Apply
)
$ErrorActionPreference = 'Continue'
if (-not $Server) { $Server = "$ComputerName\KriticalSCXCode" }

function Test-KritScxRemoteReachability {
  param([Parameter(Mandatory)][string]$ComputerName)
  # Verbatim pattern from the source session's reachability check.
  $pingOk = $false
  try { $pingOk = [bool](Test-Connection $ComputerName -Count 1 -Quiet 2>$null) } catch { $pingOk = $false }
  Write-Host "  ping ${ComputerName}: $pingOk"
  try {
    Test-WSMan $ComputerName -ErrorAction Stop | Out-Null
    Write-Host "  WinRM ${ComputerName}: UP" -ForegroundColor Green
    return $true
  } catch {
    $msg = $_.Exception.Message.Split([char]10)[0]
    Write-Host "  WinRM ${ComputerName}: $msg" -ForegroundColor Red
    return $false
  }
}

Write-Host "=== Kritical SCX remote store provision ($Mode) @ $ComputerName ===" -ForegroundColor Cyan

switch ($Mode) {

  'Probe' {
    Write-Host "`n--- reachability (WinRM + ping) ---"
    $up = Test-KritScxRemoteReachability -ComputerName $ComputerName
    if (-not $up) {
      Write-Host "`nNot reachable over WinRM. Stopping (nothing else was attempted)." -ForegroundColor Yellow
      return
    }

    Write-Host "`n--- ${ComputerName}: SQL instances + sqlcmd (via WinRM) ---"
    # Verbatim pattern from the source session's SQL-instance discovery check.
    $icmParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
    if ($Credential) { $icmParams.Credential = $Credential }
    try {
      Invoke-Command @icmParams -ScriptBlock {
        try {
          (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction Stop).PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { "inst: $($_.Name)" }
        } catch {
          "no SQL instance on $using:ComputerName"
        }
        "sqlcmd: " + [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue)
      }
    } catch {
      # This is the exact failure mode hit in the source session: Kerberos
      # 0x8009030e ("a specified logon session does not exist") when run from
      # a non-interactive context with no logon session for $ComputerName.
      # Re-run from an interactive session, or pass -Credential (Get-Credential
      # first) for a real domain/local admin on $ComputerName.
      Write-Host "  Invoke-Command failed: $($_.Exception.Message)" -ForegroundColor Red
    }
  }

  { $_ -in 'Status', 'Install', 'Repair', 'Uninstall' } {
    if (-not (Test-Path $InstallerPath)) { throw "Installer not found: $InstallerPath" }
    if (-not $Credential -and $Mode -ne 'Status') {
      Write-Host "No -Credential supplied; prompting (your $ComputerName / domain admin)..." -ForegroundColor Yellow
      $Credential = Get-Credential -Message "Credential for $ComputerName (Kritical SCX remote store provision)"
    }

    $remoteArgs = @('-Mode', $Mode, '-Server', $Server)
    if ($Apply) { $remoteArgs += '-Apply' }

    Write-Host "`n--- Invoke-Command -ComputerName $ComputerName -FilePath $InstallerPath -ArgumentList $($remoteArgs -join ' ') ---"
    if ($Mode -ne 'Status' -and -not $Apply) {
      Write-Host "[DRY RUN pass-through] the remote Install-KriticalSCXStore.ps1 dry-runs by default too — re-run with -Apply on THIS wrapper to actually execute." -ForegroundColor Magenta
    }

    $icmParams = @{ ComputerName = $ComputerName; FilePath = $InstallerPath; ArgumentList = $remoteArgs }
    if ($Credential) { $icmParams.Credential = $Credential }
    Invoke-Command @icmParams
  }
}
