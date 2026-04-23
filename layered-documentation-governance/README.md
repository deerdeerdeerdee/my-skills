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

## Examples

See [SKILL.md](./SKILL.md) for detailed examples including:

- Hard constraint introduction (WebRTC B-frame limitation)
- Tech stack change (pip → uv migration)
- New subdirectory creation (edge-agent C++ component)
- Phase transition (P1 → P2)

## License

MIT
