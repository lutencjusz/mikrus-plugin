---
name: mikrus-cron
description: 'Use when inspecting or changing scheduled jobs (crontab) on the Mikrus VPS — listing the schedule, adding a recurring task, or removing one. Every change is backed up first and adding is idempotent. Triggers: "pokaż crona na Mikrusie", "dodaj zadanie cron", "zaplanuj skrypt codziennie", "usuń wpis z crontaba", "co się uruchamia na serwerze".'
---

# mikrus-cron

Podgląd i zmiana harmonogramu `crontab` na serwerze Mikrus. Każda zmiana **najpierw
robi backup** crontaba do `~/.mikrus/crontab.bak-<timestamp>` na serwerze.

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force

# Podgląd harmonogramu
(Get-MikrusCron).Output

# Dodanie zadania (z komentarzem wyjaśniającym PO CO ono jest)
Add-MikrusCronEntry -Schedule '35 21 * * *' `
                    -Command '/usr/bin/python3 /root/skrypty/prune.py >> /root/skrypty/prune.log 2>&1' `
                    -Comment 'Retencja notebookow - kasuje starsze niz 7 dni.'

# Usunięcie zadania (dopasowanie dosłowne, nie regex)
Remove-MikrusCronEntry -Match '/root/skrypty/prune.py'
```

Aby zobaczyć zdalny skrypt bez wykonania — `-DryRun` (zwraca całą komendę `ssh`).

## Co robią te funkcje

| Funkcja | Działanie |
|---|---|
| `Get-MikrusCron` | `crontab -l` — czysty odczyt, nic nie zmienia |
| `Add-MikrusCronEntry` | backup → sprawdzenie duplikatu → dopisanie komentarza i wpisu |
| `Remove-MikrusCronEntry` | backup → usunięcie pasujących linii **wraz z ich komentarzem** |

**Dodawanie jest idempotentne** — identyczny wpis (`grep -qxF`) nie zostanie dodany
drugi raz, funkcja zwróci `MIKRUS-CRON: wpis juz istnieje — bez zmian.` i `ExitCode 0`.
Można ją więc bezpiecznie wywołać ponownie, nie sprawdzając wcześniej stanu.

**Usuwanie kasuje też blok komentarza** bezpośrednio nad wpisem i pojedynczą pustą
linię separatora — inaczej w crontabie zostają osierocone komentarze opisujące
nieistniejące zadania.

## Zasady

- **Harmonogram**: 5 pól (`min godz dzień miesiąc dzień_tygodnia`) albo skrót
  `@daily`/`@reboot`/`@hourly`. Zła liczba pól → wyjątek jeszcze przed wysłaniem na serwer.
- **Zawsze dawaj `-Comment`** wyjaśniający po co jest zadanie. Crontab bez komentarzy
  po pół roku jest nieczytelny, a `Remove-MikrusCronEntry` i tak posprząta komentarz razem z wpisem.
- **Przekierowanie logu** (`>> /root/skrypty/x.log 2>&1`) wpisuj do `-Command`. Bez niego
  cron wysyła wyjście mailem lokalnym, którego nikt nie czyta — i diagnostyka awarii
  jest niemożliwa.
- **Strefa czasowa** to strefa serwera (`timedatectl`); na Mikrusie zwykle `Europe/Warsaw`,
  więc `45 21` = 21:45 czasu polskiego, z automatyczną zmianą DST.
- Komenda **nie może zawierać znaku nowej linii** — crontab czyta każdą linię osobno.
  Dłuższą logikę zapisz jako skrypt (`Set-MikrusRemoteFile`, skill mikrus-files) i wywołaj
  go jednym wpisem.
- **Usuwanie**: `-Match` to dosłowny fragment linii (jak `grep -F`). Podaj coś
  jednoznacznego — ścieżkę skryptu, nie samą godzinę. Przy szerokim wzorcu najpierw
  pokaż użytkownikowi `(Get-MikrusCron).Output` i potwierdź, co zniknie.
- Sprawdzaj `ExitCode`; przy ≠ 0 pokaż `Output`. `124` (`TimedOut`) = przekroczony limit czasu.
- Brak konfiguracji → odeślij do skilla mikrus-setup.

> [!WARNING]
> Zmiana crontaba wpływa na działające automatyzacje. Zanim usuniesz cokolwiek, czego
> nie dodałeś w tej sesji, pokaż użytkownikowi aktualny harmonogram i poproś o zgodę.
> Backup jest robiony automatycznie (`~/.mikrus/crontab.bak-*`), ale przywrócenie wymaga
> ręcznego `crontab <plik>`.
