# usage: sig.py DUMP INDEX TYPE [filter-regex]  -> compact methods/fields/parent
import sys, json, re
dump, index, t = sys.argv[1:4]
flt = re.compile(sys.argv[4], re.I) if len(sys.argv) > 4 else None
a, b = json.load(open(index))[t]
with open(dump, 'rb') as f:
    f.seek(a); raw = f.read(b - a).decode('utf-8', 'replace')
raw = raw[raw.index('{'):].rstrip().rstrip(',')
d = json.loads(raw)
print(t, '<', d.get('parent'))
for n, fd in sorted((d.get('fields') or {}).items()):
    s = f"  F {fd.get('type')} {n}" + (' static' if fd.get('flags','').find('Static')>=0 else '')
    if not flt or flt.search(s): print(s)
for n, m in sorted((d.get('methods') or {}).items()):
    ps = ','.join(f"{p.get('type')} {p.get('name')}" for p in (m.get('params') or []))
    s = f"  M {m.get('returns',{}).get('type')} {re.sub(r'\d+$','',n)}({ps})"
    if not flt or flt.search(s): print(s)
