#!/usr/bin/env bash
# Imprime o UDID de um simulador pelo NOME (ex.: "iPhone SE (3rd generation)", "iPhone 16 Pro"):
# usa o existente no runtime iOS mais novo ou cria um. Uso: scripts/sim_udid.sh "<nome>"
set -euo pipefail
NAME="${1:?uso: sim_udid.sh <nome do aparelho>}"
python3 - "$NAME" <<'PY'
import json, subprocess, sys

name = sys.argv[1]

def sh(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout

devs = json.loads(sh("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
best = None
for runtime, items in devs.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in runtime.split("iOS-")[-1].split("-") if x.isdigit())
    for d in items:
        if d["name"] == name and (best is None or ver > best[0]):
            best = (ver, d["udid"])
if best:
    print(best[1])
    sys.exit(0)

# Nao existe: cria com o runtime iOS mais novo.
rts = [r for r in json.loads(sh("xcrun", "simctl", "list", "runtimes", "available", "-j"))["runtimes"]
       if r.get("platform") == "iOS" or r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS")]
if not rts:
    sys.exit("nenhum runtime iOS disponivel")
rt = max(rts, key=lambda r: tuple(int(x) for x in r["version"].split(".")))
types = json.loads(sh("xcrun", "simctl", "list", "devicetypes", "-j"))["devicetypes"]
dt = next((t for t in types if t["name"] == name), None)
if not dt:
    sys.exit("tipo de aparelho desconhecido: " + name)
print(sh("xcrun", "simctl", "create", name, dt["identifier"], rt["identifier"]).strip())
PY
