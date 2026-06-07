# Plugin `mikrus`

[EN](README.md)

Skille Claude Code do obsługi serwera VPS [Mikrus](https://mikr.us): komendy przez SSH, transfer plików (SCP) i operacje przez API `api.mikr.us`.

## Skille
- **mikrus-setup** — konfiguracja połączenia i test (`~/.mikrus/config.json`).
- **mikrus-terminal** — wykonywanie komend przez SSH.
- **mikrus-files** — transfer plików przez SCP.
- **mikrus-api** — operacje przez API (info, stats, porty, db, logi, restart, domain…).

## Dostępność we wszystkich projektach
Aby skille były widoczne w każdym projekcie (niezależnie od katalogu roboczego), w globalnej lokalizacji `~/.claude/skills/` (`C:\Users\<user>\.claude\skills\`) — którą Claude Code ładuje automatycznie — utworzono **Junction Points** wskazujące na katalogi `skills/` w tym repo:

```
~/.claude/skills/mikrus-api      ->  C:\claude\mikrus-plugin\skills\mikrus-api
~/.claude/skills/mikrus-files    ->  C:\claude\mikrus-plugin\skills\mikrus-files
~/.claude/skills/mikrus-setup    ->  C:\claude\mikrus-plugin\skills\mikrus-setup
~/.claude/skills/mikrus-terminal ->  C:\claude\mikrus-plugin\skills\mikrus-terminal
```

Dzięki temu zmiany w repo propagują się automatycznie — **nie trzeba nic ręcznie odświeżać**. Junction Points na Windows nie wymagają uprawnień administratora.

> **Odtworzenie linków** (np. po świeżym klonie repo na nowej maszynie):
> ```powershell
> foreach ($s in 'mikrus-api','mikrus-files','mikrus-setup','mikrus-terminal') {
>   New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\$s" -Target "C:\claude\mikrus-plugin\skills\$s"
> }
> ```
> **Uwaga:** jeśli przeniesiesz plugin w inne miejsce niż `C:\claude\mikrus-plugin`, usuń stare junctiony i utwórz je ponownie ze zaktualizowanym `-Target`.

## Wymagania
- Windows z PowerShell 7 (`pwsh`), OpenSSH (`ssh`/`scp`), `curl`.
- Klucz SSH wgrany na serwer Mikrus.
- Klucz API z https://mikr.us/panel/?a=api

> **Uwaga o lokalizacji:** skille importują moduł zaszytą ścieżką `C:\claude\mikrus-plugin\lib\mikrus.psm1`. Jeśli przeniesiesz plugin w inne miejsce, zaktualizuj `Import-Module` w plikach `skills/*/SKILL.md`.

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
