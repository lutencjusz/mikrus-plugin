# Plugin `mikrus` — plan implementacji

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zbudować plugin Claude Code `mikrus` z 4 skillami (setup, terminal, files, api) opartymi o wspólny moduł PowerShell obsługujący serwer VPS Mikrus przez SSH/SCP i API.

**Architecture:** Wspólny moduł `lib/mikrus.psm1` dostarcza funkcje: czyste buildery argumentów (`New-MikrusSSHArgs`, `New-MikrusScpArgs`, `New-MikrusApiRequest`) testowane bez sieci oraz cienkie funkcje wykonawcze (`Invoke-MikrusSSH`, `Send/Get-MikrusFile`, `Invoke-MikrusApi`) wywołujące `ssh`/`scp`/`curl`. `Invoke-MikrusCurl` to izolowany szew mockowany w testach API. Konfiguracja czytana z `~/.mikrus/config.json` przez `Get-MikrusConfig`. Cztery pliki `SKILL.md` to cienkie warstwy opisujące, kiedy i jak użyć funkcji modułu.

**Tech Stack:** PowerShell 7 (pwsh), OpenSSH (`ssh`/`scp`), `curl`, Pester 5 (testy). Windows 11.

---

## Struktura plików

| Plik | Odpowiedzialność |
|---|---|
| `.claude-plugin/plugin.json` | Manifest pluginu (nazwa, wersja, opis). |
| `lib/mikrus.psm1` | Cała logika: config, buildery, wykonanie SSH/SCP/API. |
| `tests/mikrus.Tests.ps1` | Testy Pester modułu (offline, mockowane). |
| `skills/mikrus-setup/SKILL.md` | Konfiguracja + test połączenia. |
| `skills/mikrus-terminal/SKILL.md` | Komendy przez SSH. |
| `skills/mikrus-files/SKILL.md` | Transfer plików (SCP). |
| `skills/mikrus-api/SKILL.md` | Operacje przez API. |
| `README.md` | Instalacja, konfiguracja, ostrzeżenia bezpieczeństwa. |
| `.gitignore` | Już istnieje — chroni config/sekrety. |

**Konwencja modułu:** brak `Export-ModuleMember` → wszystkie funkcje eksportowane domyślnie (buildery są celowo dostępne i testowalne). Każdy task dopisuje swoją funkcję do `lib/mikrus.psm1` i blok `Describe` do `tests/mikrus.Tests.ps1`.

Każdy test importuje moduł na górze pliku:
```powershell
Import-Module "$PSScriptRoot/../lib/mikrus.psm1" -Force
```

---

## Task 1: Szkielet pluginu i środowisko testowe

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `lib/mikrus.psm1`
- Create: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Sprawdź dostępność Pester 5**

Run:
```powershell
pwsh -NoProfile -Command "(Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1).Version"
```
Expected: wersja `5.x.x`. Jeśli niższa niż 5 lub brak — zainstaluj:
```powershell
pwsh -NoProfile -Command "Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0 -Force -SkipPublisherCheck"
```

- [ ] **Step 2: Utwórz manifest pluginu**

Create `.claude-plugin/plugin.json`:
```json
{
  "name": "mikrus",
  "version": "0.1.0",
  "description": "Obsługa serwera VPS Mikrus: komendy przez SSH, transfer plików (SCP) i operacje przez API mikr.us.",
  "author": {
    "name": "micha"
  },
  "keywords": ["mikrus", "vps", "ssh", "scp", "api", "devops"]
}
```

- [ ] **Step 3: Utwórz pusty moduł z nagłówkiem**

Create `lib/mikrus.psm1`:
```powershell
# Moduł obsługi serwera VPS Mikrus.
# Funkcje publiczne (buildery + wykonanie) eksportowane domyślnie.
# Konfiguracja: ~/.mikrus/config.json (patrz skill mikrus-setup).

Set-StrictMode -Version Latest
```

- [ ] **Step 4: Utwórz plik testów z importem modułu**

Create `tests/mikrus.Tests.ps1`:
```powershell
Import-Module "$PSScriptRoot/../lib/mikrus.psm1" -Force

Describe 'Modul mikrus laduje sie' {
    It 'importuje sie bez bledu' {
        Get-Module mikrus | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 5: Uruchom testy — weryfikacja szkieletu**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS (1 test) — `Modul mikrus laduje sie`.

- [ ] **Step 6: Commit**

```powershell
git add .claude-plugin/plugin.json lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "Szkielet pluginu mikrus: manifest, modul, testy"
```

---

## Task 2: `Get-MikrusConfig` — wczytywanie i walidacja konfiguracji

**Files:**
- Modify: `lib/mikrus.psm1`
- Modify: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Napisz failing testy**

Dopisz do `tests/mikrus.Tests.ps1`:
```powershell
Describe 'Get-MikrusConfig' {
    BeforeAll {
        $script:validCfg = @{
            srv = 'a123'; host = 'srv03.mikr.us'; sshPort = 10123; user = 'root'
            identityFile = 'C:\keys\mikrus_ed25519'; apiKey = 'SECRET'; apiBase = 'https://api.mikr.us'
        }
    }

    It 'wczytuje poprawny config z pliku' {
        $path = Join-Path $TestDrive 'config.json'
        $script:validCfg | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        $cfg = Get-MikrusConfig -Path $path
        $cfg.host | Should -Be 'srv03.mikr.us'
        $cfg.sshPort | Should -Be 10123
    }

    It 'rzuca blad z instrukcja mikrus-setup gdy brak pliku' {
        $path = Join-Path $TestDrive 'nieistnieje.json'
        { Get-MikrusConfig -Path $path } | Should -Throw -ExpectedMessage '*mikrus-setup*'
    }

    It 'rzuca blad gdy brakuje wymaganego pola' {
        $path = Join-Path $TestDrive 'incomplete.json'
        $incomplete = $script:validCfg.Clone(); $incomplete.Remove('apiKey')
        $incomplete | ConvertTo-Json | Set-Content -Path $path -Encoding utf8
        { Get-MikrusConfig -Path $path } | Should -Throw -ExpectedMessage '*apiKey*'
    }
}
```

- [ ] **Step 2: Uruchom — testy mają failować**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: FAIL — `Get-MikrusConfig` nie istnieje (`CommandNotFoundException`).

- [ ] **Step 3: Zaimplementuj `Get-MikrusConfig`**

Dopisz do `lib/mikrus.psm1`:
```powershell
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
```

- [ ] **Step 4: Uruchom — testy mają przejść**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS (wszystkie testy `Get-MikrusConfig`).

- [ ] **Step 5: Commit**

```powershell
git add lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "Get-MikrusConfig: wczytywanie i walidacja konfiguracji"
```

---

## Task 3: SSH — `New-MikrusSSHArgs` + `Invoke-MikrusSSH`

**Files:**
- Modify: `lib/mikrus.psm1`
- Modify: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Napisz failing test buildera**

Dopisz do `tests/mikrus.Tests.ps1`:
```powershell
Describe 'New-MikrusSSHArgs' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'buduje argumenty ssh z portem, kluczem i BatchMode' {
        $a = New-MikrusSSHArgs -Config $script:cfg -Command 'echo ok'
        $a | Should -Be @('-p','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes','root@srv03.mikr.us','echo ok')
    }
}

Describe 'Invoke-MikrusSSH -DryRun' {
    It 'zwraca pelna komende ssh bez wykonania' {
        $cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
        $cmd = Invoke-MikrusSSH -Command 'uptime' -Config $cfg -DryRun
        $cmd[0] | Should -Be 'ssh'
        $cmd | Should -Contain 'root@srv03.mikr.us'
        $cmd[-1] | Should -Be 'uptime'
    }
}
```

- [ ] **Step 2: Uruchom — failuje**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: FAIL — `New-MikrusSSHArgs` / `Invoke-MikrusSSH` nie istnieją.

- [ ] **Step 3: Zaimplementuj funkcje**

Dopisz do `lib/mikrus.psm1`:
```powershell
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
```

- [ ] **Step 4: Uruchom — przechodzi**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS (testy SSH).

- [ ] **Step 5: Commit**

```powershell
git add lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "SSH: New-MikrusSSHArgs i Invoke-MikrusSSH"
```

---

## Task 4: SCP — `New-MikrusScpArgs` + `Send-MikrusFile` / `Get-MikrusFile`

**Files:**
- Modify: `lib/mikrus.psm1`
- Modify: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Napisz failing testy**

Dopisz do `tests/mikrus.Tests.ps1`:
```powershell
Describe 'New-MikrusScpArgs' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'upload: lokalny przed zdalnym, port wielka P' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction up -Local 'C:\plik.txt' -Remote '/root/plik.txt'
        $a | Should -Be @('-P','10123','-i','C:\keys\mikrus_ed25519','-o','BatchMode=yes','C:\plik.txt','root@srv03.mikr.us:/root/plik.txt')
    }

    It 'download: zdalny przed lokalnym' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction down -Local 'C:\plik.txt' -Remote '/root/plik.txt'
        $a[-2] | Should -Be 'root@srv03.mikr.us:/root/plik.txt'
        $a[-1] | Should -Be 'C:\plik.txt'
    }

    It 'dodaje -r dla katalogow' {
        $a = New-MikrusScpArgs -Config $script:cfg -Direction up -Local 'C:\dir' -Remote '/root/dir' -Recurse
        $a | Should -Contain '-r'
    }
}

Describe 'Send-MikrusFile -DryRun' {
    It 'zwraca komende scp upload' {
        $cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
        $cmd = Send-MikrusFile -Local 'C:\plik.txt' -Remote '/root/plik.txt' -Config $cfg -DryRun
        $cmd[0] | Should -Be 'scp'
        $cmd[-1] | Should -Be 'root@srv03.mikr.us:/root/plik.txt'
    }
}
```

- [ ] **Step 2: Uruchom — failuje**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: FAIL — funkcje SCP nie istnieją.

- [ ] **Step 3: Zaimplementuj funkcje**

Dopisz do `lib/mikrus.psm1`:
```powershell
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
```

- [ ] **Step 4: Uruchom — przechodzi**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS (testy SCP).

- [ ] **Step 5: Commit**

```powershell
git add lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "SCP: New-MikrusScpArgs, Send-MikrusFile, Get-MikrusFile"
```

---

## Task 5: API — `New-MikrusApiRequest` (budowanie żądania)

**Files:**
- Modify: `lib/mikrus.psm1`
- Modify: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Napisz failing testy**

Dopisz do `tests/mikrus.Tests.ps1`:
```powershell
Describe 'New-MikrusApiRequest' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'buduje URL z apiBase i endpointu oraz dodaje srv' {
        $r = New-MikrusApiRequest -Config $script:cfg -Endpoint '/info'
        $r.Url | Should -Be 'https://api.mikr.us/info'
        $r.Fields['srv'] | Should -Be 'a123'
    }

    It 'normalizuje ukosniki (brak podwojnego /)' {
        $cfg2 = $script:cfg.PSObject.Copy(); $cfg2.apiBase = 'https://api.mikr.us/'
        $r = New-MikrusApiRequest -Config $cfg2 -Endpoint 'stats'
        $r.Url | Should -Be 'https://api.mikr.us/stats'
    }

    It 'dolacza dodatkowe pola z Body (np. domain/port)' {
        $r = New-MikrusApiRequest -Config $script:cfg -Endpoint '/domain' -Body @{ port='30123'; domain='example.com' }
        $r.Fields['port'] | Should -Be '30123'
        $r.Fields['domain'] | Should -Be 'example.com'
        $r.Fields['srv'] | Should -Be 'a123'
    }
}
```

- [ ] **Step 2: Uruchom — failuje**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: FAIL — `New-MikrusApiRequest` nie istnieje.

- [ ] **Step 3: Zaimplementuj funkcję**

Dopisz do `lib/mikrus.psm1`:
```powershell
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
```

- [ ] **Step 4: Uruchom — przechodzi**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS (testy `New-MikrusApiRequest`).

- [ ] **Step 5: Commit**

```powershell
git add lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "API: New-MikrusApiRequest buduje URL i pola zadania"
```

---

## Task 6: API — `Invoke-MikrusCurl` + `Invoke-MikrusApi` (wykonanie + parsowanie)

**Files:**
- Modify: `lib/mikrus.psm1`
- Modify: `tests/mikrus.Tests.ps1`

- [ ] **Step 1: Napisz failing testy z mockiem `Invoke-MikrusCurl`**

Dopisz do `tests/mikrus.Tests.ps1`:
```powershell
Describe 'Invoke-MikrusApi' {
    BeforeAll {
        $script:cfg = [pscustomobject]@{
            srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
            identityFile='C:\keys\mikrus_ed25519'; apiKey='SECRET'; apiBase='https://api.mikr.us'
        }
    }

    It 'parsuje poprawny JSON na obiekt' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '{"server_id":"a123","status":"running"}' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            $r = Invoke-MikrusApi -Endpoint '/info' -Config $cfg
            $r.server_id | Should -Be 'a123'
            $r.status | Should -Be 'running'
        }
    }

    It 'rzuca czytelny blad gdy API zwraca pole error' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '{"error":"nieprawidlowy klucz"}' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            { Invoke-MikrusApi -Endpoint '/info' -Config $cfg } | Should -Throw -ExpectedMessage '*nieprawidlowy klucz*'
        }
    }

    It 'rzuca blad gdy odpowiedz nie jest JSON-em' {
        InModuleScope mikrus {
            Mock Invoke-MikrusCurl { '<html>502 Bad Gateway</html>' }
            $cfg = [pscustomobject]@{ srv='a123'; host='h'; sshPort=10123; user='root'; identityFile='k'; apiKey='SECRET'; apiBase='https://api.mikr.us' }
            { Invoke-MikrusApi -Endpoint '/info' -Config $cfg } | Should -Throw -ExpectedMessage '*Niepoprawna odpowiedz*'
        }
    }
}
```

- [ ] **Step 2: Uruchom — failuje**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: FAIL — `Invoke-MikrusApi` / `Invoke-MikrusCurl` nie istnieją.

- [ ] **Step 3: Zaimplementuj funkcje**

Dopisz do `lib/mikrus.psm1`:
```powershell
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
    if ($data.PSObject.Properties.Name -contains 'error') {
        throw "API Mikrus zwrocilo blad ($Endpoint): $($data.error)"
    }
    return $data
}
```

- [ ] **Step 4: Uruchom — przechodzi (cały zestaw)**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS — wszystkie testy modułu (config, SSH, SCP, API).

- [ ] **Step 5: Commit**

```powershell
git add lib/mikrus.psm1 tests/mikrus.Tests.ps1
git commit -m "API: Invoke-MikrusCurl i Invoke-MikrusApi z parsowaniem i obsluga bledow"
```

---

## Task 7: Skill `mikrus-setup`

**Files:**
- Create: `skills/mikrus-setup/SKILL.md`

- [ ] **Step 1: Utwórz SKILL.md**

Create `skills/mikrus-setup/SKILL.md`:
```markdown
---
name: mikrus-setup
description: Use when configuring the Mikrus VPS connection or testing it — creating ~/.mikrus/config.json, computing the SSH port from the machine number, or verifying that API and SSH work. Triggers: "skonfiguruj Mikrus", "połącz z Mikrusem", "sprawdź połączenie z serwerem", "test mikrus".
---

# mikrus-setup

Konfiguruje połączenie z serwerem VPS Mikrus i testuje je.

## Konfiguracja docelowa

Plik `C:\Users\micha\.mikrus\config.json` (poza repozytorium pluginu):

| Pole | Znaczenie | Źródło |
|------|-----------|--------|
| `srv` | nazwa serwera (np. `a123`) | panel / mail powitalny |
| `host` | host SSH (np. `srv03.mikr.us`) | mail powitalny |
| `sshPort` | port SSH = 10000 + numer maszyny | wyliczany |
| `user` | `root` | stałe |
| `identityFile` | ścieżka do prywatnego klucza SSH | użytkownik |
| `apiKey` | klucz API | https://mikr.us/panel/?a=api |
| `apiBase` | `https://api.mikr.us` | stałe |

## Procedura

1. Zapytaj użytkownika o: numer maszyny, host, nazwę serwera (`srv`), ścieżkę do klucza prywatnego, klucz API.
2. Wylicz `sshPort = 10000 + numer maszyny`. Potwierdź wynik z użytkownikiem.
3. Zaimportuj moduł i zapisz konfigurację:
   ```powershell
   Import-Module "<katalog-pluginu>/lib/mikrus.psm1" -Force
   $dir = Join-Path $HOME '.mikrus'
   if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
   @{
     srv='a123'; host='srv03.mikr.us'; sshPort=10123; user='root'
     identityFile='C:\Users\micha\.ssh\mikrus_ed25519'
     apiKey='WKLEJ_KLUCZ'; apiBase='https://api.mikr.us'
   } | ConvertTo-Json | Set-Content -Path (Join-Path $dir 'config.json') -Encoding utf8
   ```
4. Jeśli klucz publiczny nie jest jeszcze na serwerze, poinstruuj użytkownika, by go wgrał (np. przez panel Mikrus lub `ssh-copy-id`-odpowiednik); bez tego logowanie kluczem nie zadziała.
5. Test połączenia:
   ```powershell
   $cfg = Get-MikrusConfig
   "API /info:";  Invoke-MikrusApi -Endpoint '/info' -Config $cfg
   "SSH echo:";   (Invoke-MikrusSSH -Command 'echo ok' -Config $cfg).Output
   ```
6. Raportuj wynik: co działa (API / SSH), a co wymaga poprawy (np. brak klucza na serwerze, zły `apiKey`).

## Uwagi
- Nigdy nie wypisuj `apiKey` w odpowiedzi do użytkownika ani nie commituj `config.json`.
- Port 22 jest zablokowany po nieudanych próbach — używamy wyłącznie portu `sshPort` i klucza.
```

- [ ] **Step 2: Commit**

```powershell
git add skills/mikrus-setup/SKILL.md
git commit -m "Skill mikrus-setup: konfiguracja i test polaczenia"
```

---

## Task 8: Skill `mikrus-terminal`

**Files:**
- Create: `skills/mikrus-terminal/SKILL.md`

- [ ] **Step 1: Utwórz SKILL.md**

Create `skills/mikrus-terminal/SKILL.md`:
```markdown
---
name: mikrus-terminal
description: Use when running shell commands on the Mikrus VPS over SSH — checking status, inspecting files/logs, managing services or packages on the server. Triggers: "wykonaj na Mikrusie", "uruchom komendę na serwerze", "sprawdź df -h na mikrusie", "restartuj usługę na serwerze".
---

# mikrus-terminal

Wykonuje komendy na serwerze Mikrus przez SSH (pełny shell roota, bez limitu 60 s API).

## Użycie

```powershell
Import-Module "<katalog-pluginu>/lib/mikrus.psm1" -Force
$wynik = Invoke-MikrusSSH -Command 'df -h'
$wynik.Output
$wynik.ExitCode   # 0 = sukces
```

Aby tylko podejrzeć złożoną komendę bez wykonania, użyj `-DryRun`.

## Zasady
- **Polecenia destrukcyjne** (`rm -rf`, `reboot`, zatrzymywanie/usuwanie usług, nadpisywanie plików) — najpierw pokaż użytkownikowi dokładną komendę i poproś o potwierdzenie, dopiero potem wykonaj.
- Po wykonaniu sprawdzaj `ExitCode`; przy ≠ 0 pokaż `Output` i wyjaśnij błąd.
- Dla zadań długich (>60 s) to jest właściwy kanał (API `/exec` ma limit 60 s — patrz skill mikrus-api).
- Jeśli `Get-MikrusConfig` zgłosi brak konfiguracji — odeślij do skilla mikrus-setup.
```

- [ ] **Step 2: Commit**

```powershell
git add skills/mikrus-terminal/SKILL.md
git commit -m "Skill mikrus-terminal: komendy przez SSH"
```

---

## Task 9: Skill `mikrus-files`

**Files:**
- Create: `skills/mikrus-files/SKILL.md`

- [ ] **Step 1: Utwórz SKILL.md**

Create `skills/mikrus-files/SKILL.md`:
```markdown
---
name: mikrus-files
description: Use when transferring files to or from the Mikrus VPS over SCP — uploading a file/directory to the server or downloading from it. Triggers: "wyślij plik na Mikrusa", "pobierz plik z serwera", "skopiuj katalog na mikrus".
---

# mikrus-files

Przesyła pliki między komputerem lokalnym a serwerem Mikrus przez SCP.

## Użycie

```powershell
Import-Module "<katalog-pluginu>/lib/mikrus.psm1" -Force

# Wysłanie pliku na serwer
Send-MikrusFile -Local 'C:\dane\backup.zip' -Remote '/root/backup.zip'

# Pobranie pliku z serwera
Get-MikrusFile -Remote '/root/log.txt' -Local 'C:\dane\log.txt'

# Katalog (rekurencyjnie)
Send-MikrusFile -Local 'C:\projekt' -Remote '/root/projekt' -Recurse
```

Aby podejrzeć komendę bez wykonania — `-DryRun`.

## Zasady
- Sprawdzaj `ExitCode` zwracanego obiektu; przy ≠ 0 pokaż `Output`.
- Dla katalogów zawsze `-Recurse`.
- Alternatywa dla dużych/ręcznych transferów: panel Mikrus → katalog `/drop` (pliki do 100 MB). Wspomnij o niej, gdy SCP zawiedzie lub plik jest duży.
- Brak konfiguracji → odeślij do skilla mikrus-setup.
```

- [ ] **Step 2: Commit**

```powershell
git add skills/mikrus-files/SKILL.md
git commit -m "Skill mikrus-files: transfer plikow przez SCP"
```

---

## Task 10: Skill `mikrus-api`

**Files:**
- Create: `skills/mikrus-api/SKILL.md`

- [ ] **Step 1: Utwórz SKILL.md**

Create `skills/mikrus-api/SKILL.md`:
```markdown
---
name: mikrus-api
description: Use when performing Mikrus operations through the API (api.mikr.us) — server info, stats, ports, database credentials, logs, restart, amfetamina boost, quick exec, cloud, or assigning a domain. Triggers: "info o serwerze mikrus", "statystyki mikrus", "restart przez API", "dane do bazy mikrus", "porty mikrus", "amfetamina", "logi mikrus", "dodaj domenę".
---

# mikrus-api

Wykonuje operacje na serwerze Mikrus przez API `https://api.mikr.us`.

## Użycie

```powershell
Import-Module "<katalog-pluginu>/lib/mikrus.psm1" -Force
Invoke-MikrusApi -Endpoint '/info'
```

## Endpointy

| Endpoint | Działanie | Pola `-Body` |
|----------|-----------|--------------|
| `/info` | informacje o serwerze | — |
| `/serwery` | lista serwerów użytkownika | — |
| `/stats` | dysk, pamięć, uptime | — |
| `/porty` | przypisane porty TCP/UDP | — |
| `/db` | dane dostępowe do bazy | — |
| `/logs` | ostatnie 10 wpisów logu | — |
| `/logs/ID` | konkretny wpis logu | — (ID w endpoincie) |
| `/restart` | restart serwera | — |
| `/amfetamina` | dopalenie parametrów serwera | — |
| `/exec` | szybka komenda (limit 60 s) | `@{ cmd = '...' }` |
| `/cloud` | usługi cloud + statystyki | — |
| `/domain` | przypisanie domeny | `@{ port='30123'; domain='example.com' }` |

Przykłady z parametrami:
```powershell
Invoke-MikrusApi -Endpoint '/exec' -Body @{ cmd = 'uptime' }
Invoke-MikrusApi -Endpoint '/domain' -Body @{ port = '30123'; domain = 'example.com' }
Invoke-MikrusApi -Endpoint '/logs/42'
```

## Zasady
- Funkcja zwraca sparsowany obiekt JSON — przedstaw dane czytelnie, nie surowym dumpem.
- Błędy API (pole `error`, brak/niepoprawna odpowiedź) są zgłaszane jako wyjątek z czytelnym komunikatem — pokaż go użytkownikowi.
- `/exec` ma limit **60 s** — dla dłuższych zadań użyj skilla mikrus-terminal (SSH).
- `/restart` i `/amfetamina` zmieniają stan serwera — potwierdź z użytkownikiem przed wywołaniem.
- Nigdy nie wypisuj `apiKey`. Dane z `/db` traktuj jako wrażliwe.
- Brak konfiguracji → odeślij do skilla mikrus-setup.
```

- [ ] **Step 2: Commit**

```powershell
git add skills/mikrus-api/SKILL.md
git commit -m "Skill mikrus-api: operacje przez API mikr.us"
```

---

## Task 11: README i finalna weryfikacja

**Files:**
- Create: `README.md`

- [ ] **Step 1: Utwórz README**

Create `README.md`:
```markdown
# Plugin `mikrus`

Skille Claude Code do obsługi serwera VPS [Mikrus](https://mikr.us): komendy przez SSH, transfer plików (SCP) i operacje przez API `api.mikr.us`.

## Skille
- **mikrus-setup** — konfiguracja połączenia i test (`~/.mikrus/config.json`).
- **mikrus-terminal** — wykonywanie komend przez SSH.
- **mikrus-files** — transfer plików przez SCP.
- **mikrus-api** — operacje przez API (info, stats, porty, db, logi, restart, domain…).

## Wymagania
- Windows z PowerShell 7 (`pwsh`), OpenSSH (`ssh`/`scp`), `curl`.
- Klucz SSH wgrany na serwer Mikrus.
- Klucz API z https://mikr.us/panel/?a=api

## Konfiguracja
Uruchom skill **mikrus-setup**, który utworzy `C:\Users\<user>\.mikrus\config.json`:
```json
{
  "srv": "a123",
  "host": "srv03.mikr.us",
  "sshPort": 10123,
  "user": "root",
  "identityFile": "C:\\Users\\micha\\.ssh\\mikrus_ed25519",
  "apiKey": "xxxxxxxx",
  "apiBase": "https://api.mikr.us"
}
```
`sshPort` = 10000 + numer maszyny.

## ⚠️ Bezpieczeństwo
- **Nie commituj** `config.json` ani kluczy — `.gitignore` chroni je w tym repo, ale plik konfiguracyjny i tak żyje poza repo (`~/.mikrus`).
- Logowanie wyłącznie kluczem SSH; nie używaj portu 22 (blokada IP po nieudanych próbach).
- Dane z API `/db` oraz `apiKey` są wrażliwe — nie udostępniaj ich w logach/odpowiedziach.

## Testy
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
```

- [ ] **Step 2: Uruchom pełny zestaw testów — finalna weryfikacja**

Run:
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
Expected: PASS — wszystkie testy modułu (config, SSH, SCP, API) zielone.

- [ ] **Step 3: Commit**

```powershell
git add README.md
git commit -m "README: instalacja, konfiguracja i bezpieczenstwo pluginu mikrus"
```

---

## Weryfikacja ręczna end-to-end (po implementacji, na realnym serwerze)

Nie część testów jednostkowych — wykonaj raz po wdrożeniu z prawdziwą konfiguracją:

1. Skill **mikrus-setup** → utworzenie configu, test API `/info` + SSH `echo ok`.
2. **mikrus-api**: `Invoke-MikrusApi -Endpoint '/stats'` → czytelne statystyki.
3. **mikrus-terminal**: `Invoke-MikrusSSH -Command 'uptime'` → poprawny output, ExitCode 0.
4. **mikrus-files**: wysłanie pliku testowego i pobranie go z powrotem; porównanie zawartości.
```
