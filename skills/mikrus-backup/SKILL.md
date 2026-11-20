---
name: mikrus-backup
description: 'Use when backing up the Mikrus VPS to the "strych" backup storage — runs /root/skrypty/backup_strych.sh over SSH (two verified tar.gz archives: /root and system), optionally a dry list, and lists existing backups. Triggers: "zrób backup Mikrusa", "backup serwera na strych", "uruchom backup_strych", "backup mikrus", "jakie są kopie na strychu".'
---

# mikrus-backup

Uruchamia na Mikrusie skrypt `/root/skrypty/backup_strych.sh`, który streamuje `tar` wprost
na **strych** (osobny storage backupowy Mikrusa, `yasmin474@strych.mikr.us`, klucz
`/backup_key` na serwerze) i weryfikuje każde archiwum po stronie strycha (`gzip -t` + `tar tzf`).

Powstają dwa archiwa w `strych:~/backups/`:

| Archiwum | Zawartość |
|---|---|
| `mikrus_yasmin474_root_<RRRR-MM-DD>.tar.gz` | `/root` bez `/root/.cache` |
| `mikrus_yasmin474_system_<RRRR-MM-DD>.tar.gz` | `/usr/local/bin`, `/usr/local/sbin`, `/etc`, `/var/spool/cron` (do 2026-11-14 także `/home/openclaw` i kopie baz SQLite OpenClaw) |

Backup uruchamiany jest **ręcznie** — celowo nie jest w cronie. Archiwa są dopisywane
(nazwa z datą), więc nic nie nadpisuje poprzednich kopii; ponowny przebieg tego samego dnia
nadpisze tylko archiwa z tą samą datą. Skrypt zapisuje archiwa z prawami `600`
(`umask 077` + `chmod 600` po stronie strycha, od 2026-11-20) — zawierają sekrety.

## Użycie

Najpierw sprawdź połączenie i ewentualnie podejrzyj zakres (`--lista` nic nie wysyła,
tylko wypisuje pliki):

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force
$w = Invoke-MikrusSSH -Command 'bash /root/skrypty/backup_strych.sh --lista | tail -n 40' -TimeoutSec 600
$w.Output
```

Właściwy backup (długi — **wymagany duży `-TimeoutSec`**, domyślne 180 s nie wystarczy):

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force
$w = Invoke-MikrusSSH -Command 'bash /root/skrypty/backup_strych.sh' -TimeoutSec 1200
$w.Output
$w.ExitCode   # 0 = sukces
```

Lista kopii na strychu (i ich rozmiary):

```powershell
(Invoke-MikrusSSH -Command 'ssh -i /backup_key -o BatchMode=yes yasmin474@strych.mikr.us "ls -lh backups/"').Output
```

## Po wykonaniu
- `ExitCode = 0` i w wyjściu dwa komunikaty `OK - archiwum kompletne (<rozmiar>)` → backup udany; podaj użytkownikowi nazwy i rozmiary archiwów.
- `uwaga: czesc plikow zmienila sie w trakcie pakowania (tar kod 1)` → nieszkodliwe, archiwum i tak przeszło weryfikację.
- `BLAD - ...` (wysyłka, tar, archiwum uszkodzone) lub `ExitCode ≠ 0` → pokaż `Output` i wyjaśnij; nie zgłaszaj sukcesu.
- `ExitCode = 124` (`TimedOut`) → przekroczony limit czasu; skrypt na serwerze mógł zostać przerwany w połowie — sprawdź listę na strychu i powtórz z większym `-TimeoutSec`.
- Typowo (2026-11-20): `root` ~615 MB + `system` ~17 MB; archiwa z prawami `-rw-------`.

## Zasady
- Backup niczego nie usuwa na serwerze — można go uruchamiać bez dodatkowego potwierdzenia, gdy użytkownik o to prosi. **Nie kasuj** starych archiwów ze strycha bez wyraźnej zgody (pokaż listę i dokładną komendę).
- Nie ruszaj skryptu na serwerze w ramach tego skilla; jego kopia referencyjna i opis: `Google Keep/Informatyka/Daily digest - Mikrus.md` (sekcja „Backup serwera (strych)”).
- Brak konfiguracji (`Get-MikrusConfig`) → odeślij do skilla mikrus-setup.
