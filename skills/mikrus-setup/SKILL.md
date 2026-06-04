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
   Import-Module "C:\claude\mikrus-plugin\lib\mikrus.psm1" -Force
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
