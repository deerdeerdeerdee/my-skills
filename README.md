# My Skills

Reusable personal skills for Codex, Claude Code, Cursor and other agents that support `SKILL.md`.

## Available Skills

| Skill | Description |
|-------|-------------|
| [agent-browser-local](./agent-browser-local) | Windows agent-browser session isolation, persistent-login routing, diagnostics and portable runtime installer |
| [layered-documentation-governance](./layered-documentation-governance) | Converge repository docs with implementation in the same change and retire superseded content |

## Installation

### Install skill instructions

```bash
npx skills add deerdeerdeerdee/my-skills@<skill-name>
```

Example:

```bash
npx skills add deerdeerdeerdee/my-skills@layered-documentation-governance
```

Skills that include local runtime components need their additional setup too. Installing instructions alone does not install those components or grant operating-system permissions.

### Windows browser runtime

Install the upstream agent-browser CLI and browser payload first, using a Node version supported by the chosen release. Then clone this repository and run the companion installer in PowerShell 7.2+:

```powershell
git clone https://github.com/deerdeerdeerdee/my-skills.git
Set-Location my-skills
pwsh -NoProfile -File .\agent-browser-local\scripts\Install-AgentBrowserLocal.ps1
agent-browser-local status
```

The installer copies the skill, runtime and command shim into the current user's home directories. It preserves local configuration and browser data. See the [browser skill guide](./agent-browser-local/README.md) for requirements, PATH setup, nvm selection, validation and rollback.

### Manual instruction-only installation

```bash
git clone https://github.com/deerdeerdeerdee/my-skills.git
cp -r my-skills/<skill-name> ~/.claude/skills/
```

## Maintenance

Keep one directory per skill. Each `SKILL.md` owns agent instructions; references and scripts live alongside it. Update the root index when adding or renaming a skill.

For browser skill updates, edit this repository and rerun its installer to synchronize the local installation. Never copy profiles, credentials, machine configuration, logs, backups or runtime state into Git. Each computer maintains its own login data.

Validate skill metadata after changes. The browser package also provides executable regression and optional smoke checks in its guide.

## Contributing

These are personal skills. Feel free to fork and adapt for your own use.

## License

MIT
