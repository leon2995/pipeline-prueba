#!/usr/bin/env python3
"""JEV: router determinista del pipeline. Lee veredictos y decide PASS, FIX o HUMAN. Sin LLM.

Uso:
  python scripts/jev.py --verdict .pipeline/veredicto-T1.json --attempt 1 --risk medio \
      [--codex .pipeline/veredicto-codex-T1.json] [--previous .pipeline/veredicto-T1-prev.json]

Salida: primera línea PASS | FIX | HUMAN. Las siguientes líneas son la razón o los hallazgos a corregir.

Reglas de acuerdo:
  - bajo: basta el auditor Claude.
  - medio y alto: Claude y Codex deben coincidir; si no, HUMAN.
Para agregar un tercer auditor en el futuro: nuevo flag, misma validación, y regla de mayoría
con escalada a HUMAN cuando el que discrepa reporte severidad alta.
"""
import argparse
import json
import pathlib
import sys

MAX_ATTEMPTS = {"bajo": 3, "medio": 2, "alto": 2}
VALID = ("pass", "fail")


def load(path):
    try:
        return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except Exception as exc:  # archivo ausente o JSON roto
        return {"_error": str(exc)}


def human(reason):
    print("HUMAN")
    print(f"razon={reason}")
    sys.exit(0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verdict", required=True, help="veredicto del auditor Claude")
    ap.add_argument("--codex", help="veredicto del segundo auditor (Codex)")
    ap.add_argument("--attempt", type=int, required=True, help="intento actual, empezando en 1")
    ap.add_argument("--risk", choices=list(MAX_ATTEMPTS), required=True)
    ap.add_argument("--previous", help="veredicto del intento anterior, para detectar vueltas")
    args = ap.parse_args()

    verdict = load(args.verdict)
    if "_error" in verdict or verdict.get("verdict") not in VALID:
        human("veredicto del auditor ilegible o invalido")

    if args.risk in ("medio", "alto"):
        if not args.codex:
            human(f"riesgo {args.risk} requiere segundo auditor (--codex)")
        codex = load(args.codex)
        if codex.get("verdict") not in VALID:
            human("veredicto de codex ilegible o invalido")
        if codex["verdict"] != verdict["verdict"]:
            human("auditores en desacuerdo")
        if verdict["verdict"] == "fail":
            # hallazgos a corregir: union de ambos auditores
            verdict = dict(verdict, findings=verdict.get("findings", []) + codex.get("findings", []))

    if verdict["verdict"] == "pass":
        print("PASS")
        return

    if args.attempt >= MAX_ATTEMPTS[args.risk]:
        human(f"tope de reintentos alcanzado ({MAX_ATTEMPTS[args.risk]}) para riesgo {args.risk}")

    if args.previous:
        prev = load(args.previous)
        prev_high = {f.get("file") for f in prev.get("findings", []) if f.get("severity") == "alta"}
        cur_high = {f.get("file") for f in verdict.get("findings", []) if f.get("severity") == "alta"}
        if prev_high & cur_high:
            human("hallazgo de severidad alta repetido en el mismo archivo: el engineer esta dando vueltas")

    print("FIX")
    for f in verdict.get("findings", []):
        if f.get("severity") in ("alta", "media"):
            print(f"- [{f['severity']}] {f.get('file', '')}: {f.get('detail', '')} -> {f.get('fix', '')}")


if __name__ == "__main__":
    main()
