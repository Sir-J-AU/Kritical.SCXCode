#requires -Version 7.0
# Pester 5. Fake OpenAI-compatible endpoint (HttpListener) in a background runspace.
BeforeAll {
  $script:Runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Invoke-KritFreeRouterLane.ps1'
  # Mutation hook: point at a deliberately broken copy to prove the gate goes RED.
  if ($env:KRIT_LANE_RUNNER_UNDER_TEST) { $script:Runner = $env:KRIT_LANE_RUNNER_UNDER_TEST }
  $script:Port = Get-Random -Minimum 20000 -Maximum 29000
  $script:Work = Join-Path ([IO.Path]::GetTempPath()) ('krit-free-lane-' + [guid]::NewGuid().ToString('n'))
  New-Item -ItemType Directory -Path $script:Work | Out-Null
  $script:ModeFile = Join-Path $script:Work 'mode.txt'
  Set-Content $script:ModeFile 'ok'
  $script:Rs = [runspacefactory]::CreateRunspace(); $script:Rs.Open()
  $script:Ps = [powershell]::Create(); $script:Ps.Runspace = $script:Rs
  [void]$script:Ps.AddScript({
    param($port, $modeFile)
    $l = [Net.HttpListener]::new(); $l.Prefixes.Add("http://127.0.0.1:$port/"); $l.Start()
    while ($l.IsListening) {
      try { $c = $l.GetContext() } catch { break }
      $mode = (Get-Content $modeFile -Raw).Trim()
      if ($mode -eq 'quit') { $c.Response.Close(); $l.Stop(); break }
      if ($mode -eq 'http500') { $c.Response.StatusCode = 500; $json = '{"error":"boom"}' }
      else {
        $content = switch ($mode) { 'empty' { '' } 'blank' { '   ' } default { 'POSITIVE' } }
        $json = (@{ model = 'fake/free-model:free'; choices = @(@{ message = @{ role = 'assistant'; content = $content } }) } | ConvertTo-Json -Depth 5 -Compress)
      }
      $b = [Text.Encoding]::UTF8.GetBytes($json); $c.Response.ContentType = 'application/json'
      $c.Response.OutputStream.Write($b, 0, $b.Length); $c.Response.Close()
    }
  }).AddArgument($script:Port).AddArgument($script:ModeFile)
  $script:Handle = $script:Ps.BeginInvoke()
  Start-Sleep -Milliseconds 500
  function script:Run-Lane([string]$mode, [string]$briefText = 'Classify: great service. One word.') {
    Set-Content $script:ModeFile $mode
    $brief = Join-Path $script:Work 'brief.txt'; Set-Content $brief $briefText
    $out = Join-Path $script:Work "out-$mode.txt"; if (Test-Path $out) { Remove-Item $out }
    $led = Join-Path $script:Work 'ledger.jsonl'
    $err = $null; $res = $null
    try { $res = & $script:Runner -BriefPath $brief -OutPath $out -BaseUri "http://127.0.0.1:$($script:Port)" -LedgerPath $led -LaneId "t-$mode" -TimeoutSec 15 } catch { $err = $_.Exception.Message }
    [pscustomobject]@{ Result = $res; Error = $err; Out = $out; Ledger = $led }
  }
}
AfterAll {
  # Ask the fake server to exit its loop (Stop() would block on GetContext), then reap the runspace.
  try { Set-Content $script:ModeFile 'quit'; Invoke-WebRequest "http://127.0.0.1:$($script:Port)/" -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}
  try { [void]$script:Handle.AsyncWaitHandle.WaitOne(5000) } catch {}
  try { $script:Rs.Close() } catch {}
  Remove-Item $script:Work -Recurse -Force -ErrorAction SilentlyContinue
}
Describe 'Invoke-KritFreeRouterLane' {
  It 'writes the answer and ledger START+DONE with model/bytes/ms on a good answer' {
    $r = Run-Lane 'ok'
    $r.Error | Should -BeNullOrEmpty
    (Get-Content $r.Out -Raw) | Should -Be 'POSITIVE'
    $rows = @(Get-Content $r.Ledger | Where-Object { $_ -match '"lane":"t-ok"' } | ForEach-Object { $_ | ConvertFrom-Json })
    ($rows.event -join ',') | Should -Be 'START,DONE'
    $done = $rows | Where-Object event -eq 'DONE'
    $done.model | Should -Be 'fake/free-model:free'
    $done.bytes | Should -Be 8
    $done.ms | Should -BeGreaterOrEqual 0
  }
  It 'FAILS CLOSED on an EMPTY answer (the RED proof): throws, no out file, ledger FAIL' {
    $r = Run-Lane 'empty'
    $r.Error | Should -Match 'EMPTY ANSWER'
    Test-Path $r.Out | Should -BeFalse
    $fail = @(Get-Content $r.Ledger | Where-Object { $_ -match '"lane":"t-empty"' } | ForEach-Object { $_ | ConvertFrom-Json }) | Where-Object event -eq 'FAIL'
    $fail.reason | Should -Match 'EMPTY'
  }
  It 'FAILS CLOSED on a whitespace-only answer' {
    $r = Run-Lane 'blank'
    $r.Error | Should -Match 'EMPTY ANSWER'
    Test-Path $r.Out | Should -BeFalse
  }
  It 'FAILS CLOSED on an HTTP 500' {
    $r = Run-Lane 'http500'
    $r.Error | Should -Match 'request failed'
    Test-Path $r.Out | Should -BeFalse
  }
  It 'refuses to send a brief containing a secret-shaped token' {
    $r = Run-Lane 'ok' 'use key sk-or-v1-abcdef0123456789abcdef0123456789 please'
    $r.Error | Should -Match 'secret pattern'
    Test-Path $r.Out | Should -BeFalse
  }
}
