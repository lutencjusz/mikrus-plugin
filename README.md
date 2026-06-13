# Plugin `mikrus`

[PL](README_PL.md)

Claude Code skills for managing the [Mikrus](https://mikr.us) VPS: commands over SSH, file transfer (SCP) and operations through the `api.mikr.us` API.

## Skills
- **mikrus-setup** — connection configuration and test (`~/.mikrus/config.json`).
- **mikrus-terminal** — running commands over SSH.
- **mikrus-files** — file transfer over SCP.
- **mikrus-api** — operations through the API (info, stats, ports, db, logs, restart, domain…).

## Installation
Install through the Claude Code plugin marketplace:

```
/plugin marketplace add lutencjusz/mikrus-plugin
/plugin install mikrus@mikrus-plugin
```

The skills import the shared PowerShell module via `$env:CLAUDE_PLUGIN_ROOT`, so the plugin works from any project regardless of where Claude Code installs it — nothing has to be wired up by hand.

## Requirements
- Windows with PowerShell 7 (`pwsh`), OpenSSH (`ssh`/`scp`), `curl`.
- SSH key uploaded to the Mikrus server.
- API key from https://mikr.us/panel/?a=api

## Configuration
Run the **mikrus-setup** skill, which creates `~/.mikrus/config.json` (on Windows `%USERPROFILE%\.mikrus\config.json`). See [`config.example.json`](config.example.json):
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
`sshPort` = 10000 + machine number.

## ⚠️ Security
- **Do not commit** `config.json` or keys — `.gitignore` protects them in this repo, but the configuration file lives outside the repo anyway (`~/.mikrus`).
- Log in with the SSH key only; do not use port 22 (IP gets blocked after failed attempts).
- Data from the `/db` API and the `apiKey` are sensitive — do not expose them in logs/responses.

## Tests
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
