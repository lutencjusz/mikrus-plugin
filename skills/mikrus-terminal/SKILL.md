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

## Zasady
- **Polecenia destrukcyjne** (`rm -rf`, `reboot`, zatrzymywanie/usuwanie usług, nadpisywanie plików) — najpierw pokaż użytkownikowi dokładną komendę i poproś o potwierdzenie, dopiero potem wykonaj.
- Po wykonaniu sprawdzaj `ExitCode`; przy ≠ 0 pokaż `Output` i wyjaśnij błąd.
- Dla zadań długich (>60 s) to jest właściwy kanał (API `/exec` ma limit 60 s — patrz skill mikrus-api).
- Jeśli `Get-MikrusConfig` zgłosi brak konfiguracji — odeślij do skilla mikrus-setup.
