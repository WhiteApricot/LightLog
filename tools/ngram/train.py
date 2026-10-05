"""Shared frozen data and normalization contract; no model fitting here."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tools/ngram'

def normalize(text):
    # Explicit codepoint rules shared with NgramClassifier.normalize (no locale).
    chars = []
    for ch in text[:2048]:
        c = ord(ch)
        if 0xff01 <= c <= 0xff5e:
            c -= 0xfee0
        if 65 <= c <= 90:
            c += 32
        if 97 <= c <= 122 or 0x3400 <= c <= 0x9fff:
            chars.append(chr(c))
        else:
            chars.append(' ')
    return re.sub(' +', ' ', ''.join(chars)).strip()

def load(name):
    return [json.loads(line) for line in (HERE / 'data' / name).read_text(encoding='utf-8').splitlines()]
