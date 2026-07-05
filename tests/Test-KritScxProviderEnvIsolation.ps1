<#
.SYNOPSIS
  Guardrail: Kritical.SCXCode installers must never touch native Anthropic/OpenAI settings.

.DESCRIPTION
  Static regression test. It intentionally does not read the operator's current ANTHROPIC_* or
  OPENAI_* values. It scans SCX installer/wrapper scripts for writes/removals/status leaks that
  would mutate or print native provider configuration by default.
#>
[CmdletBinding()]
param([string]$RepoRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$fail = 0
$pass = 0
function T([string]$Name, [scriptblock]$Check) {
  try {
    if (& $Check) { Write-Host "  PASS  $Name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:fail++ }
  } catch {
    Write-Host "  FAIL  $Name ($($_.Exception.Message))" -ForegroundColor Red
    $script:fail++
  }
}

Write-Host "`n===== Kritical SCX Provider Env Isolation =====" -ForegroundColor Cyan
$paths = @(
  (Join-Path $RepoRoot 'install'),
  (Join-Path $RepoRoot 'codex-wrapper'),
  (Join-Path $RepoRoot 'ps-module'),
  (Join-Path $RepoRoot 'node-agent\src'),
  (Join-Path $RepoRoot 'litellm'),
  (Join-Path $RepoRoot 'mcp-server'),
  (Join-Path $RepoRoot 'safety')
) | Where-Object { Test-Path -LiteralPath $_ }

$files = Get-ChildItem -LiteralPath $paths -Recurse -Include *.ps1,*.psm1,*.mjs,*.js -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\node_modules\\|\\__pycache__\\' }

$badMutations = New-Object System.Collections.Generic.List[string]
$badStatusLeaks = New-Object System.Collections.Generic.List[string]
foreach ($file in $files) {
  $text = Get-Content -Raw -LiteralPath $file.FullName
  $relative = $file.FullName.Substring($RepoRoot.Length).TrimStart('\')
  if ($text -match "SetEnvironmentVariable\(\s*['""](?:ANTHROPIC|OPENAI)_" -or
      $text -match "Remove-HkcuVar\s+['""](?:ANTHROPIC|OPENAI)_" -or
      $text -match "Set-HkcuVar\s+['""](?:ANTHROPIC|OPENAI)_" -or
      $text -match "\`$env:(?:ANTHROPIC|OPENAI)_\w+\s*=" -or
      $text -match "process\.env\.(?:ANTHROPIC|OPENAI)_\w+\s*=") {
    $badMutations.Add($relative) | Out-Null
  }
  if ($relative -match '^(install|litellm|safety|mcp-server|codex-wrapper|ps-module)\\' -and
      ($text -match "GetEnvironmentVariable\(\s*['""](?:ANTHROPIC|OPENAI)_" -or
       $text -match "\`$env:(?:ANTHROPIC|OPENAI)_")) {
    $badStatusLeaks.Add($relative) | Out-Null
  }
}

T 'no installer/wrapper writes native Anthropic/OpenAI env vars' { $badMutations.Count -eq 0 }
if ($badMutations.Count) { $badMutations | Sort-Object -Unique | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkYellow } }
T 'VS Code installer does not read or print native Anthropic/OpenAI env vars' { $badStatusLeaks.Count -eq 0 }
if ($badStatusLeaks.Count) { $badStatusLeaks | Sort-Object -Unique | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkYellow } }
T 'SCX API key is the only provider key set by VS Code installer' {
  $installer = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot 'install\Install-KritScxVsCode.ps1')
  ($installer -match "Set-HkcuVar 'SCX_API_KEY'") -and
  ($installer -notmatch "Set-HkcuVar '(?:ANTHROPIC|OPENAI)_")
}

Write-Host "`n===== $pass passed, $fail failed =====" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $fail
