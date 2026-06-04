# Plugin `mikrus` — dokument projektowy

**Data:** 2026-06-04
**Status:** zatwierdzony do implementacji
**Cel:** Plugin Claude Code dostarczający skille do obsługi serwera VPS Mikrus — wykonywanie komend przez terminal (SSH), transfer plików (SCP) oraz operacje przez API (`api.mikr.us`).

## 1. Kontekst i założenia

Mikrus udostępnia dwa kanały dostępu:

- **SSH/SCP:** `ssh -p <10000+numer> root@srvXX.mikr.us` (użytkownik `root`, zalecane klucze SSH; port 22 zablokowany po nieudanych próbach). Transfer plików przez `scp -P <port>`, panel `/drop` (do 100 MB) lub WinSCP.
- **API (`https://api.mikr.us`):** żądania POST z polami `srv` (nazwa serwera) + `key` (klucz API z panelu `https://mikr.us/panel/?a=api`). Klucz może iść też nagłówkiem `Authorization`. Odpowiedź JSON (lub `.bash`).

Endpointy API: `/info`, `/serwery`, `/stats`, `/porty`, `/db`, `/logs` (+`/logs/ID`), `/restart`, `/amfetamina`, `/exec` (komenda w polu `cmd`, limit 60 s), `/cloud`, `/domain` (wymaga `port` + `domain`).

**Decyzje projektowe (z brainstormingu):**

| Decyzja | Wybór |
|---|---|
| Liczba serwerów | Jeden (prosta konfiguracja) |
| Uwierzytelnianie SSH/SCP | Klucz SSH |
| Przechowywanie konfiguracji | Plik poza pluginem: `~/.mikrus/config.json` |
| Podział na skille | 4 skille: setup, terminal, files, api |
| Implementacja operacji | Wspólny moduł PowerShell w pluginie (Podejście A) |

**Środowisko:** Windows 11, dostępne `ssh`, `scp`, `curl`, `pwsh` (PowerShell 7) — bez dodatkowych instalacji.

## 2. Architektura i struktura plików

Plugin `mikrus` w `c:\claude\mikrus-plugin\` (osobne repo git, instalowalny jako lokalny plugin/marketplace).

```
mikrus-plugin/
├── .claude-plugin/
│   └── plugin.json              # manifest: name, version, description, author
├── lib/
│   └── mikrus.psm1              # wspólny moduł PowerShell (Podejście A)
├── skills/
│   ├── mikrus-setup/SKILL.md
│   ├── mikrus-terminal/SKILL.md
│   ├── mikrus-files/SKILL.md
│   └── mikrus-api/SKILL.md
├── tests/
│   └── mikrus.Tests.ps1         # testy Pester dla modułu
├── docs/superpowers/specs/      # ten dokument
├── .gitignore
└── README.md
```

### Schemat konfiguracji

`C:\Users\micha\.mikrus\config.json` (poza repo, tworzony przez `mikrus-setup`):

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

- `srv` + `apiKey` → API; `host` + `sshPort` + `user` + `identityFile` → SSH/SCP.
- `sshPort` = 10000 + numer maszyny (setup wylicza i podpowiada).
- Plik z dostępem tylko dla użytkownika; README ostrzega, by go nie commitować.

## 3. Skille

### `mikrus-setup` — konfiguracja i diagnostyka
- **Trigger:** „skonfiguruj Mikrus", „połącz z Mikrusem", „sprawdź połączenie z serwerem", „test mikrus".
- **Działanie:** pyta o dane (numer maszyny → wylicza port; host, ścieżka klucza, klucz API), zapisuje `~/.mikrus/config.json`, podpowiada wgranie klucza publicznego na serwer, wykonuje test: `Invoke-MikrusApi /info` + `Invoke-MikrusSSH "echo ok"`. Raportuje, co działa.

### `mikrus-terminal` — komendy przez SSH
- **Trigger:** „wykonaj na Mikrusie…", „uruchom komendę na serwerze", „sprawdź `df -h` na mikrusie", „restartuj usługę na serwerze".
- **Działanie:** `Invoke-MikrusSSH -Command "..."`. Pełny shell roota, bez limitu 60 s. Polecenia destrukcyjne (rm, reboot, zmiana usług) — potwierdzenie przed wykonaniem.

### `mikrus-files` — transfer plików (SCP)
- **Trigger:** „wyślij plik na Mikrusa", „pobierz plik z serwera", „skopiuj katalog na mikrus".
- **Działanie:** `Send-MikrusFile` / `Get-MikrusFile` (scp, `-r` dla katalogów). Wspomina o alternatywie panel `/drop` (do 100 MB).

### `mikrus-api` — operacje przez API
- **Trigger:** „info o serwerze mikrus", „statystyki mikrus", „restart przez API", „dane do bazy", „porty mikrus", „amfetamina", „logi mikrus", „dodaj domenę".
- **Działanie:** `Invoke-MikrusApi -Endpoint <...>` dla `/info`, `/serwery`, `/stats`, `/porty`, `/db`, `/logs` (+`/logs/ID`), `/restart`, `/amfetamina`, `/exec` (adnotacja o limicie 60 s + sugestia terminala dla dłuższych), `/cloud`, `/domain` (z `port`+`domain`). Parsuje JSON i przedstawia czytelnie.

**Granica terminal vs `/exec`:** SSH to domyślny kanał poleceń (bez limitu czasu, pełny output). `/exec` w API to „szybka komenda" gdy użytkownik wprost prosi o API; `mikrus-api` przy dłuższych zadaniach odsyła do `mikrus-terminal`.

## 4. Moduł `mikrus.psm1` — funkcje publiczne

| Funkcja | Rola |
|---|---|
| `Get-MikrusConfig` | Wczytuje `~/.mikrus/config.json`, waliduje wymagane pola; czytelny błąd „uruchom mikrus-setup" gdy brak. |
| `Invoke-MikrusSSH -Command <str> [-Raw]` | `ssh -p <sshPort> -i <identityFile> -o BatchMode=yes <user>@<host> <command>`. Zwraca output + kod wyjścia. |
| `Send-MikrusFile -Local <p> -Remote <p> [-Recurse]` | `scp -P <sshPort> -i <identityFile>` lokalny → serwer. |
| `Get-MikrusFile -Remote <p> -Local <p> [-Recurse]` | scp serwer → lokalnie. |
| `Invoke-MikrusApi -Endpoint <str> [-Body <hashtable>]` | `curl` POST na `<apiBase><endpoint>` z `srv`+`key` (+ ew. `cmd`/`port`/`domain`); zwraca sparsowany JSON. |

## 5. Obsługa błędów

- Brak/niekompletny config → wyjątek z instrukcją uruchomienia `mikrus-setup`.
- SSH: `BatchMode=yes` → brak wiszących promptów o hasło; nieznany host key / błąd auth → czytelny komunikat (z odnośnikiem do wiki o zmianie host key).
- API: błąd HTTP lub `{"error": ...}` → zwróć treść błędu, nie surowy dump; rozpoznaj limit 60 s na `/exec`.
- Polecenia destrukcyjne w `mikrus-terminal` → potwierdzenie przed wykonaniem.

## 6. Bezpieczeństwo

- `apiKey` tylko w `~/.mikrus/config.json` (poza repo); plugin nie loguje klucza.
- Klucz API przekazywany do `curl` nagłówkiem `Authorization` lub w body, nie w URL.
- `.gitignore` w repo; README ostrzega, by nie commitować configu i klucza.
- SSH wyłącznie kluczem; nigdy port 22 z hasłem (ochrona przed blokadą IP).

## 7. Testowanie

**Pester** w `tests/mikrus.Tests.ps1` (TDD przy implementacji):

- `Get-MikrusConfig` — poprawny config / brak pliku / brakujące pole (oczekiwane komunikaty); config jako tymczasowy plik, bez ruszania prawdziwego `~/.mikrus`.
- Budowanie komend — funkcje SSH/SCP/API z trybem „dry-run" zwracającym złożoną komendę, testowanym bez realnego połączenia (np. maszyna 123 → `ssh -p 10123 -i ... root@srv03.mikr.us ...`).
- Parsowanie API — `Invoke-MikrusApi` z mockiem `curl`, testy na poprawny JSON i `{"error":...}`.
- Brak wywołań sieciowych w testach — ssh/scp/curl mockowane; testy szybkie i offline.

**Test ręczny e2e** (po implementacji, na realnym serwerze): `mikrus-setup` → `/info` przez API → `echo ok` przez SSH → wysłanie i pobranie pliku.

## 8. Poza zakresem (YAGNI)

- Obsługa wielu serwerów / profili.
- Uwierzytelnianie hasłem, plink/pscp/sshpass.
- Interaktywne sesje terminalowe (PTY) — operacje są jednorazowe (komenda → output).
- GUI / integracje WinSCP/FileZilla (jedynie wzmianka w dokumentacji).
