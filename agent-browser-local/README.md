# agent-browser-local

A small companion to the official agent-browser skill: it defaults to a fixed persistent work profile and describes profile selection for concurrent tasks. All browser operations use the native CLI. There are no companion scripts, command filters, runtime installer, fixed CDP port, or extra daemon.

## Installation

Install the official agent-browser skill, CLI, and browser using the upstream instructions. Install this companion as ordinary skill instructions:

```bash
npx skills add deerdeerdeerdee/my-skills@agent-browser-local
```

To make the convention discoverable across projects, add this to your agent's user-level instructions (for Codex, `~/.codex/AGENTS.md`):

> When using agent-browser locally, also read the agent-browser-local skill and invoke the native CLI directly. Default to the persistent work profile under the current user home at `.agent-browser/profiles/work`, including frontend tests; use clean sessions only when isolation is required. For concurrency, follow the skill’s default/named/temporary profile conventions and task ownership rules. Choose headed/headless independently; do not set global profile/session defaults.

[SKILL.md](SKILL.md) owns the default/named/temporary profile conventions, task ownership and concurrency rules, mode selection, native command examples and lifecycle rules. These are instructions rather than an atomic lock or scheduler; newly created profiles need their own login when required. The same directory convention is portable; login data is machine-local.

On Windows, if a launch waits indefinitely only when assigned to a PowerShell output variable or piped to `Out-Null`, invoke the CLI directly as shown in the skill. Some versions leave output handles inherited by the background daemon. Check the task's existing session before retrying; this symptom alone does not establish an OS permission failure.

## Updating an older wrapper installation

Update the installed skill and any user/project instructions that require the old `agent-browser-local` command or runtime `POLICY.md`. The old PowerShell wrapper, installer, regression runner and reference files have been retired from this package; Git history preserves them. Older local code can be archived outside the installed skill for rollback. Nothing needs to be installed beyond the upstream tool and skill instructions.

The existing work profile already uses the same directory, so it does not need moving, exporting or clearing. Close any old task-owned browser before opening that profile with the native CLI. Keep profiles, credentials, configs, logs and backups out of this repository.
