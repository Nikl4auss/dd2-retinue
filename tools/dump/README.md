# Dump tools

Query REFramework's `il2cpp_dump.json` (REFramework menu → DeveloperTools → Object Explorer → Dump SDK)
without loading 1+ GB into memory. Regenerate `out/` after every game update.

```sh
DUMP="$HOME/Documentos/Games/Dragon Dogma 2/il2cpp_dump.json"
mkdir -p tools/dump/out
python3 -I tools/dump/index_dump.py "$DUMP" tools/dump/out/index.json   # type -> byte range (~15 s)
python3 -I tools/dump/flat.py "$DUMP" tools/dump/out/flat.tsv           # type<TAB>F|M|P<TAB>member (~20 s)
```

- Find members by name: `grep -P '^app\.[^\t<]*\tM\t' tools/dump/out/flat.tsv | grep -i subpawn`
- Signatures of one type: `python3 -I tools/dump/sig.py "$DUMP" tools/dump/out/index.json app.PawnUtil [regex]`

Notes: the dump uses CRLF line endings. Method keys carry a numeric suffix (`isSubPawn244319`), which the tools strip.
Enum member names that end in digits (`Job01`) are stripped too, so read enums with `sig.py` instead of `flat.tsv`.
