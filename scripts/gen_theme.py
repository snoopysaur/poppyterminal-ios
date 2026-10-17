"""Gera App/Design/ThemeTokens.swift a partir de design/tokens.json.

Uso:
  python -I scripts/gen_theme.py          # escreve o arquivo
  python -I scripts/gen_theme.py --check  # sai 0 se o arquivo gerado esta em dia, 1 se nao
Sem dependencias. Cores derivadas (tintas, bloco de risco, selecao do terminal, cores
brilhantes do terminal) sao calculadas aqui e entram como constantes no Swift.
"""
import json
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
ENTRADA = RAIZ / "design" / "tokens.json"
SAIDA = RAIZ / "App" / "Design" / "ThemeTokens.swift"

CHAVES = ["base", "mantle", "crust", "surface", "surfaceStrong", "text", "textSecondary",
          "accent", "onAccent", "border", "borderStrong", "peach", "red", "blue", "green",
          "lavender", "idle", "gameMode"]


def mix(a, b, t):
    """t de b sobre a (0..1); devolve hex maiusculo sem #."""
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ca, cb))


def derivados(c, ansi):
    d = {
        "tintAlert": mix(c["surface"], c["peach"], 0.14),
        "tintDanger": mix(c["surface"], c["red"], 0.14),
        "riskBlock": mix(c["surface"], c["red"], 0.16),
        "riskButton": mix(c["surface"], c["red"], 0.22),
        "seal": c["crust"],
        "onBadge": c["crust"],
        "terminalSelection": mix(c["crust"], c["accent"], 0.30),
    }
    # 16 cores do terminal: 0-7 normais; 8 = ocioso; 9-15 = normal + 25% do texto.
    brilhantes = [c["idle"]] + [mix(a, c["text"], 0.25) for a in ansi[1:]]
    return d, ansi + brilhantes


def bloco(nome, tema):
    c = tema["cores"]
    faltam = [k for k in CHAVES if k not in c]
    if faltam or len(tema["ansi"]) != 8:
        sys.exit(f"tema {nome}: faltam chaves {faltam} ou ansi != 8")
    d, term = derivados(c, tema["ansi"])
    linhas = [f"    static let {k}: UInt32 = 0x{c[k]}" for k in CHAVES]
    linhas += [f"    static let {k}: UInt32 = 0x{v}" for k, v in d.items()]
    lista = ", ".join(f"0x{x}" for x in term)
    linhas.append(f"    static let terminalAnsi: [UInt32] = [{lista}]")
    return "\n".join(linhas)


def gerar():
    dados = json.loads(ENTRADA.read_text(encoding="utf-8"))
    ativo = dados["ativo"]
    nomes = {"guild": "ThemeTokensGuild", "mocha": "ThemeTokensMocha"}
    partes = ["// GERADO por scripts/gen_theme.py a partir de design/tokens.json. NAO EDITE A MAO.",
              "// Para mudar uma cor: edite design/tokens.json e rode `python -I scripts/gen_theme.py`.", ""]
    for chave, enum in nomes.items():
        partes.append(f"/// {dados['temas'][chave]['nome']}")
        partes.append(f"enum {enum} {{")
        partes.append(bloco(chave, dados["temas"][chave]))
        partes.append("}")
        partes.append("")
    partes.append("/// Tema ativo do app.")
    partes.append(f"typealias ThemeTokens = {nomes[ativo]}")
    partes.append("")
    return "\n".join(partes)


def main():
    novo = gerar()
    if "--check" in sys.argv:
        atual = SAIDA.read_bytes().decode("utf-8").replace("\r\n", "\n") if SAIDA.exists() else ""
        if atual != novo:
            print("ThemeTokens.swift esta fora de data: rode python -I scripts/gen_theme.py")
            return 1
        print("ThemeTokens.swift em dia")
        return 0
    SAIDA.write_bytes(novo.encode("utf-8"))
    print(f"gerado {SAIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
