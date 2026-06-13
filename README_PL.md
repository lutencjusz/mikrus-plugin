# Plugin `mikrus`

[EN](README.md)

Skille Claude Code do obsługi serwera VPS [Mikrus](https://mikr.us): komendy przez SSH, transfer plików (SCP) i operacje przez API `api.mikr.us`.

## Skille
- **mikrus-setup** — konfiguracja połączenia i test (`~/.mikrus/config.json`).
- **mikrus-terminal** — wykonywanie komend przez SSH.
- **mikrus-files** — transfer plików przez SCP.
- **mikrus-api** — operacje przez API (info, stats, porty, db, logi, restart, domain…).

## Instalacja
Zainstaluj przez marketplace pluginów Claude Code:

```
/plugin marketplace add lutencjusz/mikrus-plugin
/plugin install mikrus@mikrus-plugin
```

Skille importują współdzielony moduł PowerShell przez `$env:CLAUDE_PLUGIN_ROOT`, więc plugin działa w każdym projekcie niezależnie od tego, gdzie Claude Code go zainstaluje — nie trzeba nic ręcznie podpinać.

## Wymagania
- Windows z PowerShell 7 (`pwsh`), OpenSSH (`ssh`/`scp`), `curl`.
- Klucz SSH wgrany na serwer Mikrus.
- Klucz API z https://mikr.us/panel/?a=api

## Konfiguracja
Uruchom skill **mikrus-setup**, który utworzy `~/.mikrus/config.json` (na Windows `%USERPROFILE%\.mikrus\config.json`). Wzór: [`config.example.json`](config.example.json):
```json
{
  "srv": "a123",
  "host": "srvXX.mikr.us",
  "sshPort": 10123,
  "user": "root",
  "identityFile": "~/.ssh/mikrus_ed25519",
  "apiKey": "xxxxxxxxxxxxxxxx",
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
