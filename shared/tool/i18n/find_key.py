#!/usr/bin/env python3
"""Look up existing ARB keys for Chinese (or English) literals.

Usage:
  python tool/i18n/find_key.py 取消 保存
  python tool/i18n/find_key.py --en Cancel
"""

import json
import sys
from pathlib import Path

ZH = Path('lib/l10n/app_zh.arb')
EN = Path('lib/l10n/app_en.arb')


def main(argv):
    en = '--en' in argv
    words = [a for a in argv if not a.startswith('--')]
    data = json.loads((EN if en else ZH).read_text(encoding='utf-8'))
    for word in words:
        hits = [
            (key, data[key])
            for key in data
            if not key.startswith('@') and data[key] == word
        ]
        print(f'{word!r}: {hits if hits else "—"}')


if __name__ == '__main__':
    main(sys.argv[1:])
