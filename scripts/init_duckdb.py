#!/usr/bin/env python3
"""
init_duckdb.py — Inicializa o banco DuckDB local com views apontando para os Parquets raw.

Execute uma vez (ou após apagar o .duckdb) antes do primeiro `dbt build --target local`:
    py -3.14 scripts/init_duckdb.py

Só é necessário quando o arquivo local.duckdb não existe ainda ou foi removido.
O dbt mantém as views nas execuções subsequentes.
"""
import os
import sys

try:
    import duckdb
except ImportError:
    print("Erro: pacote 'duckdb' não encontrado. Execute: pip install dbt-duckdb")
    sys.exit(1)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(PROJECT_ROOT, "data", "local.duckdb")
DATA_PATH = os.path.join(PROJECT_ROOT, "data", "processed")

# Glob patterns com separador Unix (DuckDB exige)
payments_glob = DATA_PATH.replace("\\", "/") + "/*/payments.parquet"
receivables_glob = DATA_PATH.replace("\\", "/") + "/*/receivables.parquet"

print(f"Banco DuckDB: {DB_PATH}")
print(f"Parquets payments: {payments_glob}")
print(f"Parquets receivables: {receivables_glob}")

conn = duckdb.connect(DB_PATH)

conn.execute("CREATE SCHEMA IF NOT EXISTS raw")

conn.execute(f"""
    CREATE OR REPLACE VIEW raw.raw_payments AS
    SELECT * FROM read_parquet('{payments_glob}', union_by_name=true)
""")
print("View raw.raw_payments criada")

conn.execute(f"""
    CREATE OR REPLACE VIEW raw.raw_receivables AS
    SELECT * FROM read_parquet('{receivables_glob}', union_by_name=true)
""")
print("View raw.raw_receivables criada")

c1 = conn.execute("SELECT COUNT(*) FROM raw.raw_payments").fetchone()[0]
c2 = conn.execute("SELECT COUNT(*) FROM raw.raw_receivables").fetchone()[0]
print(f"\nValidacao: raw_payments={c1} linhas | raw_receivables={c2} linhas")

conn.close()
print("\nDuckDB inicializado com sucesso. Agora rode: dbt build --target local")
