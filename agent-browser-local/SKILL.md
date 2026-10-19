---
name: agent-browser-local
description: Manage Windows agent-browser sessions with temporary or persistent login data, headed or headless operation, and targeted lifecycle diagnostics. Use with agent-browser for local browser automation and frontend testing.
---

# Local browser routing

Read [references/policy.md](references/policy.md) before browser commands. Use the upstream agent-browser skill and `agent-browser skills get core` for the installed version's page-operation syntax. This skill owns machine-local routing and lifecycle.

Choose data lifetime and display mode independently:

| Task | Display | Command |
| --- | --- | --- |
| Frontend tests or other temporary browsing | Headless (default) | `test new qa` |
| Temporary browsing with visual observation | Headed | `test new qa --headed` |
| Reuse managed login in the background | Headless | `auth start <url> --headless` |
| First login, verification, or persistent browsing with a window | Headed (default for auth) | `auth start <url> --headed` |

Honor an established user preference for persistent automation without asking again for every task. Use temporary sessions for frontend tests unless the task needs managed login. Display defaults do not override an explicit user choice.

## Test browsing

Use a new registered session for each task; reuse it within that task. Test mode ignores ambient `AGENT_BROWSER_*` settings and user/project CLI configuration. It uses no saved profile or restore state.

```powershell
$session = agent-browser-local test new qa
try {
    agent-browser-local test run $session open <url>
    agent-browser-local test run $session snapshot -i
} finally {
    agent-browser-local test close $session
}
```

For a visible browser, use `test new qa --headed`. This still creates an isolated test browser. Browser visibility does not require persistent login. For React inspection, pass `--enable react-devtools` on the first `open` through `test run`.

Pass the command first after `run <session>`. Routing flags, providers, plugins, MCP/chat servers and maintenance commands are not passed through. Pass batch commands as JSON-array arguments; the wrapper checks every command and sends the validated arrays to the native CLI through stdin. Nested batches, caller-provided stdin and closing inside batches are unsupported. Use `eval -b <base64>` for complex JavaScript.

## Persistent login

Use auth mode when the task or an established user preference requires persistent user-managed login or browser data:

```powershell
agent-browser-local auth start <url>
agent-browser-local auth run snapshot -i
agent-browser-local auth stop

# Later background work uses the same profile after the headed browser stops.
agent-browser-local auth start <url> --headless
agent-browser-local auth run snapshot -i
agent-browser-local auth stop
```

It uses one Chrome, a persistent work profile and one configured local CDP port (default 9333), with serialized operations and checked ownership. Both display modes share that profile; it is separate from everyday Chrome. `auth status` reports `Headless` from the verified running process (`null` when absent or unverified). A start in the same mode reuses the browser; a conflicting mode fails without navigating or closing it. Stop your task-owned browser before switching modes. Finish with `auth stop`, which closes Chrome gracefully and releases its reserved CLI connection. After manual closure use `auth status`. Never start a second Chrome sharing that profile.

First login or expired sessions may require a headed browser and user verification. Persistent cookies and site storage can survive restarts; website expiration, logout, and some session-only state can still require login. No login data is synchronized between computers.

## Diagnostics and installation

Use `agent-browser-local status` first on failure. Preserve evidence and close only sessions belonging to this task. Ordinary task failure is not authorization for repair or global cleanup. Upstream doctor performs cleanup even without `--fix` and is not a read-only diagnostic.

For installation, nvm selection/pinning, supported commands, validation and portability, read the repository [README.md](README.md) and [troubleshooting reference](references/troubleshooting.md). The runtime installer must be run separately after installing the skill. No authentication data is included in the package.
