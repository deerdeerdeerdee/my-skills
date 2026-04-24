# Layered Documentation Governance Skill

A Claude Code / Codex skill for maintaining layered CLAUDE.md and AGENTS.md files across project directories.

## Overview

This skill helps prevent documentation rot in multi-agent collaborative projects by:

- **Layered structure**: Root-level global docs + subdirectory-specific docs
- **Dual-file sync**: Keeps CLAUDE.md and AGENTS.md synchronized
- **Intelligent triggers**: Uses a "three-question test" to decide when to update
- **Clear division of labor**: Distinguishes between agent context files and detailed `docs/`

## Installation

### Via Claude Code

```bash
npx skills add deerdeerdeerdee/my-skills@layered-documentation-governance
```

### Manual Installation

```bash
git clone https://github.com/deerdeerdeerdee/my-skills.git
cp -r my-skills/layered-documentation-governance ~/.claude/skills/
```

## When to Use

This skill triggers when:

1. User explicitly requests documentation updates
2. Hard constraints are introduced (e.g., "must use X")
3. Major tech stack changes (e.g., pip → uv)
4. Directory structure or naming conventions change
5. Significant bug fixes reveal architectural constraints
6. Phase transitions (e.g., P1 → P2)
7. User asks "should I document this?"

## Key Principles

### The Three-Question Test

Before updating any documentation:

1. Would a new person/agent hit a pitfall without this info?
2. Is this info already in code or detailed docs?
3. Will this still be valid in 6 months?

Only update when: (yes, no, yes)

### Layered Structure

```
project-root/
├── CLAUDE.md              # Global: architecture, cross-cutting constraints
├── AGENTS.md              # Global: same content as CLAUDE.md
├── <component>/
│   ├── CLAUDE.md          # Local: tech-stack specific
│   └── AGENTS.md          # Local: same content
└── docs/                  # Detailed docs (separate from agent context)
```

### Division of Labor with `docs/`

| Content | Location |
|---------|----------|
| Why (decisions) | `docs/10-decisions/ADR-*.md` |
| What (designs) | `docs/20-components/*.md` |
| How to integrate | `docs/30-contracts/*.md` |
| How to operate | `docs/40-operations/*.md` |
| **How agents code here** | **CLAUDE.md / AGENTS.md** |
| **Critical constraints** | **CLAUDE.md / AGENTS.md** |

## Bundled Resources

This skill includes automation tools to help maintain documentation quality:

### Staleness Detection Script

`scripts/check_staleness.py` - Automated documentation health checker

**Features**:
- Detects outdated status markers ("P1 in progress" when completed)
- Finds missing new files in project structure sections
- Identifies tech stack mismatches (pip vs uv, npm vs yarn)
- Checks file length limits (root <150 lines, subdirs <100 lines)
- Verifies CLAUDE.md/AGENTS.md synchronization
- Scans for references to non-existent files

**Usage**:
```bash
# From project root
python /path/to/skill/scripts/check_staleness.py

# With verbose output
python /path/to/skill/scripts/check_staleness.py --verbose

# Check specific directory
python /path/to/skill/scripts/check_staleness.py --root /path/to/project
```

**Example output**:
```
📋 Staleness Report (3 issues)

⚠️ WARNING (2)
  web-console/CLAUDE.md
    Status says "P1 in progress" but should be "P1 ✅ Completed"
    💡 Check git log and update status if phase is completed

  CLAUDE.md:287
    287 lines (target: <150 lines)
    💡 Consider refactoring details to subdirectory docs or docs/

ℹ️ INFO (1)
  web-console/CLAUDE.md
    Recent addition 'multi-player.html' not mentioned in docs
    💡 Consider adding to project structure or relevant section
```

### Update Checklist Template

`references/checklist-template.md` - Standardized update checklist

**Use when**:
- Making significant documentation changes
- Ensuring holistic updates (not just patching)
- Verifying all related files are updated

**Includes**:
- Core files checklist (root, subdirectories, docs/)
- Staleness verification steps
- Sync verification (CLAUDE.md ↔ AGENTS.md)
- Common scenario checklists (new feature, phase transition, tech stack change)
- Anti-patterns to avoid

## Examples

See [SKILL.md](./SKILL.md) for detailed examples including:

- Hard constraint introduction (WebRTC B-frame limitation)
- Tech stack change (pip → uv migration)
- New subdirectory creation (edge-agent C++ component)
- Phase transition (P1 → P2)

## CI Integration

You can integrate the staleness checker into your CI pipeline:

```yaml
# .github/workflows/docs-check.yml
name: Documentation Check
on: [pull_request]
jobs:
  check-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check documentation staleness
        run: |
          python ~/.claude/skills/layered-documentation-governance/scripts/check_staleness.py
```

Or as a pre-commit hook:

```bash
# .git/hooks/pre-commit
#!/bin/bash
python ~/.claude/skills/layered-documentation-governance/scripts/check_staleness.py
if [ $? -ne 0 ]; then
    echo "Documentation staleness detected. Please fix before committing."
    exit 1
fi
```

## License

MIT
