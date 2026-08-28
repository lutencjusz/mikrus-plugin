# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Co to jest

Plugin Claude Code o nazwie `mikrus` do obsługi serwera VPS [Mikrus](https://mikr.us). Składa się z pięciu skilli (`skills/*/SKILL.md`), które są cienkimi nakładkami dokumentującymi jeden współdzielony moduł PowerShell `lib/mikrus.psm1`. Cała logika żyje w module; skille opisują tylko, kiedy i jak go wywołać. Język dokumentacji i komunikatów: polski.

## Architektura

- **`lib/mikrus.psm1`** — jedyne źródło logiki. Dwie warstwy funkcji:
  - **Buildery** (`New-MikrusSSHArgs`, `New-MikrusScpArgs`, `New-MikrusApiRequest`) — czyste, deterministyczne, budują tablice argumentów / strukturę żądania bez efektów ubocznych. Są bezpośrednio testowalne.
  - **Egzekutory** (`Invoke-MikrusSSH`, `Send-MikrusFile`, `Get-MikrusFile`, `Invoke-MikrusApi`) — wywołują zewnętrzne `ssh`/`scp`/`curl` (`Invoke-MikrusCurl`). Każdy najpierw woła builder, potem uruchamia komendę.
- **`Get-MikrusConfig`** — wczytuje i **waliduje** `~/.mikrus/config.json` (sprawdza komplet pól: `srv,host,sshPort,user,identityFile,apiKey,apiBase`). Brak pliku/pola → wyjątek odsyłający do skilla `mikrus-setup`. Config żyje poza repo.
- **Wzorzec `-DryRun`** — egzekutory SSH/SCP z `-DryRun` zwracają tablicę komendy zamiast ją wykonywać. To jest mechanizm testowania bez sieci oraz sposób na podgląd komendy przed wykonaniem destrukcyjnej operacji.
- **Buildery skryptów zdalnych** (`New-MikrusRemoteWriteScript`, `New-MikrusCronAddScript`, `New-MikrusCronRemoveScript`) — składają tekst skryptu bash wykonywanego przez `Invoke-MikrusSSH`. Egzekutory: `Set-MikrusRemoteFile`, `Add-MikrusCronEntry`, `Remove-MikrusCronEntry`, `Get-MikrusCron`.

## Skrypty generowane dla zdalnego basha — dwie pułapki

1. **CRLF.** Pliki tego repo mają zakończenia CRLF, więc PowerShellowe here-stringi (`@"…"@`) przenoszą `\r` do generowanego skryptu. Bash dokleja CR do ostatniego argumentu w linii: `set -e<CR>` → `invalid option`, `"$HOME/.mikrus"<CR>` → katalog z CR w nazwie. **Każdy** builder skryptu musi przepuścić wynik przez `ConvertTo-MikrusLfText` (test regresyjny: „Skrypty zdalne nie zawieraja CR").
2. **Cytowanie.** Wartości wstawiane do skryptu (ścieżki, komendy, wzorce) przechodzą przez `ConvertTo-MikrusShellSingleQuoted` — bash nie zna escape'ów wewnątrz apostrofów, więc apostrof zamykamy i otwieramy z powrotem (`'\''`). Wzorce przekazywane do `awk` idą przez `ENVIRON`, bo `awk -v` interpretowałoby sekwencje z backslashem.
- **`Invoke-MikrusApi`** — POST przez `curl` z nagłówkiem `Authorization: <apiKey>`, pole `srv` dodawane automatycznie. Zwraca sparsowany JSON; wykrywa pole `error`, brak odpowiedzi i nie-JSON i zamienia je na czytelne wyjątki.

## Ładowanie modułu (przenośne)

Skille importują moduł przez `$env:CLAUDE_PLUGIN_ROOT`:
`Import-Module "$env:CLAUDE_PLUGIN_ROOT/lib/mikrus.psm1"`. Zmienną ustawia Claude Code,
gdy plugin jest zainstalowany — nie ma zaszytej ścieżki bezwzględnej, więc plugin działa
niezależnie od miejsca instalacji (marketplace) i nie wymaga ręcznego podpinania.

## Testy

Pester. Buildery testowane bezpośrednio, egzekutory przez `-DryRun`, `Invoke-MikrusApi` przez `InModuleScope mikrus` + `Mock Invoke-MikrusCurl` (mockuje tylko warstwę `curl`, reszta logiki realna).

```powershell
# Wszystkie testy
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"

# Pojedynczy blok Describe
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -FullNameFilter '*Invoke-MikrusApi*' -Output Detailed"
```

## Konwencje przy zmianach

- Nowa operacja = nowy builder (czysty, z testem) + cienki egzekutor, oba w `mikrus.psm1`; potem zaktualizuj odpowiedni SKILL.md. Nie duplikuj logiki w skillach.
- **`description:` w SKILL.md zawsze w apostrofach** (wewnętrzne `'` podwajaj). Opisy zawierają `Triggers: "…"`, a dwukropek ze spacją w niecytowanym skalarze YAML psuje parsowanie — Claude Code pokazuje wtedy samą nazwę skilla zamiast opisu i **skill przestaje się wyzwalać**. Weryfikacja: `grep -h '^description:' skills/*/SKILL.md` — każda linia musi zaczynać się od `description: '`.
- Wersję podbijaj w **dwóch** miejscach: `.claude-plugin/plugin.json` i `.claude-plugin/marketplace.json` (ta druga zasila `/plugin install`).
- `Set-StrictMode -Version Latest` jest aktywny — odwołania do nieistniejących pól wywalą się.
- Operacje destrukcyjne (SSH `rm -rf`/`reboot`, API `/restart`/`/amfetamina`) wymagają potwierdzenia użytkownika — najpierw pokaż dokładną komendę (np. przez `-DryRun`).
- Nigdy nie wypisuj `apiKey` ani danych z API `/db`. Nie commituj `config.json` (chroni `.gitignore`).
- API `/exec` ma limit 60 s — dłuższe zadania kieruj na SSH (`Invoke-MikrusSSH`).
- `sshPort = 10000 + numer maszyny`; port 22 jest zablokowany — łączymy się wyłącznie kluczem na `sshPort`.

## Dokumentacja projektowa

`docs/superpowers/specs/` i `docs/superpowers/plans/` zawierają oryginalny design i plan implementacji pluginu.
