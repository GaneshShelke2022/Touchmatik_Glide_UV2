import json
from pathlib import Path

lang_dir = Path(__file__).resolve().parents[1] / 'assets' / 'lang'
base = json.loads((lang_dir / 'app_en.arb').read_text(encoding='utf-8'))
base_keys = list(base.keys())

targets = ['app_hi.arb', 'app_mr.arb', 'app_pa.arb', 'app_bn.arb']
for name in targets:
    f = lang_dir / name
    if not f.exists():
        print('Skipping missing', name)
        continue
    j = json.loads(f.read_text(encoding='utf-8'))
    out = {}
    for k in base_keys:
        out[k] = j.get(k, base[k])
    # write back with pretty formatting and ensure trailing newline
    text = json.dumps(out, ensure_ascii=False, indent=2, sort_keys=False)
    (lang_dir / name).write_text(text + '\n', encoding='utf-8')
    print('Merged missing keys into', name)
