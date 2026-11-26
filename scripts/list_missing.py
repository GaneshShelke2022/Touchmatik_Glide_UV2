import json
from pathlib import Path

lang_dir = Path(__file__).resolve().parents[1] / 'assets' / 'lang'
base = json.loads((lang_dir / 'app_en.arb').read_text(encoding='utf-8'))
base_keys = set(base.keys())

targets = ['app_hi.arb', 'app_mr.arb', 'app_pa.arb', 'app_bn.arb']
for name in targets:
    f = lang_dir / name
    if not f.exists():
        print(name, 'MISSING FILE')
        continue
    j = json.loads(f.read_text(encoding='utf-8'))
    keys = set(j.keys())
    missing = sorted(list(base_keys - keys))
    print(name, 'missing_count=', len(missing))
    if missing:
        print('\n'.join(missing))
    print('---')
