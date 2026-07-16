---
name: layered-documentation-governance
description: Proactively keep a repository's documentation coherent with its implementation and lifecycle. Use after completing or changing features, fixes, schemas, configuration, operations, components, files, phases, releases, or validation work; when documentation is stale, duplicated, patch-like, contradictory, oversized, or poorly routed; and when asked whether README, docs, ADRs, runbooks, AGENTS.md, or CLAUDE.md should change. Perform scoped same-change convergence, update existing authorities, synchronize agent-guide pairs, and retire superseded content instead of merely proposing more documents.
---

# Layered Documentation Governance

Keep documentation coherent as part of the change that affects it. Prefer a small set of explicit authorities over additive notes, permanent planning snapshots, or periodic cleanup campaigns.

## Start With Repository Policy

1. Read the applicable `AGENTS.md`, `CLAUDE.md`, documentation index, and repository-specific governance rules before judging structure or editing files.
2. Inspect the worktree and relevant diff or recent change. Preserve unrelated user changes.
3. Respect the user's requested action. For an audit or explanation, report evidence without writing. For an authorized change or completed feature, execute documentation convergence and validation in the same turn.
4. Use repository-specific authorities and checks when they exist. Do not impose the directory examples in this skill as a fixed taxonomy.

## Select The Scope

- For a normal feature or fix, review the semantic impact surface: changed code plus the nearby authorities that describe its behavior, contract, operation, constraints, status, or evidence. Do not turn every change into a full-repository audit.
- For a deep-governance request, release or phase closeout, large merge, authority-boundary change, or observed widespread drift, inventory and semantically read the full documentation tree before restructuring it.
- Include detailed `docs/` content. Documentation governance is not limited to `AGENTS.md` and `CLAUDE.md`.
- Read relevant documents completely enough to understand their ownership and lifecycle. Search and scripts can locate candidates but cannot determine semantic correctness.

## Route Facts By Ownership

Do not use one global source-priority list for every fact. Adapt this ownership model to the repository:

| Fact kind | Typical owner |
| --- | --- |
| Exact routes, fields, schemas, defaults, and implementation behavior | Code, generated API/schema output, migrations, config, and tests |
| Accepted architectural intent and tradeoffs | ADRs and architecture overview |
| Current component responsibilities and integration semantics | Component and contract documents |
| Executable deployment, upgrade, validation, and recovery procedures | Current scripts/config plus the owning runbook |
| Current phase, queue, acceptance state, and evidence | One explicitly designated summary, queue, or ledger per concern |
| Agent workflow, commands, durable constraints, and costly pitfalls | Nearest applicable `AGENTS.md` / `CLAUDE.md` quick reference |
| Historical context | Deliberate archive or Git history, never a current authority |

When sources conflict, determine which one owns that kind of fact. Exact implementation details are verified in code, but code that violates an accepted safety or architecture invariant may be the defect. Resolve the discrepancy in the owning source; do not add a conflict-explaining patch document.

## Classify Documentation Impact

Classify the completed change before closing it:

- `none`: Only when the change is internal and introduces no durable user behavior, interface, data, configuration, operational, architecture, safety, workflow, status, or evidence delta.
- `update`: An existing authority must be rewritten to match the final change.
- `retire`: Existing content or files are superseded, redundant, misleading, or temporary and must be removed after durable facts are preserved.

A change may require both `update` and `retire`. "The fact is visible in code" does not by itself mean `none`; code and documents own different kinds of facts.

## Converge In The Same Change

1. Derive the final semantic delta from code, tests, migrations, configuration, scripts, runtime evidence, and the user's acceptance boundary.
2. Map each durable fact to one owner. Identify other files that duplicate it, route to it, or will become stale.
3. Update the existing owner's complete section in place. Replace old conclusions rather than appending dated notes, correction blocks, or follow-up sections.
4. Remove superseded paragraphs, checklists, temporary specs/plans, stale examples, and patch documents after incorporating any still-valid facts.
5. Update the nearest navigation index for added, renamed, moved, or removed authorities.
6. Synchronize affected `AGENTS.md` / `CLAUDE.md` pairs in the same change when the repository requires equivalent pairs.
7. Re-read the changed sections and adjacent authorities for contradictions, duplication, mixed current/history state, and paths or commands that no longer work.
8. Run repository-specific mechanical checks only after semantic review. Treat their success as evidence of syntax and linkage health, not proof of correctness.

Do not defer steps 2-7 to a later documentation cleanup unless the user explicitly separates the work.

## Gate New Documents

Create a new document only when all of these are true:

- No existing authority can carry the content clearly through a rewrite or focused new section.
- The file has one distinct responsibility, audience, owner, and update trigger.
- The nearest index will route readers to it in the same change.
- Its authority and lifecycle are clear. Temporary artifacts have an explicit retirement event.
- The new boundary reduces duplication and cognitive load rather than splitting one topic across more files.

Do not create `fix`, `follow-up`, `addendum`, `v2-current`, or date-suffixed current documents merely to avoid editing an existing authority. Keep short-lived execution detail in the task system when the repository permits it.

## Apply Lifecycle Rules

- Current overview and component docs describe the system as it is now. Remove branch transcripts, implementation diaries, completed checkboxes, and successive dated conclusions.
- ADRs preserve accepted decisions and rationale. Amend or supersede them deliberately; do not use them as progress logs.
- Contract docs own durable semantics. Prefer generated schemas and code references for exhaustive field-level truth when available.
- Runbooks contain executable prerequisites, steps, decisions, rollback, and verification. Keep one-off command output and repeated smoke transcripts in evidence storage, not in the procedure.
- Status, queue, and evidence are different concerns. Give each one owner and link between them instead of copying states everywhere.
- Agent guides are concise quick references. Keep navigation, daily commands, durable constraints, and non-obvious costly pitfalls; link to depth and avoid transient progress.
- Archives require continuing audit, legal, protocol-version, or historical decision value. Git history is sufficient for ordinary superseded prose and completed plans.

## Delete And Consolidate Safely

Before moving or deleting a tracked document:

1. Search current references by path, filename, title, and distinctive terms.
2. Read the candidate and preserve any unique durable fact in its owner.
3. Update links, indexes, and replacement routing in the same change.
4. Confirm code, tests, installers, runbooks, and automation do not depend on the file.
5. Use Git history for recovery unless repository policy requires an archive.

Do not archive by default. Moving every stale file to an archive preserves the same search and maintenance burden under a new path.

## Deep Governance Workflow

For an explicitly broad audit:

1. Inventory all current documentation, agent guides, indexes, generated references, and archives.
2. Read documents semantically by domain and compare them with current code, configuration, migrations, scripts, and tests.
3. Classify each file as `keep`, `rewrite`, `merge`, `delete`, or `archive`, with a named replacement authority for every merge/delete.
4. Execute the smallest coherent restructuring that restores one owner per fact and clear navigation.
5. Search for removed names and stale concepts, then run repository checks.
6. Report reductions, remaining authorities, validation performed, and any runtime facts that could not be verified.

File counts and line counts can describe the result, but they are not governance goals. Optimize reader effort, correctness, and update cost.

## Report The Outcome

For completed changes, include a concise final record:

```text
Documentation impact: none | update | retire | update + retire
Authorities changed: <paths or none>
Content retired: <paths/sections or none>
Validation: <semantic checks and mechanical commands>
```

For audits, lead with concrete drift, duplication, ownership, and lifecycle findings. Do not force a planning template when the user asked for implementation, and do not claim documentation health from scripts alone.
