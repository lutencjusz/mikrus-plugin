---
name: mikrus-files
description: 'Use when transferring files to or from the Mikrus VPS over SCP, or writing a file directly onto the server without a local copy — uploading a file/directory, downloading from it, or creating a remote script from generated content. Triggers: "wyślij plik na Mikrusa", "pobierz plik z serwera", "skopiuj katalog na mikrus", "utwórz skrypt na serwerze", "zapisz plik na Mikrusie".'
---

# mikrus-files

Przesyła pliki między komputerem lokalnym a serwerem Mikrus przez SCP.

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force

# Wysłanie pliku na serwer
Send-MikrusFile -Local 'C:\dane\backup.zip' -Remote '/root/backup.zip'

# Pobranie pliku z serwera
Get-MikrusFile -Remote '/root/log.txt' -Local 'C:\dane\log.txt'

# Katalog (rekurencyjnie)
Send-MikrusFile -Local 'C:\projekt' -Remote '/root/projekt' -Recurse
```

Aby podejrzeć komendę bez wykonania — `-DryRun`.

## Zapis pliku bez SCP (`Set-MikrusRemoteFile`)

Gdy plik powstaje **w locie** (skrypt generowany przez Claude, konfiguracja składana
z fragmentów) — nie ma sensu tworzyć kopii lokalnej tylko po to, żeby wysłać ją SCP.
`Set-MikrusRemoteFile` zapisuje treść przez SSH heredocem:

```powershell
# Treść prosto z pamięci + prawa wykonywania
Set-MikrusRemoteFile -Remote '/root/skrypty/nowy.sh' -Content $tresc -Mode 755

# Albo z pliku lokalnego (gdy scp niedostępny)
Set-MikrusRemoteFile -Remote '/root/skrypty/nowy.sh' -Local 'C:\tmp\nowy.sh'
```

Funkcja sama: tworzy katalog nadrzędny (`mkdir -p`), **normalizuje CRLF → LF**
(Windowsowe `\r` psuje shebang i skrypty bash), zostawia dokładnie jeden końcowy
newline i zwraca `md5sum` zapisanego pliku — porównaj go z lokalnym, żeby potwierdzić
zapis. Ogranicznik heredoca dobierany jest tak, by nie występował w treści.

> [!WARNING]
> **Nadpisuje bez pytania.** `Set-MikrusRemoteFile` działa jak `>` — istniejący plik przepada. Przed nadpisaniem
> czegoś ważnego zrób kopię (`cp plik plik.bak-$(date +%s)` przez mikrus-terminal)
> albo pokaż użytkownikowi `-DryRun`.

## Limit czasu (duże transfery)

`Send-MikrusFile` i `Get-MikrusFile` mają **twardy limit czasu** na cały proces scp
(domyślnie **180 s**). Po przekroczeniu transfer jest ubijany, a wynik ma
`ExitCode = 124` i `TimedOut = $true` — zamiast wisieć w nieskończoność przy zawieszonym
połączeniu. Dla **dużych plików/katalogów** podaj większy `-TimeoutSec`:

```powershell
Send-MikrusFile -Local 'C:\dane\backup.zip' -Remote '/root/backup.zip' -TimeoutSec 1200
```

Domyślne wartości limitów można nadpisać w `~/.mikrus/config.json` (pole `commandTimeout`
i opcje połączenia — patrz skill mikrus-terminal).

## Zasady
- Sprawdzaj `ExitCode` zwracanego obiektu; przy ≠ 0 pokaż `Output`. `ExitCode = 124` (`TimedOut`) = przekroczony limit czasu → zwiększ `-TimeoutSec` (duży plik) lub sprawdź połączenie.
- Dla katalogów zawsze `-Recurse`.
- Alternatywa dla dużych/ręcznych transferów: panel Mikrus → katalog `/drop` (pliki do 100 MB). Wspomnij o niej, gdy SCP zawiedzie lub plik jest duży.
- Brak konfiguracji → odeślij do skilla mikrus-setup.
