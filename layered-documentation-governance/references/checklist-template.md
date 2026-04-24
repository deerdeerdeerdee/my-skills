# Documentation Update Checklist

Use this checklist when making significant changes to ensure holistic updates across all related documentation.

## Core Files to Check

When making significant changes (new ADR, phase transition, major feature, tech stack change), verify ALL of:

- [ ] **Root CLAUDE.md** - Updated with cross-cutting changes
- [ ] **Root AGENTS.md** - Synced with CLAUDE.md (equivalent content)
- [ ] **Affected subdirectory CLAUDE.md** - Component-specific updates
- [ ] **Affected subdirectory AGENTS.md** - Synced with subdirectory CLAUDE.md
- [ ] **docs/00-overview/03-phase-plan.md** - Phase status markers (if phase-related)
- [ ] **Related component design docs** (docs/20-components/) - Detailed design updates
- [ ] **Related ADRs** (docs/10-decisions/) - Architecture decision records
- [ ] **Related operations docs** (docs/40-operations/) - Deployment/ops guides

## Staleness Checks

Before adding new content, verify existing documentation is current:

- [ ] **No outdated status markers** - "in progress" when completed, 🔄 when should be ✅
- [ ] **All new files mentioned** - Recent additions appear in project structure sections
- [ ] **Tech stack references accurate** - Commands match actual tools (pip vs uv, npm vs yarn)
- [ ] **No missing features** - Recently added functionality is documented
- [ ] **File paths valid** - Referenced files/directories still exist
- [ ] **Length within limits** - Root <150 lines, subdirectories <100 lines

## Sync Verification

- [ ] **CLAUDE.md ↔ AGENTS.md pairs synced** - Both files contain equivalent content
- [ ] **Modification times similar** - Both files updated in same commit
- [ ] **Content consistency** - No contradictions between paired files

## Content Quality

- [ ] **Links to docs/** - Detailed content lives in docs/, not duplicated in CLAUDE.md
- [ ] **Concrete examples** - Commands, flags, file paths included where relevant
- [ ] **Quick-reference format** - Scannable, not verbose
- [ ] **No temporary notes** - Only stable, validated information

## Common Scenarios

### Adding a New Feature

- [ ] Update subdirectory CLAUDE.md/AGENTS.md with feature details
- [ ] Update root CLAUDE.md/AGENTS.md if cross-cutting
- [ ] Add to project structure section
- [ ] Link to relevant docs/ if detailed design exists

### Phase Transition (e.g., P1 → P2)

- [ ] Update "Current Status" in root CLAUDE.md/AGENTS.md
- [ ] Update "Current Status" in affected subdirectory docs
- [ ] Update docs/00-overview/03-phase-plan.md markers
- [ ] Add phase completion summary with deliverables

### Tech Stack Change (e.g., pip → uv)

- [ ] Update subdirectory CLAUDE.md/AGENTS.md commands
- [ ] Remove/update stale artifacts (requirements.txt)
- [ ] Update "Tech Stack" or "Dependency Management" sections
- [ ] Verify no references to old tool remain

### New Component/Directory

- [ ] Create new CLAUDE.md in component directory
- [ ] Create paired AGENTS.md with equivalent content
- [ ] Update root CLAUDE.md/AGENTS.md index
- [ ] Add component to project structure overview

### New ADR or Operations Guide

- [ ] Create ADR/guide in docs/
- [ ] Update root CLAUDE.md/AGENTS.md if introduces constraint
- [ ] Update affected component docs with reference
- [ ] Add to relevant sections (constraints, operations, etc.)

## Anti-Patterns to Avoid

- [ ] **Not patching** - Updated related existing docs, not just added new ones
- [ ] **Not duplicating docs/** - Linked to detailed docs instead of copying
- [ ] **Not skipping sync** - Updated both CLAUDE.md AND AGENTS.md
- [ ] **Not ignoring staleness** - Fixed outdated info found during update
- [ ] **Not letting docs bloat** - Refactored if files exceed length targets

## Automation

Run automated staleness check:

```bash
# From skill directory
python scripts/check_staleness.py --root /path/to/project

# Or from project root
python /path/to/skill/scripts/check_staleness.py
```

## Notes

- This checklist is a guide, not all items apply to every change
- Use judgment to determine which sections are relevant
- When in doubt, err on the side of updating more rather than less
- Holistic updates prevent documentation rot
