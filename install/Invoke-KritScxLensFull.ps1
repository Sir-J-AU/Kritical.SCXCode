<#
.SYNOPSIS
  Full-Lens ingestion — run every applicable Kritical Lens tool over a repo and store the
  JSON artifacts (compressed, deduped) in KriticalSCXCodeStore.dbo.lens_artifact, PLUS the
  SqlMiner catalog (via the existing ingest). Idempotent; re-run any time. HR29: read-only on code.

  Tools: SqlMiner (catalog) · CodeGraph (semantic graph) · PSGraph (PS call graph) ·
         ALDependencyMatrix (only if .al files present under -Root).

.PARAMETER Root    Repo to mine (default the Kritical.SCXCode repo).
.PARAMETER Mode    Ingest | Status   (default Ingest)
.EXAMPLE  pwsh Invoke-KritScxLensFull.ps1
.EXAMPLE  pwsh Invoke-KritScxLensFull.ps1 -Mode Status
#>
[CmdletBinding()]
param([string]$Root="C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode",
      [ValidateSet('Ingest','Status')][string]$Mode='Ingest',
      [string]$Server='.\SQLEXPRESS', [string]$DbName='KriticalSCXCodeStore')
$ErrorActionPreference='Continue'
$GH = "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github"
$conn = "Server=$Server;Database=$DbName;Integrated Security=True;TrustServerCertificate=True;"

# ensure the artifact table exists
$schema = @"
IF OBJECT_ID('dbo.lens_artifact') IS NULL
CREATE TABLE dbo.lens_artifact (
  id BIGINT IDENTITY(1,1) PRIMARY KEY,
  tool VARCHAR(64) NOT NULL, root NVARCHAR(400) NULL,
  content_sha256 CHAR(64) NOT NULL, content_gz VARBINARY(MAX) NULL, byte_len INT NULL,
  generated_utc DATETIME2(3) NOT NULL CONSTRAINT DF_lens_art DEFAULT SYSUTCDATETIME()
);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='UX_lens_artifact')
  CREATE UNIQUE INDEX UX_lens_artifact ON dbo.lens_artifact(tool, content_sha256);
"@
sqlcmd -S $Server -d $DbName -E -b -Q $schema 2>&1 | Out-Null

if ($Mode -eq 'Status') {
  Write-Host "`n=== Lens artifacts in $DbName ===" -ForegroundColor Cyan
  sqlcmd -S $Server -d $DbName -E -h -1 -W -Q "SELECT tool, COUNT(*) n, MAX(generated_utc) latest FROM dbo.lens_artifact GROUP BY tool;" 2>&1 | ForEach-Object { "  $_" }
  sqlcmd -S $Server -d $DbName -E -h -1 -W -Q "SELECT CONCAT('LensSqlCatalog rows=', COUNT(*)) FROM dbo.LensSqlCatalog;" 2>&1 | ForEach-Object { "  $_" }
  return
}

$venvPy = 'C:\KriticalSCX\venv-litellm-test\Scripts\python.exe'
function Ingest-Artifact($tool, $jsonPath) {
  if (-not (Test-Path $jsonPath)) { Write-Host "  ${tool}: no output" -ForegroundColor DarkYellow; return }
  # pyodbc path (like the live-sink callback) — reliable, no SQL-service file-access issue
  $r = & $venvPy "$PSScriptRoot\lens_ingest.py" $tool $jsonPath $Root 2>&1
  $r | ForEach-Object { if($_ -match '\S'){ Write-Host "  $_" -ForegroundColor Green } }
}

$hasAl = @(Get-ChildItem $Root -Recurse -Filter *.al -EA SilentlyContinue | Select-Object -First 1).Count -gt 0
$tools = @(
  @{ n='CodeGraph';          mod='Kritical.Lens.CodeGraph';          fn='Invoke-KriticalLensCodeGraph' },
  @{ n='PSGraph';            mod='Kritical.Lens.PSGraph';            fn='Invoke-KriticalLensPSGraph' }
)
if ($hasAl) { $tools += @{ n='ALDependencyMatrix'; mod='Kritical.Lens.ALDependencyMatrix'; fn='Invoke-KriticalLensALDependencyMatrix' } }

foreach ($t in $tools) {
  Write-Host "[Lens] $($t.n) ..." -ForegroundColor Yellow
  try {
    Import-Module "$GH\$($t.mod)\src\$($t.mod).psd1" -Force -EA Stop
    $out = "$env:TEMP\lens-$($t.n)-$(Get-Date -Format yyyyMMddHHmmss).json"
    & $t.fn -Root $Root -OutputJson $out 2>&1 | Select-Object -Last 1 | Out-Null
    Ingest-Artifact $t.n $out
  } catch { Write-Host "  $($t.n) skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow }
}

# SqlMiner via the existing ingest (into LensSqlCatalog)
Write-Host "[Lens] SqlMiner (catalog) ..." -ForegroundColor Yellow
try { & "$PSScriptRoot\Invoke-KritScxLensIngest.ps1" -Root $Root -Mode Ingest 2>&1 | Select-Object -Last 2 | Out-Host } catch { Write-Host "  SqlMiner skipped: $_" -ForegroundColor DarkYellow }

Write-Host "`nDone. Check: pwsh Invoke-KritScxLensFull.ps1 -Mode Status" -ForegroundColor Green
