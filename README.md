# My Skills

Reusable personal skills for Codex, Claude Code, Cursor and other agents that support `SKILL.md`.

## Available Skills

| Skill | Description |
|-------|-------------|
| [agent-browser-local](./agent-browser-local) | Fixed local login profile and mode-selection conventions for the native agent-browser CLI |
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

### Local browser setup

Install the official agent-browser skill, CLI and browser through the upstream instructions. Then install `agent-browser-local` as ordinary skill instructions; no additional runtime or wrapper is required. See its [installation and migration guide](./agent-browser-local/README.md) for the fixed profile convention and user-level discovery rule. Installing skills does not grant operating-system permissions.

### Manual instruction-only installation

```bash
git clone https://github.com/deerdeerdeerdee/my-skills.git
cp -r my-skills/<skill-name> ~/.claude/skills/
```

## Maintenance

Keep one directory per skill. Each `SKILL.md` owns agent instructions; references and scripts live alongside it. Update the root index when adding or renaming a skill.

For browser skill updates, edit this repository and synchronize the installed skill instructions. Never copy profiles, credentials, machine configuration, logs, backups or runtime state into Git. Each computer maintains its own login data.

Validate skill metadata after changes. Browser commands and feature documentation come from the installed upstream CLI.

## Contributing

These are personal skills. Feel free to fork and adapt for your own use.

## License

MIT
