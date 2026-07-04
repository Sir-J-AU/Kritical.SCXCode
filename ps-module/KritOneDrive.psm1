<#
  KritOneDrive.psm1 — pause/resume OneDrive around OneDrive-locked operations (HR22).
  Repos live under OneDrive; sync locks break git/gh pushes + pnpm installs. Pause first, resume after.

  Functions:
    Get-KritOneDriveState                 -> @{ Running; Pids; Exe }
    Suspend-KritOneDrive [-Force]         -> stop OneDrive (graceful; -Force = kill). Idempotent.
    Resume-KritOneDrive                   -> start OneDrive if not running. Idempotent.
    Invoke-KritOneDriveSafe -Script {...} -> pause, run block, ALWAYS resume (finally). The one to use.

  Examples:
    Suspend-KritOneDrive; git push origin HEAD; Resume-KritOneDrive
    Invoke-KritOneDriveSafe { git -C $repo push origin HEAD }      # auto pause+resume
    Invoke-KritOneDriveSafe -KeepPausedOnError { ... }             # leave paused if block throws (debug)
#>

function Get-KritOneDriveExe {
  $c = @(
    "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe",
    "$env:PROGRAMFILES\Microsoft OneDrive\OneDrive.exe",
    "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"
  )
  foreach ($p in $c) { if (Test-Path $p) { return $p } }
  return $null
}

function Get-KritOneDriveState {
  $p = @(Get-Process OneDrive -ErrorAction SilentlyContinue)
  [pscustomobject]@{ Running = [bool]$p.Count; Pids = @($p.Id); Exe = (Get-KritOneDriveExe) }
}

function Suspend-KritOneDrive {
  [CmdletBinding()] param([switch]$Force, [int]$GraceSec = 5)
  $s = Get-KritOneDriveState
  if (-not $s.Running) { Write-Verbose 'OneDrive already stopped'; return $s }
  Write-Verbose "Stopping OneDrive (pids $($s.Pids -join ','))"
  # graceful shutdown first
  & (Get-KritOneDriveExe) /shutdown 2>$null
  $deadline = (Get-Date).AddSeconds($GraceSec)
  while ((Get-Process OneDrive -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  if (Get-Process OneDrive -ErrorAction SilentlyContinue) {
    if ($Force) { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue }
    else        { Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue }  # HR22: force-kill permitted
  }
  return (Get-KritOneDriveState)
}

function Resume-KritOneDrive {
  [CmdletBinding()] param()
  if ((Get-KritOneDriveState).Running) { Write-Verbose 'OneDrive already running'; return (Get-KritOneDriveState) }
  $exe = Get-KritOneDriveExe
  if ($exe) { Start-Process $exe -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
  else { Write-Warning 'OneDrive.exe not found — cannot resume' }
  return (Get-KritOneDriveState)
}

function Invoke-KritOneDriveSafe {
  [CmdletBinding()] param(
    [Parameter(Mandatory)][scriptblock]$Script,
    [switch]$Force,
    [switch]$KeepPausedOnError
  )
  $wasRunning = (Get-KritOneDriveState).Running
  $threw = $false
  try {
    if ($wasRunning) { Suspend-KritOneDrive -Force:$Force | Out-Null; Write-Verbose 'OneDrive paused' }
    return & $Script
  } catch { $threw = $true; throw }
  finally {
    if ($wasRunning -and -not ($threw -and $KeepPausedOnError)) {
      Resume-KritOneDrive | Out-Null; Write-Verbose 'OneDrive resumed'
    }
  }
}

Export-ModuleMember -Function Get-KritOneDriveState,Suspend-KritOneDrive,Resume-KritOneDrive,Invoke-KritOneDriveSafe
