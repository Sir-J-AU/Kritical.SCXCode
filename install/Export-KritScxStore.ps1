<#
.SYNOPSIS
  Re-export KriticalSCXCodeStore rows back to files (DECOMPRESS), and VERIFY round-trip fidelity
  (re-hash DECOMPRESS'd content vs the stored SHA — proves lossless ingest->store->re-export).

.PARAMETER Mode      Verify | Export   (default Verify)
.PARAMETER OutDir    Export target (default C:\KriticalSCX\store-export)
.EXAMPLE  pwsh Export-KritScxStore.ps1 -Mode Verify
.EXAMPLE  pwsh Export-KritScxStore.ps1 -Mode Export -OutDir C:\KriticalSCX\store-export
#>
[CmdletBinding()]
param([ValidateSet('Verify','Export')][string]$Mode='Verify',
      [string]$OutDir='C:\KriticalSCX\store-export',
      [string]$Server='.\SQLEXPRESS', [string]$DbName='KriticalSCXCodeStore')
$ErrorActionPreference='Continue'
$venvPy='C:\KriticalSCX\venv-litellm-test\Scripts\python.exe'

if ($Mode -eq 'Verify') {
  Write-Host "=== Round-trip fidelity (DECOMPRESS -> re-hash vs stored SHA) ===" -ForegroundColor Cyan
  & $venvPy "$PSScriptRoot\store_verify.py"
  return
}

# Export: dump decompressed content to files, grouped by table
New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($t in @(
    @{ tbl='v_decision_log'; key='id';     ext='txt';  content='content' },
    @{ tbl='lens_artifact';  key='tool';   ext='json'; content='CAST(DECOMPRESS(content_gz) AS NVARCHAR(MAX))' },
    @{ tbl='context_shard';  key='shard_id';ext='txt'; content='CAST(DECOMPRESS(content_gz) AS NVARCHAR(MAX))' })) {
  $dir = Join-Path $OutDir $t.tbl; New-Item -ItemType Directory -Force $dir | Out-Null
  $rows = sqlcmd -S $Server -d $DbName -E -h -1 -W -Q "SELECT COUNT(*) FROM dbo.$($t.tbl);" 2>&1 | Select-Object -First 1
  # export each row's content to a file via python (handles large/NVARCHAR cleanly)
  & $venvPy -c @"
import pyodbc,os
cn=pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=$($Server.Replace('\','\\'));DATABASE=$DbName;Trusted_Connection=yes;Encrypt=no;',timeout=20)
cur=cn.cursor()
n=0
for k,c in cur.execute("SELECT $($t.key), $($t.content) FROM dbo.$($t.tbl)"):
    if c is None: continue
    open(os.path.join(r'$dir', f'{n}_{str(k)[:24]}.$($t.ext)'),'w',encoding='utf-8').write(str(c)); n+=1
print(f'  $($t.tbl): exported {n} files')
cn.close()
"@ 2>&1 | Where-Object { $_ -match '\S' } | ForEach-Object { Write-Host $_ -ForegroundColor Green }
}
Write-Host "`nExported to $OutDir" -ForegroundColor Green
