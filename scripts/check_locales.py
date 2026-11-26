import json
from pathlib import Path

lang_dir = Path(__file__).resolve().parents[1] / 'assets' / 'lang'
files = list(lang_dir.glob('app_*.arb'))
if not files:
    print('No app_*.arb files found in assets/lang')
    raise SystemExit(1)

base = json.loads((lang_dir / 'app_en.arb').read_text(encoding='utf-8'))
base_keys = set(base.keys())

ok = True
for f in sorted(files):
    j = json.loads(f.read_text(encoding='utf-8'))
    keys = set(j.keys())
    missing = base_keys - keys
    extra = keys - base_keys
    print(f.name, ': keys=', len(keys), 'missing=', len(missing), 'extra=', len(extra))
    if missing:
        print('  missing list:')
        for k in sorted(list(missing)):
            print('   -', k)
        ok = False
    if extra:
        print('  extra list:')
        for k in sorted(list(extra)):
            print('   -', k)
        ok = False

if ok:
    print('All locale files contain the same keys as app_en.arb')
else:
    print('Some locale files have mismatched keys')
