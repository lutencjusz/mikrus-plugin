# Plugin `mikrus`

[PL](README_PL.md)

Claude Code skills for managing the [Mikrus](https://mikr.us) VPS: commands over SSH, file transfer (SCP) and operations through the `api.mikr.us` API.

## Skills
- **mikrus-setup** — connection configuration and test (`~/.mikrus/config.json`).
- **mikrus-terminal** — running commands over SSH.
- **mikrus-files** — file transfer over SCP.
- **mikrus-api** — operations through the API (info, stats, ports, db, logs, restart, domain…).

## Availability across all projects
So that the skills are visible in every project (regardless of the working directory), **Junction Points** pointing to the `skills/` directories in this repo were created in the global location `~/.claude/skills/` (`C:\Users\<user>\.claude\skills\`), which Claude Code loads automatically:

```
~/.claude/skills/mikrus-api      ->  C:\claude\mikrus-plugin\skills\mikrus-api
~/.claude/skills/mikrus-files    ->  C:\claude\mikrus-plugin\skills\mikrus-files
~/.claude/skills/mikrus-setup    ->  C:\claude\mikrus-plugin\skills\mikrus-setup
~/.claude/skills/mikrus-terminal ->  C:\claude\mikrus-plugin\skills\mikrus-terminal
```

Thanks to this, changes in the repo propagate automatically — **nothing needs to be refreshed manually**. Junction Points on Windows do not require administrator privileges.

> **Recreating the links** (e.g. after a fresh clone of the repo on a new machine):
> ```powershell
> foreach ($s in 'mikrus-api','mikrus-files','mikrus-setup','mikrus-terminal') {
>   New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\$s" -Target "C:\claude\mikrus-plugin\skills\$s"
> }
> ```
> **Note:** if you move the plugin somewhere other than `C:\claude\mikrus-plugin`, delete the old junctions and recreate them with an updated `-Target`.

## Requirements
- Windows with PowerShell 7 (`pwsh`), OpenSSH (`ssh`/`scp`), `curl`.
- SSH key uploaded to the Mikrus server.
- API key from https://mikr.us/panel/?a=api

> **Note on location:** the skills import the module using the hardcoded path `C:\claude\mikrus-plugin\lib\mikrus.psm1`. If you move the plugin elsewhere, update `Import-Module` in the `skills/*/SKILL.md` files.

## Configuration
Run the **mikrus-setup** skill, which creates `C:\Users\<user>\.mikrus\config.json`:
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
`sshPort` = 10000 + machine number.

## ⚠️ Security
- **Do not commit** `config.json` or keys — `.gitignore` protects them in this repo, but the configuration file lives outside the repo anyway (`~/.mikrus`).
- Log in with the SSH key only; do not use port 22 (IP gets blocked after failed attempts).
- Data from the `/db` API and the `apiKey` are sensitive — do not expose them in logs/responses.

## Tests
```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path tests/mikrus.Tests.ps1 -Output Detailed"
```
