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

# Domyslne limity czasu polaczenia (sekundy). Bez nich ssh/scp potrafi wisiec
# w nieskonczonosc: ConnectTimeout ucina martwy handshake TCP, a ServerAlive*
# wykrywa sesje, ktora zawisla juz PO polaczeniu (np. kontener pod presja RAM
# przyjmuje TCP, ale sshd przestaje odpowiadac). Mozna nadpisac przez pola
# connectTimeout / serverAliveInterval / serverAliveCountMax w config.json.
$script:MikrusDefaultConnectTimeout    = 15
$script:MikrusDefaultServerAliveInt    = 10
$script:MikrusDefaultServerAliveCount  = 3

function Get-MikrusConnectOption {
    param(
        [Parameter(Mandatory)] $Config,
        [Parameter(Mandatory)][string]$Field,
        [Parameter(Mandatory)]$Default
    )
    if ($Config.PSObject.Properties.Name -contains $Field -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.$Field)) {
        return $Config.$Field
    }
    return $Default
}

function New-MikrusTimeoutArgs {
    param([Parameter(Mandatory)] $Config)
    $ct  = Get-MikrusConnectOption -Config $Config -Field 'connectTimeout'        -Default $script:MikrusDefaultConnectTimeout
    $sai = Get-MikrusConnectOption -Config $Config -Field 'serverAliveInterval'   -Default $script:MikrusDefaultServerAliveInt
    $sac = Get-MikrusConnectOption -Config $Config -Field 'serverAliveCountMax'   -Default $script:MikrusDefaultServerAliveCount
    return @(
        '-o', "ConnectTimeout=$ct"
        '-o', "ServerAliveInterval=$sai"
        '-o', "ServerAliveCountMax=$sac"
    )
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
    ) + (New-MikrusTimeoutArgs -Config $Config) + @(
        "$($Config.user)@$($Config.host)"
        $Command
    )
}

# Domyslny twardy limit (sekundy) na CALY proces ssh/scp. To backstop ostateczny:
# ConnectTimeout pilnuje tylko handshake TCP, a ServerAlive* dziala dopiero PO
# uwierzytelnieniu — zwis w fazie wymiany kluczy/auth omija oba i wisialby
# w nieskonczonosc. Po przekroczeniu proces (z drzewem potomnym) jest ubijany,
# a wynik ma ExitCode 124 (jak `timeout`). Dla dlugich operacji (backup,
# streaming) podaj wiekszy -TimeoutSec lub pole commandTimeout w config.json.
$script:MikrusDefaultCommandTimeout = 180

function Invoke-MikrusNative {
    # Uruchamia natywny program (ssh/scp) z twardym limitem czasu. Argumenty ida
    # przez ProcessStartInfo.ArgumentList, ktore escape'uje kazdy element osobno
    # — tak samo jak operator & , wiec zlozone komendy zdalne (cudzyslowy,
    # heredoki) zostaja nienaruszone.
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSec
    )
    if (-not $TimeoutSec -or $TimeoutSec -le 0) { $TimeoutSec = $script:MikrusDefaultCommandTimeout }
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $Exe
    foreach ($a in $Arguments) { $psi.ArgumentList.Add([string]$a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill($true) } catch { try { $proc.Kill() } catch {} }
        try { $null = $proc.WaitForExit(5000) } catch {}
        $partial = @($outTask, $errTask | ForEach-Object { try { $_.Result } catch { '' } } | Where-Object { $_ })
        $msg = "TIMEOUT: $Exe nie odpowiedzial w ${TimeoutSec}s (polaczenie/komenda zawieszone) — proces ubity. Zwieksz -TimeoutSec dla dlugich operacji."
        return [pscustomobject]@{
            Output   = (@($msg) + $partial) -join [Environment]::NewLine
            ExitCode = 124
            TimedOut = $true
        }
    }
    $out = try { $outTask.Result } catch { '' }
    $err = try { $errTask.Result } catch { '' }
    $merged = @()
    if ($err) { $merged += $err.TrimEnd("`r", "`n") }
    if ($out) { $merged += $out.TrimEnd("`r", "`n") }
    return [pscustomobject]@{
        Output   = ($merged -join [Environment]::NewLine)
        ExitCode = $proc.ExitCode
        TimedOut = $false
    }
}

function Invoke-MikrusSSH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        $Config,
        [int]$TimeoutSec,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $sshArgs = New-MikrusSSHArgs -Config $Config -Command $Command
    if ($DryRun) { return @('ssh') + $sshArgs }
    if (-not $TimeoutSec) { $TimeoutSec = Get-MikrusConnectOption -Config $Config -Field 'commandTimeout' -Default $script:MikrusDefaultCommandTimeout }
    return Invoke-MikrusNative -Exe 'ssh' -Arguments $sshArgs -TimeoutSec $TimeoutSec
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
    $scpArgs += New-MikrusTimeoutArgs -Config $Config
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
        [int]$TimeoutSec,
        [switch]$Recurse,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $scpArgs = New-MikrusScpArgs -Config $Config -Direction up -Local $Local -Remote $Remote -Recurse:$Recurse
    if ($DryRun) { return @('scp') + $scpArgs }
    if (-not $TimeoutSec) { $TimeoutSec = Get-MikrusConnectOption -Config $Config -Field 'commandTimeout' -Default $script:MikrusDefaultCommandTimeout }
    return Invoke-MikrusNative -Exe 'scp' -Arguments $scpArgs -TimeoutSec $TimeoutSec
}

function Get-MikrusFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory)][string]$Local,
        $Config,
        [int]$TimeoutSec,
        [switch]$Recurse,
        [switch]$DryRun
    )
    if (-not $Config) { $Config = Get-MikrusConfig }
    $scpArgs = New-MikrusScpArgs -Config $Config -Direction down -Local $Local -Remote $Remote -Recurse:$Recurse
    if ($DryRun) { return @('scp') + $scpArgs }
    if (-not $TimeoutSec) { $TimeoutSec = Get-MikrusConnectOption -Config $Config -Field 'commandTimeout' -Default $script:MikrusDefaultCommandTimeout }
    return Invoke-MikrusNative -Exe 'scp' -Arguments $scpArgs -TimeoutSec $TimeoutSec
}

function ConvertTo-MikrusShellSingleQuoted {
    # Cytuje ciag do bezpiecznego wstawienia w apostrofy w bashu. Apostrof zamykamy,
    # wstawiamy escapowany i otwieramy z powrotem ('\''), bo bash nie zna escape'ow
    # WEWNATRZ apostrofow. Bez tego sciezka lub komenda z ' rozwala zdalny skrypt.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return "'" + ($Text -replace "'", "'\''") + "'"
}

function ConvertTo-MikrusLfText {
    # Normalizuje zakonczenia linii do LF. KAZDY skrypt budowany dla zdalnego basha
    # musi przez to przejsc: pliki tego repo maja CRLF, wiec here-stringi PowerShella
    # przenosza \r do skryptu, a bash doklada go do ostatniego argumentu w linii
    # (`set -e<CR>` -> "invalid option", `"$HOME/.mikrus"<CR>` -> katalog z CR w nazwie).
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return ($Text -replace "`r`n", "`n") -replace "`r", "`n"
}

function New-MikrusHereDocDelimiter {
    # Dobiera ogranicznik heredoca, ktorego NIE ma w tresci — inaczej plik urwie sie
    # w losowym miejscu, a reszta poleci do shella jako komendy.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Content)
    $delimiter = 'MIKRUS_EOF'
    $suffix = 0
    while ($Content -match "(?m)^\s*$delimiter\s*$") {
        $suffix++
        $delimiter = "MIKRUS_EOF_$suffix"
    }
    return $delimiter
}

function New-MikrusRemoteWriteScript {
    # Buduje skrypt bash zapisujacy plik na serwerze przez heredoc. Alternatywa dla SCP,
    # gdy plik powstaje w locie (nie ma go lokalnie) albo scp jest niedostepny.
    param(
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [ValidatePattern('^[0-7]{3,4}$')][string]$Mode
    )
    # LF i dokladnie jeden koncowy newline: CRLF z Windows psuje shebang i skrypty bash,
    # a nadmiarowy newline na koncu rozjezdza md5 wzgledem kopii lokalnej.
    $body = (ConvertTo-MikrusLfText -Text $Content).TrimEnd("`n")
    $delimiter = New-MikrusHereDocDelimiter -Content $body
    $quotedPath = ConvertTo-MikrusShellSingleQuoted -Text $Remote
    $lines = @(
        'set -e'
        "mkdir -p `"`$(dirname $quotedPath)`""
        "cat > $quotedPath <<'$delimiter'"
        $body
        $delimiter
    )
    if ($Mode) { $lines += "chmod $Mode $quotedPath" }
    # md5 na koncu pozwala wolajacemu porownac zapis z oryginalem bez dodatkowej rundy.
    $lines += "md5sum $quotedPath"
    return ($lines -join "`n")
}

function Set-MikrusRemoteFile {
    [CmdletBinding(DefaultParameterSetName = 'FromFile')]
    param(
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory, ParameterSetName = 'FromFile')][string]$Local,
        [Parameter(Mandatory, ParameterSetName = 'FromContent')][AllowEmptyString()][string]$Content,
        [ValidatePattern('^[0-7]{3,4}$')][string]$Mode,
        $Config,
        [int]$TimeoutSec,
        [switch]$DryRun
    )
    if ($PSCmdlet.ParameterSetName -eq 'FromFile') {
        if (-not (Test-Path -Path $Local)) { throw "Brak pliku lokalnego: $Local" }
        $Content = Get-Content -Raw -Path $Local
    }
    if ($null -eq $Content) { $Content = '' }
    # -Mode przekazujemy tylko gdy podany: pusty ciag odbilby sie od ValidatePattern.
    $writeArgs = @{ Remote = $Remote; Content = $Content }
    if ($Mode) { $writeArgs['Mode'] = $Mode }
    $script = New-MikrusRemoteWriteScript @writeArgs
    return Invoke-MikrusSSH -Command $script -Config $Config -TimeoutSec $TimeoutSec -DryRun:$DryRun
}

function New-MikrusCronEntry {
    # Waliduje harmonogram i sklada linie wpisu crontaba (komentarz + wpis).
    param(
        [Parameter(Mandatory)][string]$Schedule,
        [Parameter(Mandatory)][string]$Command,
        [string]$Comment
    )
    $schedule = $Schedule.Trim()
    $isSpecial = $schedule -match '^@(reboot|yearly|annually|monthly|weekly|daily|midnight|hourly)$'
    $fields = @($schedule -split '\s+' | Where-Object { $_ })
    if (-not $isSpecial -and $fields.Count -ne 5) {
        throw "Niepoprawny harmonogram cron: '$Schedule'. Oczekiwano 5 pol (min godz dzien miesiac dzien_tygodnia) albo @daily/@reboot."
    }
    if ($Command -match "[`r`n]") {
        throw 'Komenda crona nie moze zawierac znaku nowej linii — crontab traktuje kazda linie osobno.'
    }
    if ([string]::IsNullOrWhiteSpace($Command)) {
        throw 'Komenda crona nie moze byc pusta.'
    }
    $entry = "$schedule $($Command.Trim())"
    $lines = @()
    foreach ($line in @($Comment -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $lines += "# $($line.Trim().TrimStart('#').Trim())"
    }
    $lines += $entry
    return [pscustomobject]@{
        Entry = $entry
        Lines = $lines
        Text  = ($lines -join "`n")
    }
}

# Backupy crontaba trafiaja obok konfiguracji, a nie do /tmp — maja przezyc restart
# kontenera, bo to jedyny slad stanu sprzed zmiany.
$script:MikrusCronBackupDir = '$HOME/.mikrus'

function New-MikrusCronAddScript {
    # Skrypt bash: backup crontaba -> sprawdzenie duplikatu -> dopisanie wpisu.
    # Idempotentny: identyczny wpis nie zostaje dodany drugi raz.
    param(
        [Parameter(Mandatory)]$CronEntry
    )
    $quotedEntry = ConvertTo-MikrusShellSingleQuoted -Text $CronEntry.Entry
    $printfArgs = ($CronEntry.Lines | ForEach-Object { ConvertTo-MikrusShellSingleQuoted -Text $_ }) -join ' '
    $tail = $CronEntry.Lines.Count + 1
    return ConvertTo-MikrusLfText -Text @"
set -e
mkdir -p "$($script:MikrusCronBackupDir)"
CUR="`$(crontab -l 2>/dev/null || true)"
BAK="$($script:MikrusCronBackupDir)/crontab.bak-`$(date +%Y%m%d-%H%M%S)"
printf '%s\n' "`$CUR" > "`$BAK"
if printf '%s\n' "`$CUR" | grep -qxF $quotedEntry; then
  echo "MIKRUS-CRON: wpis juz istnieje — bez zmian."
  exit 0
fi
printf '%s\n' "`$CUR" '' $printfArgs | crontab -
echo "MIKRUS-CRON: dodano wpis (backup: `$BAK)."
crontab -l | tail -n $tail
"@
}

function New-MikrusCronRemoveScript {
    # Skrypt bash: backup crontaba -> usuniecie linii ZAWIERAJACYCH podany ciag
    # WRAZ z blokiem komentarza tuz nad nimi i pojedyncza pusta linia separatora.
    # Bez tego po usunieciu wpisu w crontabie zostaja osierocone komentarze.
    # Dopasowanie doslowne (awk index), nie regexowe — wzorzec ma byc przewidywalny.
    # Wzorzec idzie przez ENVIRON, bo `awk -v` interpretowaloby sekwencje `\`.
    param(
        [Parameter(Mandatory)][string]$Match
    )
    if ([string]::IsNullOrWhiteSpace($Match)) {
        throw 'Wzorzec usuwania nie moze byc pusty — skasowalby caly crontab.'
    }
    $quotedMatch = ConvertTo-MikrusShellSingleQuoted -Text $Match
    return ConvertTo-MikrusLfText -Text @"
set -e
mkdir -p "$($script:MikrusCronBackupDir)"
CUR="`$(crontab -l 2>/dev/null || true)"
BAK="$($script:MikrusCronBackupDir)/crontab.bak-`$(date +%Y%m%d-%H%M%S)"
printf '%s\n' "`$CUR" > "`$BAK"
NEW="`$(printf '%s\n' "`$CUR" | MIKRUS_CRON_PATTERN=$quotedMatch awk '
BEGIN { pat = ENVIRON["MIKRUS_CRON_PATTERN"] }
{ lines[++n] = `$0 }
END {
  for (i = 1; i <= n; i++) {
    if (index(lines[i], pat) == 0) continue
    del[i] = 1
    j = i - 1
    while (j >= 1 && lines[j] ~ /^[[:space:]]*#/) { del[j] = 1; j-- }
    if (j >= 1 && lines[j] ~ /^[[:space:]]*`$/) del[j] = 1
  }
  for (i = 1; i <= n; i++) if (!(i in del)) print lines[i]
}')"
if [ "`$CUR" = "`$NEW" ]; then
  echo "MIKRUS-CRON: nic nie pasuje do wzorca — bez zmian."
  exit 0
fi
printf '%s\n' "`$NEW" | crontab -
echo "MIKRUS-CRON: usunieto wpisy pasujace do wzorca wraz z komentarzem (backup: `$BAK)."
crontab -l
"@
}

function Get-MikrusCron {
    [CmdletBinding()]
    param(
        $Config,
        [int]$TimeoutSec,
        [switch]$DryRun
    )
    return Invoke-MikrusSSH -Command 'crontab -l' -Config $Config -TimeoutSec $TimeoutSec -DryRun:$DryRun
}

function Add-MikrusCronEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Schedule,
        [Parameter(Mandatory)][string]$Command,
        [string]$Comment,
        $Config,
        [int]$TimeoutSec,
        [switch]$DryRun
    )
    $cronEntry = New-MikrusCronEntry -Schedule $Schedule -Command $Command -Comment $Comment
    $script = New-MikrusCronAddScript -CronEntry $cronEntry
    return Invoke-MikrusSSH -Command $script -Config $Config -TimeoutSec $TimeoutSec -DryRun:$DryRun
}

function Remove-MikrusCronEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Match,
        $Config,
        [int]$TimeoutSec,
        [switch]$DryRun
    )
    $script = New-MikrusCronRemoveScript -Match $Match
    return Invoke-MikrusSSH -Command $script -Config $Config -TimeoutSec $TimeoutSec -DryRun:$DryRun
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

function New-MikrusCurlArgs {
    # Buduje argumenty curl BEZ klucza API. Klucz idzie przez stdin (-K -),
    # by nie pojawil sie w linii polecen procesu. Wartosci pol kodowane (--data-urlencode).
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Fields
    )
    $curlArgs = @('-s', '-X', 'POST', '-K', '-', $Url)
    foreach ($k in $Fields.Keys) {
        $curlArgs += @('--data-urlencode', "$k=$($Fields[$k])")
    }
    return $curlArgs
}

function New-MikrusCurlConfig {
    # Plik konfiguracyjny curl (przekazywany przez stdin) z naglowkiem autoryzacji.
    param(
        [Parameter(Mandatory)][string]$ApiKey
    )
    return "header = `"Authorization: $ApiKey`""
}

function Invoke-MikrusCurl {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][hashtable]$Fields,
        [Parameter(Mandatory)][string]$ApiKey
    )
    $curlArgs = New-MikrusCurlArgs -Url $Url -Fields $Fields
    $config   = New-MikrusCurlConfig -ApiKey $ApiKey
    return ($config | & curl.exe @curlArgs)
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
