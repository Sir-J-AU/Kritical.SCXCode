<#
.SYNOPSIS
  Enable / disable MCP servers in the Codex config.toml — additive, backed-up, reversible.
  Sets `enabled = true|false` inside a named [mcp_servers.X] section (adds the line if missing).
  DRY-RUN by default. HR29: never removes a server, never touches non-MCP config.

.PARAMETER Mode      Status | Enable | Disable   (default Status)
.PARAMETER Servers   comma/space list of server names (e.g. bc_al,shopify-dev-mcp)
.PARAMETER Apply     actually write (otherwise dry-run)
.PARAMETER Config    codex config path (default ~/.codex/config.toml)
.EXAMPLE  pwsh Set-KritMcp.ps1 -Mode Status
.EXAMPLE  pwsh Set-KritMcp.ps1 -Mode Disable -Servers falcon-mcp -Apply
#>
[CmdletBinding()]
param([ValidateSet('Status','Enable','Disable')][string]$Mode='Status',
      [string[]]$Servers=@(), [switch]$Apply,
      [string]$Config="$env:USERPROFILE\.codex\config.toml")
$ErrorActionPreference='Stop'
if (-not (Test-Path $Config)) { throw "codex config not found: $Config" }
$lines = Get-Content $Config
# map: section name -> line index of its header
$sections = @{}
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^\s*\[mcp_servers\.([^\]]+)\]') { $sections[$Matches[1]] = $i }
}
function Get-Enabled($name) {
  $start = $sections[$name]; if ($null -eq $start) { return $null }
  for ($j=$start+1; $j -lt $lines.Count -and $lines[$j] -notmatch '^\s*\['; $j++) {
    if ($lines[$j] -match '^\s*enabled\s*=\s*(true|false)') { return [bool]($Matches[1] -eq 'true') }
  }
  return $true  # codex default when unspecified
}

if ($Mode -eq 'Status') {
  Write-Host "`n=== MCP servers in $Config ===" -ForegroundColor Cyan
  foreach ($n in ($sections.Keys | Sort-Object)) { $e = Get-Enabled $n; Write-Host ("  {0} {1}" -f $(if($e){'[on] '}else{'[off]'}), $n) -ForegroundColor $(if($e){'Green'}else{'DarkGray'}) }
  return
}

$want = if ($Mode -eq 'Enable') { 'true' } else { 'false' }
$targets = @($Servers | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ })
$changed = @()
foreach ($name in $targets) {
  $start = $sections[$name]
  if ($null -eq $start) { Write-Host "  ? unknown MCP server: $name (have: $($sections.Keys -join ', '))" -ForegroundColor Yellow; continue }
  # find enabled line within section
  $enIdx = $null
  for ($j=$start+1; $j -lt $lines.Count -and $lines[$j] -notmatch '^\s*\['; $j++) { if ($lines[$j] -match '^\s*enabled\s*=') { $enIdx=$j; break } }
  if ($enIdx) { if ($lines[$enIdx] -notmatch "=\s*$want") { $changed += "${name}: enabled -> $want (line $($enIdx+1))"; $lines[$enIdx] = "enabled = $want" } }
  else { $changed += "${name}: add 'enabled = $want' after header"; $lines = $lines[0..$start] + "enabled = $want" + $lines[($start+1)..($lines.Count-1)] }
}
if (-not $changed) { Write-Host "No changes needed." -ForegroundColor Green; return }
Write-Host "Changes:" -ForegroundColor Cyan; $changed | ForEach-Object { "  - $_" }
if (-not $Apply) { Write-Host "`n[DRY RUN] add -Apply to write." -ForegroundColor Magenta; return }
$bk = "$Config.bak-$(Get-Random)"
Copy-Item $Config $bk
$lines | Set-Content $Config -Encoding utf8
Write-Host "`nApplied. Backup: $bk" -ForegroundColor Green
Write-Host "Revert: Copy-Item '$bk' '$Config' -Force" -ForegroundColor Yellow
