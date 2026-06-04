---
name: mikrus-files
description: Use when transferring files to or from the Mikrus VPS over SCP — uploading a file/directory to the server or downloading from it. Triggers: "wyślij plik na Mikrusa", "pobierz plik z serwera", "skopiuj katalog na mikrus".
---

# mikrus-files

Przesyła pliki między komputerem lokalnym a serwerem Mikrus przez SCP.

## Użycie

```powershell
Import-Module "C:\claude\mikrus-plugin\lib\mikrus.psm1" -Force

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
