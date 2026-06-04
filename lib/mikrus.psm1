# Moduł obsługi serwera VPS Mikrus.
# Funkcje publiczne (buildery + wykonanie) eksportowane domyślnie.
# Konfiguracja: ~/.mikrus/config.json (patrz skill mikrus-setup).

Set-StrictMode -Version Latest

function Get-MikrusConfig {
    [CmdletBinding()]
    param(
        [string]$Path = (Join-Path $HOME '.mikrus/config.json')
    )
    if (-not (Test-Path -Path $Path)) {
        throw "Brak konfiguracji Mikrus ($Path). Uruchom skill mikrus-setup, aby ja utworzyc."
    }
    $cfg = Get-Content -Raw -Path $Path | ConvertFrom-Json
    $required = 'srv','host','sshPort','user','identityFile','apiKey','apiBase'
    $missing = foreach ($f in $required) {
        $has = $cfg.PSObject.Properties.Name -contains $f
        if (-not $has -or [string]::IsNullOrWhiteSpace([string]$cfg.$f)) { $f }
    }
    if ($missing) {
        throw "Konfiguracja Mikrus niekompletna ($Path). Brakuje pol: $($missing -join ', '). Uruchom mikrus-setup."
    }
    return $cfg
}

function New-MikrusSSHArgs {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string]$Command
    )
    return @(
        '-p', "$($Config.sshPort)"
        '-i', "$($Config.identityFile)"
        '-o', 'BatchMode=yes'
        "$($Config.user)@$($Config.host)"
        $Command
    )
}

function Invoke-MikrusSSH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        $Config,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $sshArgs = New-MikrusSSHArgs -Config $Config -Command $Command
    if ($DryRun) { return @('ssh') + $sshArgs }
    $output = & ssh @sshArgs 2>&1
    return [pscustomobject]@{
        Output   = $output
        ExitCode = $LASTEXITCODE
    }
}

function New-MikrusScpArgs {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][ValidateSet('up','down')][string]$Direction,
        [Parameter(Mandatory)][string]$Local,
        [Parameter(Mandatory)][string]$Remote,
        [switch]$Recurse
    )
    $remoteSpec = "$($Config.user)@$($Config.host):$Remote"
    $scpArgs = @('-P', "$($Config.sshPort)", '-i', "$($Config.identityFile)", '-o', 'BatchMode=yes')
    if ($Recurse) { $scpArgs += '-r' }
    if ($Direction -eq 'up') { $scpArgs += @($Local, $remoteSpec) }
    else { $scpArgs += @($remoteSpec, $Local) }
    return $scpArgs
}

function Send-MikrusFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Local,
        [Parameter(Mandatory)][string]$Remote,
        $Config,
        [switch]$Recurse,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $scpArgs = New-MikrusScpArgs -Config $Config -Direction up -Local $Local -Remote $Remote -Recurse:$Recurse
    if ($DryRun) { return @('scp') + $scpArgs }
    $output = & scp @scpArgs 2>&1
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function Get-MikrusFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory)][string]$Local,
        $Config,
        [switch]$Recurse,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $scpArgs = New-MikrusScpArgs -Config $Config -Direction down -Local $Local -Remote $Remote -Recurse:$Recurse
    if ($DryRun) { return @('scp') + $scpArgs }
    $output = & scp @scpArgs 2>&1
    return [pscustomobject]@{ Output = $output; ExitCode = $LASTEXITCODE }
}

function New-MikrusApiRequest {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string]$Endpoint,
        [hashtable]$Body
    )
    $base = ([string]$Config.apiBase).TrimEnd('/')
    $ep   = $Endpoint.TrimStart('/')
    $url  = "$base/$ep"
    $fields = @{ srv = $Config.srv }
    if ($Body) {
        foreach ($k in $Body.Keys) { $fields[$k] = $Body[$k] }
    }
    return @{ Url = $url; Fields = $fields }
}

function Invoke-MikrusCurl {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Fields,
        [Parameter(Mandatory)][string]$ApiKey
    )
    $curlArgs = @('-s', '-X', 'POST', $Url, '-H', "Authorization: $ApiKey")
    foreach ($k in $Fields.Keys) {
        $curlArgs += @('-d', "$k=$($Fields[$k])")
    }
    return (& curl @curlArgs)
}

function Invoke-MikrusApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Endpoint,
        [hashtable]$Body,
        $Config
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $req = New-MikrusApiRequest -Config $Config -Endpoint $Endpoint -Body $Body
    $raw = Invoke-MikrusCurl -Url $req.Url -Fields $req.Fields -ApiKey $Config.apiKey
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        throw "Brak odpowiedzi z API Mikrus ($Endpoint)."
    }
    try {
        $data = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Niepoprawna odpowiedz API ($Endpoint): $raw"
    }
    if (($data -is [System.Management.Automation.PSCustomObject]) -and ($data.PSObject.Properties.Name -contains 'error')) {
        throw "API Mikrus zwrocilo blad ($Endpoint): $($data.error)"
    }
    return $data
}
