#!/usr/bin/env bash
# Imprime o UDID de um simulador iPhone disponivel (runtime iOS mais novo; sem SE/mini/Air).
set -euo pipefail
xcrun simctl list devices available -j | python3 "$(dirname "$0")/pick_sim.py"
