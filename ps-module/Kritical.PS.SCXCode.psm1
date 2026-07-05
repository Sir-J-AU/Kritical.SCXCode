#Requires -Version 7
<#
.SYNOPSIS
    Kritical.PS.SCXCode — PowerShell client for SCX (api.scx.ai).
.DESCRIPTION
    Chat + model list + embeddings + streaming + connection test + install helper.
    Sibling of kritical.vscode.SCXCode VS Code extension. Both read HKCU env
    SCX_API_KEY (Kritical convention). Apache 2.0.
#>

# ────────────────────────────────────────────────────────────────
# config resolution
# ────────────────────────────────────────────────────────────────

function Get-KritScxConfig {
    <#
    .SYNOPSIS
        Return the effective SCX config (keys, base URL, default model, fallback chain).
    .DESCRIPTION
        Reads SCX_API_KEY (primary) + SCX_API_KEY_2..SCX_API_KEY_N (rotation pool)
        from HKCU. Returns both the primary and the full ordered key list.
    .EXAMPLE
        Get-KritScxConfig
    #>
    [CmdletBinding()]
    param()
    $key = [Environment]::GetEnvironmentVariable('SCX_API_KEY', 'User')
    # .5165e — multi-key rotation. Look up SCX_API_KEY_2 through SCX_API_KEY_9.
    $keys = @()
    if ($key) { $keys += $key }
    for ($i = 2; $i -le 9; $i++) {
        $k = [Environment]::GetEnvironmentVariable("SCX_API_KEY_$i", 'User')
        if ($k -and $k -ne $key) { $keys += $k }
    }
    $baseUrl = [Environment]::GetEnvironmentVariable('KRIT_SCX_BASE_URL', 'User')
    if (-not $baseUrl) { $baseUrl = 'https://api.scx.ai' }
    $default = [Environment]::GetEnvironmentVariable('KRIT_SCX_MODEL_DEFAULT', 'User')
    if (-not $default) { $default = 'MiniMax-M2.7' }
    $fallbackRaw = [Environment]::GetEnvironmentVariable('KRIT_SCX_FALLBACK_CHAIN', 'User')
    $fallback = if ($fallbackRaw) { $fallbackRaw -split ',' | ForEach-Object { $_.Trim() } } else { @('MiniMax-M2.7', 'MAGPiE', 'gpt-oss-120b') }
    [pscustomobject]@{
        HasKey        = [bool]$key
        KeyLength     = if ($key) { $key.Length } else { 0 }
        KeyPrefix     = if ($key -and $key.Length -ge 8) { $key.Substring(0, 8) } else { '' }
        KeyCount      = $keys.Count
        KeyPrefixes   = ($keys | ForEach-Object { if ($_.Length -ge 8) { $_.Substring(0, 8) } else { '(short)' } })
        Keys          = $keys
        BaseUrl       = $baseUrl
        DefaultModel  = $default
        FallbackChain = $fallback
        Source        = 'HKCU (Kritical convention)'
    }
}

function Set-KritScxConfig {
    <#
    .SYNOPSIS
        Set SCX config in HKCU. Any parameter left null leaves that env var untouched.
        This module never reads, writes, removes, or reports native Anthropic/OpenAI env vars.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$ApiKey,
        [string]$BaseUrl,
        [string]$DefaultModel,
        [string[]]$FallbackChain
    )
    if ($ApiKey -and $PSCmdlet.ShouldProcess('HKCU SCX_API_KEY', 'set')) {
        [Environment]::SetEnvironmentVariable('SCX_API_KEY', $ApiKey, 'User')
    }
    if ($BaseUrl -and $PSCmdlet.ShouldProcess('HKCU KRIT_SCX_BASE_URL', 'set')) {
        [Environment]::SetEnvironmentVariable('KRIT_SCX_BASE_URL', $BaseUrl, 'User')
    }
    if ($DefaultModel -and $PSCmdlet.ShouldProcess('HKCU KRIT_SCX_MODEL_DEFAULT', 'set')) {
        [Environment]::SetEnvironmentVariable('KRIT_SCX_MODEL_DEFAULT', $DefaultModel, 'User')
    }
    if ($FallbackChain -and $PSCmdlet.ShouldProcess('HKCU KRIT_SCX_FALLBACK_CHAIN', 'set')) {
        [Environment]::SetEnvironmentVariable('KRIT_SCX_FALLBACK_CHAIN', ($FallbackChain -join ','), 'User')
    }
    Get-KritScxConfig
}

# ────────────────────────────────────────────────────────────────
# HTTP core
# ────────────────────────────────────────────────────────────────

function Invoke-KritScx {
    <#
    .SYNOPSIS
        POST /v1/messages (Anthropic shape) to SCX. Low-level primitive.
    .EXAMPLE
        Invoke-KritScx -Model MiniMax-M2.7 -Messages @(@{role='user'; content='hi'})
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][hashtable[]]$Messages,
        [int]$MaxTokens = 1000,
        [string]$System,
        [string]$ApiKey,
        [string]$BaseUrl
    )
    $cfg = Get-KritScxConfig
    if (-not $ApiKey) { $ApiKey = [Environment]::GetEnvironmentVariable('SCX_API_KEY', 'User') }
    if (-not $ApiKey) { throw 'SCX_API_KEY not set. Run Install-KritScxKey OR Set-KritScxConfig -ApiKey ...' }
    if (-not $BaseUrl) { $BaseUrl = $cfg.BaseUrl }

    $body = @{ model = $Model; max_tokens = $MaxTokens; messages = @($Messages) }
    if ($System) { $body.system = $System }
    $bodyJson = $body | ConvertTo-Json -Depth 8

    $headers = @{
        'x-api-key'         = $ApiKey
        'anthropic-version' = '2023-06-01'
        'content-type'      = 'application/json'
    }
    $uri = "$BaseUrl/v1/messages"
    try {
        return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyJson -TimeoutSec 120
    } catch {
        $exc = $_.Exception
        $status = if ($exc.Response) { [int]$exc.Response.StatusCode } else { 0 }
        $errBody = if ($exc.Response) {
            try { (New-Object System.IO.StreamReader($exc.Response.GetResponseStream())).ReadToEnd() } catch { $exc.Message }
        } else { $exc.Message }
        throw [pscustomobject]@{ Status = $status; Body = $errBody; Message = $exc.Message; IsRateLimit = ($status -eq 429); IsServerError = ($status -ge 500) }
    }
}

function Invoke-KritScxChat {
    <#
    .SYNOPSIS
        Send one user message, get plain-text reply. Auto-failover across FallbackChain on 429/5xx.
        On rate-limit, tries `Switch-KritScxKey` once to swap to the next healthy key file,
        then retries. Uses HKCU SCX_API_KEY only — key rotation is a management operation, not
        a hot-path grid walk.
    .EXAMPLE
        Invoke-KritScxChat -Prompt 'what is 47*3?'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Prompt,
        [string]$Model,
        [int]$MaxTokens = 1200,
        [string]$System,
        [switch]$NoAutoSwitch
    )
    $cfg = Get-KritScxConfig
    if (-not $Model) { $Model = $cfg.DefaultModel }
    $chain = @($Model) + @($cfg.FallbackChain | Where-Object { $_ -ne $Model })
    $attempts = @()
    $lastErr = $null
    $switched = $false
    foreach ($m in $chain) {
        $attempts += $m
        try {
            $r = Invoke-KritScx -Model $m -Messages @(@{ role = 'user'; content = $Prompt }) -MaxTokens $MaxTokens -System:$System
            $text = ($r.content | ForEach-Object { $_.text }) -join ''
            return [pscustomobject]@{
                Model     = $m
                Text      = $text
                InTokens  = $r.usage.input_tokens
                OutTokens = $r.usage.output_tokens
                Attempts  = $attempts
                Raw       = $r
            }
        } catch {
            $lastErr = $_.TargetObject
            # .5165f — on rate-limit, swap HKCU key once + retry current model.
            if ($lastErr.IsRateLimit -and -not $switched -and -not $NoAutoSwitch) {
                Write-Verbose 'Rate limit — trying Switch-KritScxKey'
                $r2 = Switch-KritScxKey
                if ($r2.Switched) {
                    $switched = $true
                    $attempts += "$m (post-key-switch)"
                    try {
                        $r = Invoke-KritScx -Model $m -Messages @(@{ role = 'user'; content = $Prompt }) -MaxTokens $MaxTokens -System:$System
                        $text = ($r.content | ForEach-Object { $_.text }) -join ''
                        return [pscustomobject]@{
                            Model     = $m
                            Text      = $text
                            InTokens  = $r.usage.input_tokens
                            OutTokens = $r.usage.output_tokens
                            Attempts  = $attempts
                            Raw       = $r
                        }
                    } catch { $lastErr = $_.TargetObject }
                }
            }
            if ($lastErr.IsRateLimit -or $lastErr.IsServerError) { continue }
            throw $_
        }
    }
    throw ("Failover exhausted (tried {0}): {1}" -f ($attempts -join ' -> '), $lastErr.Body)
}

function Switch-KritScxKey {
    <#
    .SYNOPSIS
        Rotate HKCU SCX_API_KEY to the next healthy key file in the secrets dir.
    .DESCRIPTION
        Reads every scx-*apiKey*.txt (and scx-benApiKey / scx-previousApiKeyPreBenSwitch)
        under the Kritical secrets dir. Skips the one currently in HKCU. Tests each
        candidate with a 20-token /v1/messages ping. First to respond 200 (or any non-429
        auth-valid response) becomes the new HKCU SCX_API_KEY. Returns which key was picked.

        Files must be exactly 39-char keys (starts with 'sk-scx-'). Files > 100 chars or
        with 'anthropicCompatible' in the name are treated as narrative blobs and skipped.
    .PARAMETER SecretsDir
        Kritical secrets root. Default: OneDrive Github-SecretsOutsideOfGitRepos.
    .EXAMPLE
        Switch-KritScxKey
        Switch-KritScxKey -Verbose
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$SecretsDir = 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos'
    )
    if (-not (Test-Path $SecretsDir)) { throw "SecretsDir not found: $SecretsDir" }

    $currentKey = [Environment]::GetEnvironmentVariable('SCX_API_KEY', 'User')
    $candidates = Get-ChildItem -LiteralPath $SecretsDir -Filter 'scx-*.txt' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*anthropicCompatible*' } |
        ForEach-Object {
            $raw = (Get-Content -LiteralPath $_.FullName -Raw).Trim()
            if ($raw.Length -eq 39 -and $raw.StartsWith('sk-scx-')) {
                [pscustomobject]@{ File = $_.Name; Key = $raw; Prefix = $raw.Substring(0, 8) }
            }
        } | Sort-Object File

    if (-not $candidates) { return [pscustomobject]@{ Switched = $false; Reason = 'no candidate keys in secrets dir' } }

    $others = $candidates | Where-Object { $_.Key -ne $currentKey }
    if (-not $others) { return [pscustomobject]@{ Switched = $false; Reason = 'only one key available (already in HKCU)'; Current = $candidates[0].Prefix } }

    # .5231 (bughunt) — $currentKey is null when SCX_API_KEY isn't in HKCU; .Substring(0,8) threw. Guard.
    $curShown = if ($currentKey -and $currentKey.Length -ge 8) { $currentKey.Substring(0, 8) } elseif ($currentKey) { $currentKey } else { '(none set)' }
    Write-Verbose "candidates: $($candidates.Prefix -join ', '); current: $curShown"

    foreach ($cand in $others) {
        Write-Verbose "probing $($cand.File) ($($cand.Prefix))..."
        try {
            $probe = Invoke-KritScx -Model 'MiniMax-M2.7' -Messages @(@{ role = 'user'; content = 'reply just OK' }) -MaxTokens 20 -ApiKey $cand.Key
            if ($PSCmdlet.ShouldProcess("HKCU SCX_API_KEY", "swap to $($cand.File)")) {
                [Environment]::SetEnvironmentVariable('SCX_API_KEY', $cand.Key, 'User')
            }
            return [pscustomobject]@{ Switched = $true; File = $cand.File; Prefix = $cand.Prefix; ProbeVerdict = 'OK' }
        } catch {
            $err = $_.TargetObject
            if ($err -and $err.IsRateLimit) {
                Write-Verbose "  429 (this key also spent)"
                continue
            }
            Write-Verbose "  non-429 error: $($err.Message ?? $_.Exception.Message)"
            continue
        }
    }
    return [pscustomobject]@{ Switched = $false; Reason = 'all candidate keys 429 or errored'; TriedFiles = ($others.File) }
}

# ────────────────────────────────────────────────────────────────
# models + status
# ────────────────────────────────────────────────────────────────

function Get-KritScxModels {
    <#
    .SYNOPSIS
        List all models the SCX catalog exposes (GET /v1/models).
    #>
    [CmdletBinding()]
    param([switch]$Full)
    $cfg = Get-KritScxConfig
    $key = [Environment]::GetEnvironmentVariable('SCX_API_KEY', 'User')
    if (-not $key) { throw 'SCX_API_KEY not set. Install-KritScxKey first.' }
    $r = Invoke-RestMethod -Method Get -Uri "$($cfg.BaseUrl)/v1/models" -Headers @{ 'x-api-key' = $key }
    if ($Full) { return $r.data }
    $r.data | Select-Object id, @{n = 'ctx'; e = { $_.context_length } }, @{n = 'maxOut'; e = { $_.max_output_length } }, @{n = 'in$/1M'; e = { [math]::Round([double]$_.pricing.prompt * 1e6, 4) } }, @{n = 'out$/1M'; e = { [math]::Round([double]$_.pricing.completion * 1e6, 4) } }
}

function Test-KritScxConnection {
    <#
    .SYNOPSIS
        Ping /v1/messages with 20-token round-trip on default model. Returns latency + verdict.
    #>
    [CmdletBinding()]
    param([string]$Model)
    $cfg = Get-KritScxConfig
    if (-not $Model) { $Model = $cfg.DefaultModel }
    $t0 = Get-Date
    try {
        $r = Invoke-KritScx -Model $Model -Messages @(@{ role = 'user'; content = 'reply just OK' }) -MaxTokens 20
        $ms = [int]((New-TimeSpan -Start $t0 -End (Get-Date)).TotalMilliseconds)
        [pscustomobject]@{
            Ok      = $true
            Model   = $Model
            LatMs   = $ms
            Reply   = ($r.content | ForEach-Object { $_.text }) -join ''
            InTok   = $r.usage.input_tokens
            OutTok  = $r.usage.output_tokens
        }
    } catch {
        $ms = [int]((New-TimeSpan -Start $t0 -End (Get-Date)).TotalMilliseconds)
        $err = $_.TargetObject
        [pscustomobject]@{
            Ok           = $false
            Model        = $Model
            LatMs        = $ms
            Status       = $err.Status
            IsRateLimit  = $err.IsRateLimit
            Error        = ($err.Body ?? $_.Exception.Message)
        }
    }
}

function New-KritScxEmbedding {
    <#
    .SYNOPSIS
        Generate embeddings via SCX E5-Mistral-7B-Instruct (OpenAI-shape endpoint).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Texts,
        [string]$Model = 'E5-Mistral-7B-Instruct'
    )
    $cfg = Get-KritScxConfig
    $key = [Environment]::GetEnvironmentVariable('SCX_API_KEY', 'User')
    if (-not $key) { throw 'SCX_API_KEY not set.' }
    $body = @{ model = $Model; input = $Texts } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Method Post -Uri "$($cfg.BaseUrl)/v1/embeddings" -Headers @{ 'x-api-key' = $key; 'content-type' = 'application/json' } -Body $body -TimeoutSec 60
    $r.data
}

function Get-KritScxStatus {
    <#
    .SYNOPSIS
        Read-only inventory: HKCU env, endpoint reachable?, models available count, latest chat latency.
    #>
    [CmdletBinding()]
    param()
    $cfg = Get-KritScxConfig
    $probe = if ($cfg.HasKey) {
        try {
            $mCount = @(Get-KritScxModels).Count
            $t = Test-KritScxConnection
            [pscustomobject]@{ Alive = $true; ModelCount = $mCount; Latency = $t.LatMs; TestVerdict = if ($t.Ok) { 'OK' } else { "FAIL ({0})" -f $t.Status } }
        } catch { [pscustomobject]@{ Alive = $false; Reason = $_.Exception.Message } }
    } else {
        [pscustomobject]@{ Alive = $false; Reason = 'No SCX_API_KEY in HKCU' }
    }
    [pscustomobject]@{
        Config = $cfg
        Probe  = $probe
    }
}

# ────────────────────────────────────────────────────────────────
# install / uninstall HKCU
# ────────────────────────────────────────────────────────────────

function Install-KritScxKey {
    <#
    .SYNOPSIS
        Copy the newest scx-benApiKey-*.txt into HKCU SCX_API_KEY + set defaults.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$SecretsDir = 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github-SecretsOutsideOfGitRepos',
        [string]$DefaultModel = 'MiniMax-M2.7'
    )
    $file = Get-ChildItem -LiteralPath $SecretsDir -Filter 'scx-benApiKey-*.txt' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $file) { throw "No scx-benApiKey-*.txt found in $SecretsDir" }
    $key = (Get-Content -LiteralPath $file.FullName -Raw).Trim()
    Set-KritScxConfig -ApiKey $key -BaseUrl 'https://api.scx.ai' -DefaultModel $DefaultModel -Confirm:$false
    Write-Verbose "installed HKCU env from $($file.Name) (len=$($key.Length))"
    Get-KritScxConfig
}

function Uninstall-KritScxKey {
    <#
    .SYNOPSIS
        Remove Kritical HKCU env vars only. Native Anthropic/OpenAI env vars are never touched.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    foreach ($n in 'SCX_API_KEY', 'KRIT_SCX_BASE_URL', 'KRIT_SCX_MODEL_DEFAULT', 'KRIT_SCX_FALLBACK_CHAIN') {
        if ($PSCmdlet.ShouldProcess("HKCU $n", 'remove')) {
            [Environment]::SetEnvironmentVariable($n, $null, 'User')
        }
    }
    Get-KritScxConfig
}

# ────────────────────────────────────────────────────────────────
# aliases
# ────────────────────────────────────────────────────────────────

Set-Alias -Name scx        -Value Invoke-KritScxChat -Scope Global
Set-Alias -Name scx-chat   -Value Invoke-KritScxChat -Scope Global
Set-Alias -Name scx-models -Value Get-KritScxModels  -Scope Global
Set-Alias -Name scx-test   -Value Test-KritScxConnection -Scope Global

Export-ModuleMember -Function Invoke-KritScx, Invoke-KritScxChat, Get-KritScxModels, Get-KritScxConfig, Set-KritScxConfig, Test-KritScxConnection, New-KritScxEmbedding, Get-KritScxStatus, Install-KritScxKey, Uninstall-KritScxKey, Switch-KritScxKey -Alias scx, scx-chat, scx-models, scx-test
