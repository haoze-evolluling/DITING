#!/usr/bin/env python3
"""Regenerate the localization classes without gen-l10n's doc comments.

Usage: python tool/i18n/gen_l10n.py    (from shared/ or any directory)

Flutter's gen-l10n template writes a three-line `///` block for every message
("No description provided for @key" / "In zh, this message translates to" /
the text itself). The generated files are kept in git, so those comments add
tens of thousands of lines of churn on every regeneration. Run this script
instead of `flutter gen-l10n`: it generates, drops the generated comments
(keeping `// ignore` directives) and formats the result.
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _run(*args):
    executable = shutil.which(args[0])
    if executable is None:
        sys.exit(f'{args[0]} not found in PATH')
    subprocess.run(
        [executable, *args[1:]],
        cwd=ROOT,
        check=True,
        shell=os.name == 'nt',
    )


def strip_generated_comments(path):
    """Drop every comment except `// ignore` directives. True if it changed."""
    original = path.read_text(encoding='utf-8')
    kept = []
    for line in original.splitlines(keepends=True):
        text = line.lstrip()
        if text.startswith('///'):
            continue
        if text.startswith('//') and not text.startswith('// ignore'):
            continue
        kept.append(line)
    stripped = ''.join(kept)
    if stripped == original:
        return False
    path.write_text(stripped, encoding='utf-8')
    return True


def main():
    _run('flutter', 'gen-l10n')
    generated = sorted((ROOT / 'lib/l10n').glob('app_localizations*.dart'))
    if not generated:
        sys.exit('no generated localization files found')
    changed = [path.name for path in generated if strip_generated_comments(path)]
    _run('dart', 'format', *[str(path) for path in generated])
    print(f'{len(generated)} generated files, stripped comments from {len(changed)}')


if __name__ == '__main__':
    main()
