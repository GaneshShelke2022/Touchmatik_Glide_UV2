import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'assets' / 'lang'
files = {
    'en': root / 'app_en.arb',
    'pa': root / 'app_pa.arb',
    'bn': root / 'app_bn.arb',
}

en = json.load(open(files['en'], encoding='utf-8'))
pa = json.load(open(files['pa'], encoding='utf-8'))
bn = json.load(open(files['bn'], encoding='utf-8'))

same_pa = [k for k,v in en.items() if k in pa and pa[k]==v]
same_bn = [k for k,v in en.items() if k in bn and bn[k]==v]

print('Keys identical to en in app_pa.arb: {}'.format(len(same_pa)))
for k in same_pa[:50]:
    print(' PA:', k, '=>', en[k])

print('\nKeys identical to en in app_bn.arb: {}'.format(len(same_bn)))
for k in same_bn[:50]:
    print(' BN:', k, '=>', en[k])
