---
name: mikrus-terminal
description: Use when running shell commands on the Mikrus VPS over SSH — checking status, inspecting files/logs, managing services or packages on the server. Triggers: "wykonaj na Mikrusie", "uruchom komendę na serwerze", "sprawdź df -h na mikrusie", "restartuj usługę na serwerze".
---

# mikrus-terminal

Wykonuje komendy na serwerze Mikrus przez SSH (pełny shell roota, bez limitu 60 s API).

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force
$wynik = Invoke-MikrusSSH -Command 'df -h'
$wynik.Output
$wynik.ExitCode   # 0 = sukces
```

Aby tylko podejrzeć złożoną komendę bez wykonania, użyj `-DryRun`.

## Limity czasu (nie wisi w nieskończoność)

`Invoke-MikrusSSH`, `Send-MikrusFile` i `Get-MikrusFile` mają **twardy limit czasu**
na cały proces ssh/scp. Po przekroczeniu proces (z drzewem potomnym) jest ubijany,
a wynik ma `ExitCode = 124` i `TimedOut = $true` — zamiast wisieć w nieskończoność.

Trzy warstwy zabezpieczeń (dodawane automatycznie):
- `ConnectTimeout` — ucina martwy handshake TCP,
- `ServerAliveInterval`/`ServerAliveCountMax` — wykrywa sesję, która zawisła **po**
  uwierzytelnieniu (np. kontener pod presją RAM przyjmuje TCP, ale sshd milczy),
- **wall-clock timeout** na cały proces — backstop na zwis w fazie wymiany
  kluczy/auth, którego dwa powyższe nie łapią.

Domyślny wall-clock to **180 s**. Dla długich operacji (backup, streaming) podaj
większy `-TimeoutSec`:

```powershell
Invoke-MikrusSSH -Command 'bash /root/skrypty/backup_strych.sh' -TimeoutSec 1200
```

Wartości domyślne można nadpisać w `~/.mikrus/config.json` polami:
`connectTimeout`, `serverAliveInterval`, `serverAliveCountMax`, `commandTimeout`.

## Zasady
- **Polecenia destrukcyjne** (`rm -rf`, `reboot`, zatrzymywanie/usuwanie usług, nadpisywanie plików) — najpierw pokaż użytkownikowi dokładną komendę i poproś o potwierdzenie, dopiero potem wykonaj.
- Po wykonaniu sprawdzaj `ExitCode`; przy ≠ 0 pokaż `Output` i wyjaśnij błąd. `ExitCode = 124` (`TimedOut`) oznacza przekroczony limit czasu — zwiększ `-TimeoutSec` jeśli komenda jest długa.
- Dla zadań długich (>180 s) podaj większy `-TimeoutSec` (API `/exec` ma limit 60 s — patrz skill mikrus-api).
- Jeśli `Get-MikrusConfig` zgłosi brak konfiguracji — odeślij do skilla mikrus-setup.
