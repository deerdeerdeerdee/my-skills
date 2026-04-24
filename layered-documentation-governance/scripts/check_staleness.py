#!/usr/bin/env python3
"""
Automatic staleness detection for CLAUDE.md and AGENTS.md files.

Scans project directories for documentation issues:
- Outdated status markers (P1 in progress when completed)
- Missing new files in project structure
- Tech stack mismatches (pip vs uv, etc.)
- Oversized documentation files
- Unsynchronized CLAUDE.md/AGENTS.md pairs

Usage:
    python check_staleness.py [--root /path/to/project] [--fix] [--verbose]
"""

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple, Optional


@dataclass
class Issue:
    """Represents a documentation staleness issue."""
    severity: str  # 'error', 'warning', 'info'
    file: str
    line: Optional[int]
    message: str
    suggestion: Optional[str] = None


class StalenessChecker:
    def __init__(self, root: Path, verbose: bool = False):
        self.root = root
        self.verbose = verbose
        self.issues: List[Issue] = []

    def log(self, msg: str):
        if self.verbose:
            print(f"[DEBUG] {msg}", file=sys.stderr)

    def find_doc_files(self) -> List[Path]:
        """Find all CLAUDE.md and AGENTS.md files."""
        docs = []
        for pattern in ['**/CLAUDE.md', '**/AGENTS.md']:
            docs.extend(self.root.glob(pattern))
        return sorted(set(docs))

    def check_status_markers(self, file: Path, content: str):
        """Check for outdated status markers."""
        # Pattern: "Phase X in progress" or "P1 🔄" etc.
        in_progress_patterns = [
            (r'Phase\s+(\w+).*in progress', 'phase'),
            (r'P(\d+).*🔄', 'phase'),
            (r'P(\d+).*进行中', 'phase'),
            (r'Status.*in progress', 'status'),
        ]

        for i, line in enumerate(content.split('\n'), 1):
            for pattern, kind in in_progress_patterns:
                if match := re.search(pattern, line, re.IGNORECASE):
                    self.issues.append(Issue(
                        severity='warning',
                        file=str(file.relative_to(self.root)),
                        line=i,
                        message=f"Found '{match.group(0)}' - verify if still accurate",
                        suggestion="Check git log and update status if phase is completed"
                    ))

    def check_file_length(self, file: Path, content: str):
        """Check if documentation exceeds recommended length."""
        lines = len(content.split('\n'))
        is_root = file.parent == self.root

        threshold = 150 if is_root else 100
        if lines > threshold:
            self.issues.append(Issue(
                severity='warning',
                file=str(file.relative_to(self.root)),
                line=None,
                message=f"{lines} lines (target: <{threshold} lines)",
                suggestion="Consider refactoring details to subdirectory docs or docs/"
            ))

    def check_sync(self, claude_file: Path):
        """Check if CLAUDE.md and AGENTS.md are in sync."""
        agents_file = claude_file.parent / 'AGENTS.md'
        if not agents_file.exists():
            self.issues.append(Issue(
                severity='error',
                file=str(claude_file.relative_to(self.root)),
                line=None,
                message="Missing paired AGENTS.md file",
                suggestion=f"Create {agents_file.name} with equivalent content"
            ))
            return

        # Check if both files were modified at similar times
        claude_mtime = claude_file.stat().st_mtime
        agents_mtime = agents_file.stat().st_mtime

        # If modification times differ by more than 1 hour, flag it
        if abs(claude_mtime - agents_mtime) > 3600:
            older = claude_file if claude_mtime < agents_mtime else agents_file
            self.issues.append(Issue(
                severity='warning',
                file=str(older.relative_to(self.root)),
                line=None,
                message="CLAUDE.md and AGENTS.md modification times differ significantly",
                suggestion="Verify both files contain equivalent content"
            ))

    def check_tech_stack_consistency(self, file: Path, content: str):
        """Check for tech stack mismatches."""
        # Common mismatches
        checks = [
            (r'\bpip install\b', 'pyproject.toml', 'uv',
             "Found 'pip install' but project uses uv (check pyproject.toml)"),
            (r'\bnpm install\b', 'package.json', 'yarn/pnpm',
             "Found 'npm install' - verify if project uses yarn or pnpm"),
        ]

        for pattern, indicator_file, alternative, message in checks:
            if re.search(pattern, content):
                # Check if indicator file suggests different tool
                indicator_path = file.parent / indicator_file
                if indicator_path.exists():
                    indicator_content = indicator_path.read_text()
                    # Simple heuristic: if pyproject.toml exists and mentions uv
                    if 'uv' in indicator_content or '[tool.uv]' in indicator_content:
                        self.issues.append(Issue(
                            severity='error',
                            file=str(file.relative_to(self.root)),
                            line=None,
                            message=message,
                            suggestion=f"Update commands to use {alternative}"
                        ))

    def check_missing_files(self, file: Path, content: str):
        """Check if documentation mentions files that don't exist or misses new files."""
        # Extract file paths mentioned in documentation
        # Pattern: paths like src/foo.py, components/Bar.tsx, etc.
        # Require at least one slash and reasonable file extension
        mentioned_files = set()
        for match in re.finditer(r'[\w/-]+/[\w/-]+\.\w{2,5}', content):
            path_str = match.group(0)

            # Skip URLs and network addresses
            if any(x in path_str for x in ['http', 'localhost', 'example.com', '127.0', '0.0.0', '192.168']):
                continue

            # Skip if it looks like a version number (e.g., "2.x", "3.11")
            if re.match(r'^\d+\.\d+', path_str):
                continue

            # Skip common abbreviations and false positives
            if path_str in ['e.g', 'i.e', 'etc.', 'vs.']:
                continue

            # Skip if it contains common non-file patterns
            if any(x in path_str.lower() for x in ['.case', '.com', '.org', '.net', 'dot.', 'kebab-', 'snake_']):
                continue

            # Skip technical terms that look like paths but aren't
            if any(x in path_str for x in ['H.264', 'H.265', 'MPEG-', 'UTF-']):
                continue

            mentioned_files.add(path_str)

        # Check if mentioned files exist
        for mentioned in mentioned_files:
            full_path = file.parent / mentioned
            if not full_path.exists():
                self.issues.append(Issue(
                    severity='info',
                    file=str(file.relative_to(self.root)),
                    line=None,
                    message=f"References non-existent file: {mentioned}",
                    suggestion="Verify if file was moved/renamed or remove reference"
                ))

    def check_git_recent_changes(self, file: Path):
        """Check if recent git changes are reflected in documentation."""
        try:
            # Get files added in last 10 commits in the same directory
            result = subprocess.run(
                ['git', 'log', '--name-status', '--pretty=format:', '-10',
                 '--', str(file.parent)],
                cwd=self.root,
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode != 0:
                return

            # Parse added files (lines starting with 'A')
            added_files = []
            for line in result.stdout.split('\n'):
                if line.startswith('A\t'):
                    added_file = line[2:].strip()
                    # Only consider files in the same directory
                    if added_file.startswith(str(file.parent.relative_to(self.root))):
                        added_files.append(Path(added_file).name)

            if not added_files:
                return

            # Check if these files are mentioned in documentation
            content = file.read_text()
            for added_file in added_files:
                if added_file not in content and not added_file.endswith('.md'):
                    self.issues.append(Issue(
                        severity='info',
                        file=str(file.relative_to(self.root)),
                        line=None,
                        message=f"Recent addition '{added_file}' not mentioned in docs",
                        suggestion="Consider adding to project structure or relevant section"
                    ))
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            pass

    def run_checks(self):
        """Run all staleness checks."""
        doc_files = self.find_doc_files()
        self.log(f"Found {len(doc_files)} documentation files")

        for doc_file in doc_files:
            self.log(f"Checking {doc_file.relative_to(self.root)}")

            try:
                content = doc_file.read_text()
            except Exception as e:
                self.issues.append(Issue(
                    severity='error',
                    file=str(doc_file.relative_to(self.root)),
                    line=None,
                    message=f"Failed to read file: {e}"
                ))
                continue

            # Run checks
            self.check_status_markers(doc_file, content)
            self.check_file_length(doc_file, content)
            self.check_tech_stack_consistency(doc_file, content)
            self.check_missing_files(doc_file, content)
            self.check_git_recent_changes(doc_file)

            # Check sync only for CLAUDE.md files
            if doc_file.name == 'CLAUDE.md':
                self.check_sync(doc_file)

    def print_report(self):
        """Print staleness report."""
        if not self.issues:
            print("✅ No staleness issues detected!")
            return 0

        # Group by severity
        errors = [i for i in self.issues if i.severity == 'error']
        warnings = [i for i in self.issues if i.severity == 'warning']
        infos = [i for i in self.issues if i.severity == 'info']

        print(f"\n📋 Staleness Report ({len(self.issues)} issues)\n")

        for severity, issues, icon in [
            ('ERROR', errors, '❌'),
            ('WARNING', warnings, '⚠️'),
            ('INFO', infos, 'ℹ️')
        ]:
            if not issues:
                continue

            print(f"{icon} {severity} ({len(issues)})")
            for issue in issues:
                location = f"{issue.file}:{issue.line}" if issue.line else issue.file
                print(f"  {location}")
                print(f"    {issue.message}")
                if issue.suggestion:
                    print(f"    💡 {issue.suggestion}")
                print()

        return 1 if errors else 0


def main():
    parser = argparse.ArgumentParser(
        description='Check CLAUDE.md and AGENTS.md files for staleness issues'
    )
    parser.add_argument(
        '--root',
        type=Path,
        default=Path.cwd(),
        help='Project root directory (default: current directory)'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose output'
    )
    parser.add_argument(
        '--fix',
        action='store_true',
        help='Attempt to auto-fix issues (not yet implemented)'
    )

    args = parser.parse_args()

    if not args.root.exists():
        print(f"Error: Directory {args.root} does not exist", file=sys.stderr)
        return 1

    if args.fix:
        print("Warning: --fix is not yet implemented", file=sys.stderr)

    checker = StalenessChecker(args.root, verbose=args.verbose)
    checker.run_checks()
    return checker.print_report()


if __name__ == '__main__':
    sys.exit(main())
