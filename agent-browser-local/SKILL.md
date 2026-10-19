---
name: agent-browser-local
description: Manage agent-browser sessions on Windows with isolated test browsers, a serial persistent-login browser, and targeted lifecycle diagnostics. Use with agent-browser when controlling local browsers or diagnosing their launch and ownership.
---

# Local browser routing

Read [references/policy.md](references/policy.md) before browser commands. Use the upstream agent-browser skill and `agent-browser skills get core` for the installed version's page-operation syntax. This skill owns machine-local routing and lifecycle.

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

Use auth mode when the task explicitly needs persistent user-managed login or browser data:

```powershell
agent-browser-local auth start <url>
agent-browser-local auth run snapshot -i
agent-browser-local auth stop
```

It uses one visible Chrome and one configured local CDP port (default 9333), with serialized operations and checked ownership. The managed work profile is separate from the user's everyday Chrome profile. Finish with `auth stop`; after manual closure use `auth status`. Never start a second Chrome sharing that profile.

## Diagnostics and installation

Use `agent-browser-local status` first on failure. Preserve evidence and close only sessions belonging to this task. Ordinary task failure is not authorization for repair or global cleanup. Upstream doctor performs cleanup even without `--fix` and is not a read-only diagnostic.

For installation, nvm selection/pinning, supported commands, validation and portability, read the repository [README.md](README.md) and [troubleshooting reference](references/troubleshooting.md). The runtime installer must be run separately after installing the skill. No authentication data is included in the package.
