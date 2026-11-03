import sys, re, json
src, out = sys.argv[1], sys.argv[2]
pat = re.compile(rb'^    "(.*)": \{\r?\n$')
idx = {}
off = 0
prev = None
with open(src, 'rb') as f:
    for line in f:
        m = pat.match(line)
        if m:
            name = m.group(1).decode('utf-8', 'replace')
            if prev: idx[prev][1] = off
            idx[name] = [off, None]; prev = name
        off += len(line)
idx[prev][1] = off
json.dump(idx, open(out, 'w'))
print(len(idx), 'types')
