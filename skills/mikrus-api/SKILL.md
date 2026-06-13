---
name: mikrus-api
description: Use when performing Mikrus operations through the API (api.mikr.us) — server info, stats, ports, database credentials, logs, restart, amfetamina boost, quick exec, cloud, or assigning a domain. Triggers: "info o serwerze mikrus", "statystyki mikrus", "restart przez API", "dane do bazy mikrus", "porty mikrus", "amfetamina", "logi mikrus", "dodaj domenę".
---

# mikrus-api

Wykonuje operacje na serwerze Mikrus przez API `https://api.mikr.us`.

## Użycie

```powershell
Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1" -Force
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
