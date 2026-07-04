<#
.SYNOPSIS
  Semantic-parse + SQL-mine every line of a repo with Kritical Lens, ingesting into OUR store
  (KriticalSCXCodeStore — NOT KriticalBrain). Background-friendly; check the result table later.

  Add/remove/idempotent: re-run any time (Lens ingest UPSERTs by catalog key). -Mode Status to check.

.PARAMETER Root      Repo to mine (default the Kritical.SCXCode repo).
.PARAMETER Server    SQL instance (default .\SQLEXPRESS).
.PARAMETER DbName    Store DB (default KriticalSCXCodeStore).
.PARAMETER Mode      Ingest | Status   (default Ingest)
.EXAMPLE  pwsh Invoke-KritScxLensIngest.ps1                       # mine+ingest this repo
.EXAMPLE  pwsh Invoke-KritScxLensIngest.ps1 -Mode Status          # rows ingested so far
#>
[CmdletBinding()]
param([string]$Root="C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode",
      [string]$Server='.\SQLEXPRESS', [string]$DbName='KriticalSCXCodeStore',
      [ValidateSet('Ingest','Status')][string]$Mode='Ingest',
      [string]$Table='dbo.LensSqlCatalog')
$ErrorActionPreference='Continue'
$conn = "Server=$Server;Database=$DbName;Integrated Security=True;TrustServerCertificate=True;"
$miner = "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens.SqlMiner\src\Kritical.Lens.SqlMiner.psd1"

if ($Mode -eq 'Status') {
  $c = sqlcmd -S $Server -d $DbName -E -h -1 -W -Q "IF OBJECT_ID('$Table') IS NULL PRINT 'no table yet'; ELSE SELECT CONCAT('rows=',COUNT(*)) FROM $Table;" 2>&1
  Write-Host "Lens catalog @ $Server/$DbName/$Table :" -ForegroundColor Cyan; $c | ForEach-Object { "  $_" }
  return
}

Import-Module $miner -Force -ErrorAction Stop
$catalog = Join-Path $env:TEMP "krit-lens-scxcode-$(Get-Date -Format yyyyMMddHHmmss).json"
Write-Host "[1/2] Lens mine (semantic per-line catalog) -> $catalog" -ForegroundColor Yellow
Invoke-KriticalLensSqlMiner -Root $Root -OutputJson $catalog -ExcludeGenerated 2>&1 | Select-Object -Last 3 | Out-Host
Write-Host "[2/2] Ingest catalog -> $Server/$DbName/$Table" -ForegroundColor Yellow
Ingest-KriticalLensSqlCatalog -Path $catalog -ConnectionString $conn -TableName $Table 2>&1 | Select-Object -Last 5 | Out-Host
Write-Host "Done. Check later:  pwsh Invoke-KritScxLensIngest.ps1 -Mode Status" -ForegroundColor Green
