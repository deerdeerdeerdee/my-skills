# agent-browser-local

Windows routing and lifecycle companion for the upstream agent-browser CLI. Source of truth: this directory in `my-skills`. Run the installer to synchronize an installed copy; do not copy runtime state back into Git.

## Requirements and installation

- Windows x64 (or Windows ARM64 with the upstream x64 binary), PowerShell 7.2+.
- An installed agent-browser native CLI and Chrome payload (`agent-browser install`). Use the Node version required by your chosen npm release; current 0.31.x requires Node 24+.
- The upstream agent-browser skill, which supplies version-matched browser instructions.

From the cloned repository, in PowerShell 7:

```powershell
pwsh -NoProfile -File .\agent-browser-local\scripts\Install-AgentBrowserLocal.ps1
agent-browser-local status
```

Defaults use the current user's home: runtime in `.agent-browser/local`, skill in `.agents/skills/agent-browser-local`, command shim in `.local/bin`. Add `.local/bin` to PATH if needed. Paths can be overridden with `-InstallRoot`, `-SkillRoot`, and `-BinRoot`. The installer preserves `config.psd1`, profiles, logs and state; replaced code has scoped backups. Installing only the skill through `npx skills` does not install the command runtime: run `scripts/Install-AgentBrowserLocal.ps1` from the installed skill too.

## Daily use

```powershell
$session = agent-browser-local test new qa
try {
    agent-browser-local test run $session open https://example.com
    agent-browser-local test run $session snapshot -i
    agent-browser-local test run $session console
} finally {
    agent-browser-local test close $session
}

# Visible isolated test browser
$visible = agent-browser-local test new visual --headed
agent-browser-local test run $visible open about:blank
agent-browser-local test close $visible

# Only for tasks requiring persistent managed login
agent-browser-local auth start about:blank
agent-browser-local auth run snapshot -i
agent-browser-local auth stop
```

Commands after `run` use command-first syntax. New sessions are registered and checked before execution. Test sessions may run in parallel; auth operations are serialized. Each test close invalidates only its own registration after successful native close. Registrations prevent mistakes, not other same-user processes reading or editing local files.

The wrapper uses its own minimal CLI config and temporarily removes inherited `AGENT_BROWSER_*` overrides. Standard proxy variables remain available. It blocks routing overrides and unreviewed command families. `batch` accepts JSON arrays as arguments, validates every command and sends a normalized JSON document to the native CLI through stdin; nested batches are rejected and sessions close outside batches. Unknown commands fail closed so new upstream capabilities require review. This is not an operating-system sandbox or an authorization mechanism for external site mutations.

Supported command families include navigation/read, snapshot/screenshot, element and keyboard operations, network, page storage, tabs, diffs, tracing/recording, console/errors, React, Web Vitals, a11y, frames and dialogs. Availability depends on the installed upstream CLI. `--enable react-devtools` may be passed on the initial open. Stdin forwarding is unsupported; use `eval -b <base64>` and argument-based batches. CLI flags are available except reserved routing/config/provider/plugin/launch overrides. MCP, plugins, dashboard and autonomous chat are not routed through test/auth.

## Machine configuration

Optional `config.psd1` in the runtime root overrides portable defaults. `AGENT_BROWSER_LOCAL_CONFIG` may select a separate PowerShell data file. Do not copy a machine's config into the source repository.

```powershell
@{
    # Empty: follow the current nvm/PATH npm installation.
    CanonicalCliHint = ''
    CdpAddress = '127.0.0.1'
    CdpPort = 9333
}
```

For an nvm-independent CLI, pin `CanonicalCliHint` to the real version directory's native executable, not nvm's shared symlink. A missing pin fails explicitly. BrowserRoot and AuthProfilePath can also be overridden. A new computer starts with a new work profile and requires its own manual login.

## Validation and maintenance

```powershell
pwsh -NoProfile -File .\agent-browser-local\scripts\Test-AgentBrowserLocal.ps1
pwsh -NoProfile -File .\agent-browser-local\scripts\Test-AgentBrowserLocal.ps1 -Smoke
```

Regression checks use an isolated temporary config and do not access real authentication data. Optional smoke starts only task-owned temporary browser sessions, checks isolation and targeted close, and never runs doctor or the real work profile. Use `status` first for ordinary failures. See [policy](references/policy.md) and [troubleshooting](references/troubleshooting.md).

## Source layout

- `SKILL.md` and `references/`: agent routing and operational rules.
- `scripts/runtime/`: installable entry point, module and controlled CLI config.
- `scripts/Install-AgentBrowserLocal.ps1`: portable installation and local synchronization.
- `scripts/Test-AgentBrowserLocal.ps1`: executable regression and optional runtime checks.

Only source is distributed. Browser binaries, profiles, credentials, local config, registrations, logs, backups and historical execution artifacts are excluded.
