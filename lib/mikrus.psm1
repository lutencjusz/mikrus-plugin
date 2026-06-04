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
