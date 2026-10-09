#!/usr/bin/env python3
"""Imprime as mensagens de falha de `xcresulttool get test-results tests` (diagnostico de CI)."""
import json
import sys


def walk(n, path):
    if isinstance(n, list):
        for c in n:
            walk(c, path)
        return
    if not isinstance(n, dict):
        return
    name = str(n.get("name", ""))
    if n.get("nodeType") == "Failure Message":
        print("FALHA em %s :: %s" % (path, name))
    for c in n.get("children", []) or []:
        walk(c, path + "/" + name)


walk(json.load(open(sys.argv[1])).get("testNodes", []), "")
