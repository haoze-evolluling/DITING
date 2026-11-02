#!/usr/bin/env python3
"""Merge one batch of translations into the ARB resources.

Usage: python tool/i18n/merge_arb.py path/to/batch.json

The batch file maps a key to either `["中文", "English"]` or
`{"zh": "...", "en": "...", "placeholders": {"count": {"type": "int"}}}`.
Placeholder metadata is written to the template (Chinese) file only, which is
what gen-l10n reads. Keys must be new: the script refuses to silently replace an
existing translation.
"""

import json
import sys
from pathlib import Path

ARB = {'zh': Path('lib/l10n/app_zh.arb'), 'en': Path('lib/l10n/app_en.arb')}


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def dump(path, data):
    # `@@locale` stays first; the rest keeps insertion order so the file reads like a glossary.
    ordered = {}
    if '@@locale' in data:
        ordered['@@locale'] = data.pop('@@locale')
    ordered.update(data)
    path.write_text(
        json.dumps(ordered, indent=2, ensure_ascii=False) + '\n', encoding='utf-8'
    )


def main(batch_path):
    batch = load(Path(batch_path))
    files = {code: load(path) for code, path in ARB.items()}
    for key, value in batch.items():
        if isinstance(value, list):
            zh, en, meta = value[0], value[1], None
        else:
            zh, en, meta = value['zh'], value['en'], value.get('placeholders')
        if key in files['zh']:
            # Reused key: the batch is shared with apply.py, which needs the literal too.
            if files['zh'][key] != zh or files['en'][key] != en:
                sys.exit(f'{key} already exists with different text')
            continue
        files['zh'][key] = zh
        files['en'][key] = en
        if meta:
            files['zh'][f'@{key}'] = {'placeholders': meta}
    for code, path in ARB.items():
        dump(path, files[code])
    print(f'merged {len(batch)} keys')


if __name__ == '__main__':
    main(sys.argv[1])
