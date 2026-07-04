<#  HR21 paired test — store round-trip fidelity must be 100% (DECOMPRESS re-hash == stored SHA). #>
$ErrorActionPreference='Continue'
$venvPy='C:\KriticalSCX\venv-litellm-test\Scripts\python.exe'
$verify="$PSScriptRoot\..\install\store_verify.py"
$out = & $venvPy $verify 2>&1
$out | ForEach-Object { Write-Host "  $_" }
$line = ($out | Select-String 'TOTAL FIDELITY').ToString()
$ok = $line -match '\(100\.0%\)' -or $line -match 'rows lossless \(100'
Write-Host "`n$(if($ok){'PASS'}else{'FAIL'}) store round-trip fidelity = 100%" -ForegroundColor $(if($ok){'Green'}else{'Red'})
exit ([int](-not $ok))
