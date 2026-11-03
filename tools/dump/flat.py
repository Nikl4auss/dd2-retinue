import sys, re
top = re.compile(rb'^    "(.*)": \{\r?\n$')
sec = re.compile(rb'^        "(methods|fields|properties)": \{\r?\n$')
mem = re.compile(rb'^            "(.*)": \{\r?\n$')
t = s = None
out = open(sys.argv[2], 'w')
for line in open(sys.argv[1], 'rb'):
    m = top.match(line)
    if m: t = m.group(1).decode('utf-8','replace'); s = None; continue
    m = sec.match(line)
    if m: s = m.group(1).decode()[0].upper(); continue
    if s:
        m = mem.match(line)
        if m:
            n = re.sub(r'\d+$', '', m.group(1).decode('utf-8','replace'))
            out.write(f"{t}\t{s}\t{n}\n")
