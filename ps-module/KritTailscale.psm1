<#
  KritTailscale.psm1 — pause/resume Tailscale around git pushes.
  Tailscale MITMs the HTTPS git protocol on this box -> 'fatal: protocol error: bad line length'.
  Dropping Tailscale for the push (then restoring) is one reliable fix; SSH-remote is the other.

  Functions:
    Get-KritTailscaleState              -> @{ Running; Connected; Exe }
    Suspend-KritTailscale [-Kill]       -> `tailscale down` (or -Kill = stop the service). Idempotent.
    Resume-KritTailscale                -> `tailscale up` (or restart service). Idempotent.
    Invoke-KritTailscaleDown -Script {} -> down, run block, ALWAYS restore (finally).

  NOTE: dropping Tailscale disconnects your tailnet (remote access to golem etc.) for the duration.
  Examples:
    Invoke-KritTailscaleDown { git -C $repo push origin HEAD }
    Suspend-KritTailscale; git push; Resume-KritTailscale
#>
function Get-KritTailscaleExe {
  $c = @("$env:ProgramFiles\Tailscale\tailscale.exe","${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")
  foreach ($p in $c) { if (Test-Path $p) { return $p } }
  return (Get-Command tailscale -EA SilentlyContinue).Source
}
function Get-KritTailscaleState {
  $exe = Get-KritTailscaleExe
  $connected = $false
  if ($exe) { try { $connected = ((& $exe status 2>$null) -notmatch 'Tailscale is stopped') } catch {} }
  [pscustomobject]@{ Running = [bool](Get-Service Tailscale -EA SilentlyContinue | Where-Object Status -eq 'Running'); Connected = $connected; Exe = $exe }
}
function Suspend-KritTailscale {
  [CmdletBinding()] param([switch]$Kill)
  $exe = Get-KritTailscaleExe; if (-not $exe) { Write-Warning 'tailscale not found'; return }
  if ($Kill) { Stop-Service Tailscale -Force -EA SilentlyContinue }
  else       { & $exe down 2>$null }
  Start-Sleep -Milliseconds 800
  return (Get-KritTailscaleState)
}
function Resume-KritTailscale {
  [CmdletBinding()] param()
  $exe = Get-KritTailscaleExe; if (-not $exe) { return }
  if (-not (Get-Service Tailscale -EA SilentlyContinue | Where-Object Status -eq 'Running')) { Start-Service Tailscale -EA SilentlyContinue; Start-Sleep 1 }
  & $exe up 2>$null
  return (Get-KritTailscaleState)
}
function Invoke-KritTailscaleDown {
  [CmdletBinding()] param([Parameter(Mandatory)][scriptblock]$Script,[switch]$Kill)
  $wasConnected = (Get-KritTailscaleState).Connected
  try {
    if ($wasConnected) { Suspend-KritTailscale -Kill:$Kill | Out-Null; Write-Verbose 'Tailscale down' }
    return & $Script
  } finally {
    if ($wasConnected) { Resume-KritTailscale | Out-Null; Write-Verbose 'Tailscale restored' }
  }
}
Export-ModuleMember -Function Get-KritTailscaleState,Suspend-KritTailscale,Resume-KritTailscale,Invoke-KritTailscaleDown
