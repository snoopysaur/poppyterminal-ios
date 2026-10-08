#!/usr/bin/env bash
# Exporta os anexos (capturas) de um .xcresult para uma pasta, com o NOME legivel de cada um
# (o xcresulttool grava com UUID). Uso: scripts/export_shots.sh <Test.xcresult> <pasta> [prefixo]
set -uo pipefail
RES="${1:?xcresult}"; OUT="${2:?pasta}"; PREFIX="${3:-}"
mkdir -p "$OUT"
[ -d "$RES" ] || { echo "sem $RES"; exit 0; }
TMP="$(mktemp -d)"
xcrun xcresulttool export attachments --path "$RES" --output-path "$TMP" >/dev/null 2>&1 || true
python3 - "$TMP" "$OUT" "$PREFIX" <<'PY'
import json, os, shutil, sys
tmp, out, prefix = sys.argv[1:4]
manifest = os.path.join(tmp, "manifest.json")
used = set()
def put(src, name):
    base, ext = os.path.splitext(name)
    ext = ext or os.path.splitext(src)[1] or ".png"
    n, i = base, 1
    while (n + ext) in used:
        i += 1
        n = "%s-%d" % (base, i)
    used.add(n + ext)
    shutil.copy(src, os.path.join(out, prefix + n + ext))
if os.path.exists(manifest):
    for entry in json.load(open(manifest)):
        for a in entry.get("attachments", []):
            src = os.path.join(tmp, a.get("exportedFileName", ""))
            if os.path.isfile(src):
                nm = a.get("suggestedHumanReadableName") or a["exportedFileName"]
                for ch in '/\\"<>:|*? \r\n':
                    nm = nm.replace(ch, "_")
                put(src, nm)
else:
    for f in os.listdir(tmp):
        if f.lower().endswith((".png", ".jpg")):
            put(os.path.join(tmp, f), f)
print("exportadas:", len(used))
PY
rm -rf "$TMP"
