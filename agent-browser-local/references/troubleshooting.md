# Troubleshooting

Run `agent-browser-local status`, `Get-Command agent-browser,agent-browser-local`, `node --version`, and `agent-browser --version`. Record the failing task session and any reported PID or ownership reason. Status reports the resolved native CLI, its version and npm package version when available.

## nvm and upgrades

By default, the wrapper finds the native executable beside the currently selected npm installation, following nvm's shared symlink. It does not switch Node or install packages. To keep a CLI independent of nvm selection, set `CanonicalCliHint` in the installed `config.psd1` to an absolute native executable path inside the desired version's real directory, rather than the shared symlink. A missing pinned path fails explicitly.

Compare `npm ls -g agent-browser` and `agent-browser --version` after npm updates. An npm allow-scripts warning concerns postinstall execution; it does not prove the native binary was updated. Review only the named package's pending script if necessary. Read the installed upstream guide after updates and run the packaged regression and isolated smoke checks.

## Registration or configuration errors

Create a fresh session after upgrading from the older unregistered wrapper. Legacy sessions are not imported. Close an already-running legacy session only with task ownership evidence; do not guess a session name. Successful close removes only its exact registration. Failed close preserves the record for targeted diagnosis.

Runtime commands bypass user and cwd agent-browser configuration with the packaged `cli-config.json`, and remove inherited `AGENT_BROWSER_*` variables in the child execution scope. Standard proxy environment variables remain available. Pass task-specific supported page/launch options explicitly. Keep the packaged CLI config unmodified; machine paths and CDP settings go in `config.psd1`.

Unknown top-level commands fail before native execution. Commands use command-first syntax; reserved routing-like argument tokens are rejected conservatively even if intended as literal text. Use page evaluation when a literal reserved token must be entered. MCP, plugin management, dashboard, chat and restore workflows require separate deliberate integration; they do not inherit this wrapper's guarantees when called directly.

## Persistent display modes and login

`auth start [url]` defaults to headed. Use `auth start [url] --headless` for background work with the same managed profile, or `--headed` for a window. `auth status` derives `Headless` from the verified Chrome process, not from the last requested option. A mode mismatch leaves the existing browser and page unchanged: close only your task-owned instance with `auth stop`, then start the other mode. Never work around the check by launching a second Chrome on the same profile. After a manual close, check status before restarting; if native commands report a stale reserved CLI connection, use targeted `auth stop`/status diagnosis rather than global cleanup.

Saved login is site-dependent. First login, MFA, CAPTCHA and session expiration may require headed operation and user input. Tests validate only synthetic cookies and localStorage in a temporary profile; they do not establish every website's login compatibility. Login data remains on the computer and is not installed from Git.

## Windows doctor

Earlier local validation found that Chrome for Testing 150 could leave a GUI `chrome --version` process running and block doctor. That is historical evidence, not a claim about every current Chrome build. Doctor also auto-cleans stale files upstream. Do not run it as routine read-only diagnostics. The existing bounded maintenance path remains available only for an explicitly authorized maintenance task, with exact PID/process evidence and no broad termination.

## Recovery

The installer backs up replaced runtime files and the command shim under the installation's `backups/<timestamp>/`. It preserves machine config, profiles, logs and runtime state. Restore only the specific replaced code files if rollback is needed; never restore or copy authentication data from this repository. Installation does not modify PATH, npm packages, Node selection or running browser sessions.
