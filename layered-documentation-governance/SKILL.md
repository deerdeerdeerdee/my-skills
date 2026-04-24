---
name: layered-documentation-governance
description: PROACTIVELY maintain CLAUDE.md/AGENTS.md whenever users complete features, add files/directories, notice stale docs, or create components. Triggers on questions ('should there be...?', 'do we need to update...?'), problems ('says X but actually Y', 'outdated', 'too long'), and completion signals ('finished X', 'completed P1', 'added Y'). Use this skill even if the user doesn't explicitly mention documentation - if they just completed work or added files, check if docs need updating. Maintains layered structure across project directories.
---

# Layered Documentation Governance

Maintain CLAUDE.md and AGENTS.md across a project's directory tree. Keep them synchronized, relevant, and concise.

## Output Contract

When invoked, use this two-stage structure to ensure your recommendations are actionable:

### Stage 1 — Decision (concise)

The three-question test helps you avoid over-documentation (which creates maintenance burden) while catching genuine pitfalls. Answer all three:

```
## Three-Question Test

1. Would a new person/agent hit a pitfall without this info? → [Yes/No - one-line reason]
2. Is this info already in code or detailed docs? → [Yes/No - one-line reason]
3. Will this still be valid in 6 months? → [Yes/No - one-line reason]

**Decision**: [Update / Skip / Defer]
```

### Stage 2 — Execution Plan (only if Decision is Update or Create)

Provide an actionable plan that a follow-up agent can execute without re-analysis. For each file to modify or create:

```
## Execution Plan

### File: <path>
**Why**: 1-line justification
**Action**: Create / Update section "X" / Add new section
**Key content** (bullets of what to include, not full prose):
- Point 1 with concrete value (e.g., "bframes=0, tune=zerolatency")
- Point 2 with command example
- Link to: `docs/<path>` for depth

### File: <next path>
...
```

**Rules for Stage 2**:
- Include **concrete values, commands, code snippets** that the follow-up agent needs (not just "add a section about X")
- Describe content as bullets, not full markdown prose — the follow-up agent will format
- Always link to authoritative `docs/` where detail lives
- If creating a new file, list the main sections it should contain
- Keep each file entry under 10 lines

If Decision is **Skip** or **Defer**, omit Stage 2 and give a 1-2 sentence reason.

**Total response length target**: 15-60 lines depending on scope. Skip decisions should be shortest (≤15 lines). Multi-file updates may reach 60 lines.

## Decision Rules

**Update** when the answer pattern is (Yes, No, Yes). All three must match.

**Skip** when any of these are true:
- Info is already in code/docs (duplication)
- It's a temporary experiment, one-off fix, or short-term workaround
- It's obvious (e.g., "Python files end in .py")
- It will be stale in months (specific versions, temporary URLs)

## Holistic Update Principle

When updating documentation, updating related existing files prevents documentation rot. Here's why: if you only add new content without updating old content, agents consulting the old files will miss the new information, leading to inconsistent behavior across the codebase.

**Anti-pattern** (patching):
- Add ADR-0005 ✓
- Add new section to edge-agent.md ✓
- **Forget to update web-console/CLAUDE.md** ✗ ← This causes documentation rot

**Correct approach** (holistic update):
- Add ADR-0005 ✓
- **Update** edge-agent.md (modify existing timestamp constraint) ✓
- **Update** media-gateway.md (rewrite timestamp section) ✓
- **Update** web-console.md (rewrite time alignment section) ✓
- **Update** root CLAUDE.md/AGENTS.md ✓
- **Update** subdirectory CLAUDE.md/AGENTS.md if affected ✓

### Update Checklist

When making significant changes (new ADR, phase transition, major feature), check ALL of:

```
□ Root CLAUDE.md / AGENTS.md (always sync both)
□ Affected subdirectory CLAUDE.md / AGENTS.md
□ docs/00-overview/03-phase-plan.md (if phase-related)
□ Related component design docs (docs/20-components/)
□ Related ADRs (docs/10-decisions/)
□ Related operations docs (docs/40-operations/)
```

**Detection**: If you find yourself only creating new files without modifying existing ones, STOP and ask: "What existing docs need updating?"

## Scope Rules

**Root CLAUDE.md/AGENTS.md** — cross-cutting content:
- Project overview, current phase
- Architecture, design decisions (link to ADRs)
- Cross-component constraints (encoding, network, time sync)
- Index to subdirectory docs
- **Length target**: <150 lines (keep it scannable, link to details)

**Subdirectory CLAUDE.md/AGENTS.md** — tech-stack-specific content:
- Local commands, dependency management
- Code style and conventions
- Component-specific constraints
- **Length target**: <100 lines per file

**CREATE** a new subdirectory doc pair only when:
- A new top-level implementation directory is added, AND
- It has an independent tech stack / language / responsibility domain

Do NOT create for sub-modules (e.g., `app/api/`, `src/components/`).

## Sync Rule

CLAUDE.md and AGENTS.md should contain equivalent content to ensure consistency across different agent systems. When you update one, update the other in the same turn to prevent divergence.

## Division of Labor with `docs/`

| Content | Location |
|---------|----------|
| Decisions (why) | `docs/10-decisions/ADR-*.md` |
| Designs (what) | `docs/20-components/*.md` |
| Contracts (integration) | `docs/30-contracts/*.md` |
| Operations (how) | `docs/40-operations/*.md` |
| **How agents code here** | **CLAUDE.md / AGENTS.md** |
| **Critical constraints quick-ref** | **CLAUDE.md / AGENTS.md** |

CLAUDE.md/AGENTS.md is an **index**, not detailed documentation. Link to `docs/` for depth.

## Staleness Detection

Before adding new content, check for **outdated information** that needs updating:

**Red flags** (indicates stale content):
- "Phase X in progress" when X is actually completed
- Missing recently added files/features in project structure
- Old tech stack references (e.g., "pip" when project uses "uv")
- Outdated status markers (🔄 when should be ✅)

**When you detect staleness**:
1. Update the stale content FIRST
2. Then add new content
3. Include both in your execution plan

**Example**: If adding multi-player.html to web-console, check if web-console/CLAUDE.md still says "P1 in progress" — if so, update that too.

## When NOT to Use This Skill

Skip this skill for:

- **Code-only changes**: Refactoring that doesn't change behavior or add constraints
- **Documentation in `docs/`**: This skill is for CLAUDE.md/AGENTS.md, not detailed docs
- **Temporary debugging**: Adding console.log or temporary print statements
- **In-progress work**: Wait until the feature is stable before documenting
- **Self-documenting code**: Well-named functions/variables don't need CLAUDE.md entries
- **One-off scripts**: Throwaway automation that won't be reused
- **Dependency updates**: Routine package bumps without API changes

## Examples

### Hard constraint (Update, multi-file)

Prompt: "WebRTC requires H.264 Constrained Baseline (no B-frames)."

```
## Three-Question Test
1. Pitfall? → Yes (default encoding uses B-frames; streams silently rejected)
2. Already in docs? → No (new finding)
3. Valid in 6mo? → Yes (RFC 7742 requirement)

**Decision**: Update

## Execution Plan

### File: CLAUDE.md (root) + AGENTS.md (root)
**Why**: Cross-cutting constraint, agents must know at a glance
**Action**: Add new section "Video Encoding Constraints"
**Key content**:
- H.264 Constrained Baseline only (no B-frames)
- Encoder flags: `bframes=0`, `tune=zerolatency`, `profile=baseline`
- RTSP transport: TCP (UDP causes Broken pipe under load)
- Reason: WebRTC RFC 7742, MediaMTX rejects B-frame streams
- Link to: `docs/40-operations/webrtc-bframes-compatibility.md`

### File: docs/40-operations/webrtc-bframes-compatibility.md
**Why**: Detailed rationale belongs in ops docs, not quick-ref
**Action**: Create new file
**Key content**:
- Symptom: MediaMTX logs "WebRTC doesn't support H264 streams with B-frames"
- Root cause: RFC 7742 + WebRTC codec requirements
- Wrong fix: Real-time re-encode (500% CPU)
- Correct fix: Source-level `bframes=0`
- Verification: `ffprobe -show_frames input.mp4 | grep pict_type`
- GStreamer example: `x264enc bframes=0 tune=zerolatency speed-preset=veryfast`

### File: docs/20-components/edge-agent.md
**Why**: Enforce at encoder level in VideoSource abstraction
**Action**: Add encoding parameters table to "stream" module section
**Key content**: Table with Codec / Profile / B-frames / GOP / Tune / RTSP transport columns
```

### Tech stack change (Update component)

Prompt: "Backend switched from pip to uv."

```
## Three-Question Test
1. Pitfall? → Yes (agents would try pip commands, which fail)
2. Already in docs? → No (only pyproject.toml reflects the change)
3. Valid in 6mo? → Yes (architectural choice)

**Decision**: Update

## Execution Plan

### File: backend-api/CLAUDE.md + backend-api/AGENTS.md
**Why**: Component-level commands, agents run these daily
**Action**: Replace "Dependency Management" section
**Key content**:
- Add dependency: `uv add <package>`
- Add dev dependency: `uv add --dev <package>`
- Install from lock: `uv sync`
- Run command: `uv run uvicorn app.main:app --reload`
- Update lock: `uv lock --upgrade`
- Note: Do NOT use `pip install`; pyproject.toml + uv.lock are authoritative

### File: backend-api/requirements.txt
**Why**: Stale artifact that contradicts pyproject.toml
**Action**: Delete (and any `:Zone.Identifier` siblings)
```

### New component (Update + Create)

Prompt: "Starting edge-agent/ in C++20."

```
## Three-Question Test
1. Pitfall? → Yes (agents won't know C++ build, GStreamer patterns, edge constraints)
2. Already in docs? → Partially (design in `docs/20-components/edge-agent.md`)
3. Valid in 6mo? → Yes (permanent component)

**Decision**: Update + Create

## Execution Plan

### File: edge-agent/CLAUDE.md + edge-agent/AGENTS.md (CREATE)
**Why**: New tech stack (C++20/CMake/GStreamer), own build flow
**Action**: Create synced pair, ~150 lines each
**Sections to include**:
- Quick Start: `cmake -B build && cmake --build build`
- Project structure: src/, include/, configs/, tests/
- Tech Stack: C++20, CMake, GStreamer, yaml-cpp, nlohmann/json, spdlog, ixwebsocket
- Critical constraints (quick-ref, link to full docs):
  - H.264 Constrained Baseline, `bframes=0` at source
  - RTSP push over TCP (`protocols=tcp`)
  - Wall-clock PTS for multi-stream alignment
  - WebSocket reconnect, must not stop video on control disconnect
- Code style: C++ Core Guidelines, spdlog logging
- Common tasks: add new VideoSource, add new PtzDriver
- Link to: `docs/20-components/edge-agent.md`, `docs/10-decisions/ADR-0001-edge-agent-language-cpp.md`

### File: CLAUDE.md (root) + AGENTS.md (root)
**Why**: Update component index
**Action**: Edit "Component-Specific Guidelines" section
**Key content**:
- Change edge-agent status from "future" to "skeleton in progress"
- Add: `edge-agent/CLAUDE.md - C++20 embedded agent`
```

### Phase transition (Update root)

Prompt: "Completed P1, moving to P2."

```
## Three-Question Test
1. Pitfall? → Yes (agents would work on outdated P1 priorities)
2. Already in docs? → No (status is stale)
3. Valid in 6mo? → Yes (until next transition)

**Decision**: Update

## Execution Plan

### File: CLAUDE.md (root) + AGENTS.md (root)
**Why**: Current status and next-step priorities must be fresh
**Action**: Edit "Current Status" and "Phase Goals" sections
**Key content**:
- Status: `**Phase**: P2 (Device access and status plane) - In Progress`
- Add "Phase 1 Completion" summary (4-6 bullets of what shipped)
- Update "Next Steps" to P2 goals: Agent registration, heartbeat, camera/clock status reporting, frontend device overview
- Mark P1 as ✅ Completed with date

### File: docs/00-overview/03-phase-1-plan.md (if exists)
**Why**: Phase plan tracks stage completion
**Action**: Update stage markers (P1 → 🔄 to ✅)

### File: web-console/CLAUDE.md + web-console/AGENTS.md
**Why**: Subdirectory docs must reflect P1 completion (holistic update, not just root)
**Action**: Update "Current Status" section
**Key content**:
- Status: P1 ✅ Completed
- Add P1 deliverables (multi-player.html, etc.)
```

### Holistic update example (correct approach)

Prompt: "Added multi-stream playback feature (multi-player.html)."

```
## Three-Question Test
1. Pitfall? → Yes (agents won't know about new page, web-console/CLAUDE.md is stale)
2. Already in docs? → No (new feature)
3. Valid in 6mo? → Yes (core feature)

**Decision**: Update

## Execution Plan

### File: web-console/CLAUDE.md + web-console/AGENTS.md
**Why**: Subdirectory docs are stale (missing multi-player.html, status outdated)
**Action**: Update "Current Pages" section AND "Current Status" section
**Key content**:
- Add multi-player.html to page list (⭐ P1 Deliverable)
- Update status from "P1 in progress" to "P1 ✅ Completed"
- Update project structure to include multi-player.html

### File: CLAUDE.md (root) + AGENTS.md (root)
**Why**: Root docs need P1 completion summary
**Action**: Update "Current Status" section
**Key content**:
- Status: P1 ✅ Completed (2026-04-24)
- Add P1 deliverables: multi-stream playback, WebRTC <1s latency, etc.

### File: docs/00-overview/03-phase-1-plan.md
**Why**: Phase plan needs completion marker
**Action**: Update P1 section
**Key content**:
- Change P1 from 🔄 to ✅
- Add completion date
```

**Note**: This is holistic update (3 locations), not patching (just adding multi-player.html).

### Temporary experiment (Skip)

Prompt: "Experimenting with Redis, not sure if we'll keep it."

```
## Three-Question Test
1. Pitfall? → No (nothing stable to document yet)
2. Already in docs? → N/A
3. Valid in 6mo? → No (experimental)

**Decision**: Skip

Experiments don't belong in CLAUDE.md. Document after the decision is finalized — then add commands to `backend-api/CLAUDE.md` and (if introducing constraints) an ADR in `docs/10-decisions/`.
```

### One-off bug fix (Skip)

Prompt: "Fixed a null pointer with a one-line null check."

```
## Three-Question Test
1. Pitfall? → No (standard defensive programming, not an architectural constraint)
2. Already in docs? → N/A
3. Valid in 6mo? → N/A

**Decision**: Skip

The fix is self-documenting in code. Document only if the bug reveals a systemic pattern (e.g., "all gRPC responses need null checks") that agents writing new code need to know.
```

## Tricky Cases

### When scope is unclear

Prompt: "Added retry logic to API client."

**Question**: Is this cross-cutting (root) or component-specific (subdirectory)?

**Answer**: Check if other components use this API client. If yes → root (cross-cutting constraint). If no → subdirectory only.

```
## Three-Question Test
1. Pitfall? → Yes (agents might not know about retry behavior)
2. Already in docs? → No
3. Valid in 6mo? → Yes

**Decision**: Update

## Execution Plan

### File: backend-api/CLAUDE.md + backend-api/AGENTS.md
**Why**: API client is used only within backend-api
**Action**: Add to "Common Patterns" section
**Key content**:
- API client has automatic retry with exponential backoff
- Max 3 retries, 1s/2s/4s delays
- Retries on 5xx and network errors only
- Link to: `src/utils/api_client.py` for implementation
```

### When staleness is partial

Prompt: "The backend-api/CLAUDE.md mentions both pip and uv commands."

**Question**: Should I update just the pip parts or the whole section?

**Answer**: Update the whole section. Partial migration creates confusion.

```
## Three-Question Test
1. Pitfall? → Yes (mixed commands will confuse agents)
2. Already in docs? → Partially (contradictory info)
3. Valid in 6mo? → Yes

**Decision**: Update

## Execution Plan

### File: backend-api/CLAUDE.md + backend-api/AGENTS.md
**Why**: Partial staleness is still staleness
**Action**: Replace entire "Dependency Management" section
**Key content**:
- Remove ALL pip references
- Keep only uv commands
- Note: "Do NOT use pip install; pyproject.toml + uv.lock are authoritative"
```

### When multiple docs conflict

Prompt: "Root CLAUDE.md says use TCP for RTSP, but edge-agent/CLAUDE.md says UDP is fine."

**Question**: Which one is correct?

**Answer**: Investigate first, then update both to match reality.

```
## Three-Question Test
1. Pitfall? → Yes (conflicting guidance causes bugs)
2. Already in docs? → Yes but contradictory
3. Valid in 6mo? → Yes (once resolved)

**Decision**: Update (after investigation)

## Execution Plan

### Step 1: Investigate
- Check git history: when/why was each added?
- Check actual code: what does edge-agent use?
- Check docs/40-operations/: any troubleshooting guides?

### Step 2: Update both files
**File**: CLAUDE.md (root) + edge-agent/CLAUDE.md
**Why**: Conflicting docs are worse than no docs
**Action**: Update both to reflect correct constraint
**Key content**: (depends on investigation result)
```

## Anti-Patterns

- **Don't patch, update holistically** — when adding new content, update related existing docs
- **Don't duplicate `docs/`** — link to it instead
- **Don't dump full file contents** — describe changes in 1 line
- **Don't add temporary notes** — wait for decisions
- **Don't skip the sync** — always update CLAUDE.md AND AGENTS.md together
- **Don't write long explanations** — be terse; the user can ask for details
- **Don't ignore staleness** — if you see outdated info, flag it in your plan
- **Don't let root CLAUDE.md bloat** — if >150 lines, suggest refactoring to subdirectory docs

## Principle

The goal is useful quick-reference docs that agents actually consult. Long manuals get ignored. Keep it short, link outward, sync both files.

**Core philosophy**: Documentation is a living system, not a patch collection. When you add new content, update related existing content to keep the whole system coherent. Stale docs are worse than no docs — they mislead agents and waste time.

**Quality over quantity**: A concise, up-to-date 100-line CLAUDE.md beats a bloated, stale 300-line version.
