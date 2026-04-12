"""
verify_anonymization.py
========================
Verifica que nenhum arquivo Parquet em /data/processed/ contém
dados sensíveis não anonimizados.

Execute antes de qualquer commit:
    python scripts/verify_anonymization.py

Falha com exit code 1 se detectar:
- Valores no formato de CPF (NNN.NNN.NNN-NN) na coluna titular_code
- Valores no formato de CNPJ (NN.NNN.NNN/NNNN-NN) na coluna titular_code

Se este script falhar, NÃO faça commit. Verifique o script de anonimização
e re-execute scripts/anonymize_and_load.py para o mês afetado.
"""

import re
import sys
from pathlib import Path

import pandas as pd

DATA_PROCESSED_DIR = Path("data/processed")

CPF_PATTERN  = re.compile(r"^\d{3}\.\d{3}\.\d{3}-\d{2}$")
CNPJ_PATTERN = re.compile(r"^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$")

CHECKS = [
    ("titular_code", CPF_PATTERN,  "CPF não anonimizado"),
    ("titular_code", CNPJ_PATTERN, "CNPJ não anonimizado"),
]


def verify_parquet(parquet_path: Path) -> list[str]:
    """Verifica um arquivo Parquet e retorna lista de violações encontradas."""
    violations = []
    try:
        df = pd.read_parquet(parquet_path)
    except Exception as exc:
        violations.append(f"  Erro ao ler {parquet_path}: {exc}")
        return violations

    for column, pattern, description in CHECKS:
        if column not in df.columns:
            continue
        matches = df[column].astype(str).apply(lambda v: bool(pattern.match(v)))
        count = matches.sum()
        if count > 0:
            violations.append(
                f"  {description} em {parquet_path} "
                f"(coluna '{column}', {count} ocorrência(s))"
            )

    return violations


def main() -> None:
    if not DATA_PROCESSED_DIR.exists():
        print(f"[INFO] Diretório {DATA_PROCESSED_DIR} não encontrado — nenhum arquivo para verificar.")
        sys.exit(0)

    parquet_files = sorted(DATA_PROCESSED_DIR.rglob("*.parquet"))
    if not parquet_files:
        print(f"[INFO] Nenhum arquivo Parquet encontrado em {DATA_PROCESSED_DIR}.")
        sys.exit(0)

    print(f"[INFO] Verificando {len(parquet_files)} arquivo(s) Parquet em {DATA_PROCESSED_DIR}...\n")

    all_violations = []
    for parquet_path in parquet_files:
        violations = verify_parquet(parquet_path)
        if violations:
            all_violations.extend(violations)
            print(f"[FAIL] {parquet_path}")
            for v in violations:
                print(v)
        else:
            print(f"[OK]   {parquet_path}")

    print()
    if all_violations:
        print(
            f"[ERRO] {len(all_violations)} violação(ões) encontrada(s). "
            "NÃO faça commit — execute o script de anonimização novamente."
        )
        sys.exit(1)
    else:
        print("[OK] Nenhuma violação encontrada. Os dados estão anonimizados.")
        sys.exit(0)


if __name__ == "__main__":
    main()
