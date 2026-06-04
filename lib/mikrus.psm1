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
