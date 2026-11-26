#!/usr/bin/env python3
"""Regenerate the localization classes without gen-l10n's doc comments.

Usage: python tool/i18n/gen_l10n.py    (from android/app/ or any directory)

Flutter's gen-l10n template writes a three-line `///` block for every message
("No description provided for @key" / "In zh, this message translates to" /
the text itself). The generated files are kept in git, so those comments add
tens of thousands of lines of churn on every regeneration. Run this script
instead of `flutter gen-l10n`: it generates, drops the generated comments
(keeping `// ignore` directives) and formats the result.

`flutter gen-l10n` refuses to run unless the project's pubspec turns on
`flutter: generate: true`, but that same flag makes every `flutter pub get`
rerun gen-l10n and write those comments back. android/app/pubspec.yaml therefore
keeps the flag off, and this script runs gen-l10n against a throwaway project
under .dart_tool/l10n_gen whose l10n.yaml points back at lib/l10n.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARB_DIR = ROOT / 'lib/l10n'
TEMP_PROJECT = ROOT / '.dart_tool/l10n_gen'


def _run(*args, cwd=ROOT):
    executable = shutil.which(args[0])
    if executable is None:
        sys.exit(f'{args[0]} not found in PATH')
    subprocess.run(
        [executable, *args[1:]],
        cwd=cwd,
        check=True,
        shell=os.name == 'nt',
    )


def write_temp_project():
    """Create the `generate: true` project that gen-l10n insists on."""
    TEMP_PROJECT.mkdir(parents=True, exist_ok=True)
    (TEMP_PROJECT / 'pubspec.yaml').write_text(
        'name: l10n_gen\nflutter:\n  generate: true\n', encoding='utf-8'
    )
    config = (ROOT / 'tool/i18n/l10n.yaml').read_text(encoding='utf-8')
    relative_arb_dir = Path(os.path.relpath(ARB_DIR, TEMP_PROJECT)).as_posix()
    config = re.sub(
        r'^arb-dir:.*$', f'arb-dir: {relative_arb_dir}', config, flags=re.MULTILINE
    )
    (TEMP_PROJECT / 'l10n.yaml').write_text(config, encoding='utf-8')


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
    write_temp_project()
    try:
        _run('flutter', 'gen-l10n', cwd=TEMP_PROJECT)
    finally:
        shutil.rmtree(TEMP_PROJECT, ignore_errors=True)
    generated = sorted((ROOT / 'lib/l10n').glob('app_localizations*.dart'))
    if not generated:
        sys.exit('no generated localization files found')
    changed = [path.name for path in generated if strip_generated_comments(path)]
    _run('dart', 'format', *[str(path) for path in generated])
    print(f'{len(generated)} generated files, stripped comments from {len(changed)}')


if __name__ == '__main__':
    main()
