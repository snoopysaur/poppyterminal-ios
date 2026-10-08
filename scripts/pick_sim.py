import json
import sys

data = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    ver = tuple(int(x) for x in runtime.split("iOS-")[-1].split("-") if x.isdigit())
    for d in devs:
        n = d["name"]
        if n.startswith("iPhone") and "SE" not in n and "mini" not in n and "Air" not in n:
            key = (ver, "Pro" not in n, n)
            if best is None or key > best[0]:
                best = (key, d["udid"], n, runtime)
if not best:
    sys.exit("nenhum simulador iPhone encontrado")
print(best[1])
print("simulador: %s (%s)" % (best[2], best[3]), file=sys.stderr)
