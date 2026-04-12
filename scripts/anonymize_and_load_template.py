"""
anonymize_and_load_template.py
================================
Template do script de ingestão e anonimização.

Este arquivo é versionado no repositório. O script completo (com salt e
mapeamentos reais) NÃO é versionado — mantenha-o localmente como
`scripts/anonymize_and_load.py` (já no .gitignore).

Instruções para uso:
1. Copie este arquivo para `scripts/anonymize_and_load.py`
2. Preencha os valores marcados com TODO
3. Execute: python scripts/anonymize_and_load.py

Dependências: pip install -r requirements.txt
Autenticação GCP: gcloud auth application-default login
"""

import hashlib
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import colorlog
import pandas as pd
from faker import Faker
from google.cloud import bigquery

# ---------------------------------------------------------------------------
# Configuração de logging
# ---------------------------------------------------------------------------

handler = colorlog.StreamHandler()
handler.setFormatter(colorlog.ColoredFormatter(
    "%(log_color)s[%(levelname)s]%(reset)s %(asctime)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    log_colors={
        "DEBUG":    "cyan",
        "INFO":     "green",
        "WARNING":  "yellow",
        "ERROR":    "red",
        "CRITICAL": "bold_red",
    }
))
logger = logging.getLogger(__name__)
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# ---------------------------------------------------------------------------
# Constantes — preencha antes de executar
# ---------------------------------------------------------------------------

# TODO: defina um salt longo e aleatório (ex: secrets.token_hex(32))
# NUNCA versione este valor no repositório
HASH_SALT = "TODO_PREENCHA_COM_SALT_SECRETO"

# TODO: seed fixo para o Faker — garante reprodutibilidade entre execuções
FAKER_SEED = 42  # TODO: altere para um valor de sua escolha

# Projeto GCP — lido de variável de ambiente (nunca hardcode)
GCP_PROJECT_ID = os.environ["GCP_PROJECT_ID"]

# Dataset de destino no BigQuery
RAW_DATASET = "raw"

# Diretórios locais
DATA_ORIGINAL_DIR = Path("data/original")
DATA_PROCESSED_DIR = Path("data/processed")
LOGS_DIR = Path("logs")

# ---------------------------------------------------------------------------
# Mapeamento determinístico para dados comerciais sensíveis
# (estate_code, estate_name, estate_address)
# ---------------------------------------------------------------------------
# TODO: preencha com o mapeamento real antes da primeira execução.
# O dicionário é construído progressivamente — preserve-o entre execuções
# para garantir consistência entre os 12 meses.
#
# Formato:
# ESTATE_MAPPING = {
#     (estate_code_real, estate_name_real, estate_address_real): {
#         "estate_code": 1,
#         "estate_name": "Residencial Aurora",
#         "estate_address": "Rua das Flores, 100 - São Paulo/SP",
#     },
# }
ESTATE_MAPPING: dict = {}  # TODO: preencha com o mapeamento real

# Contador para geração de novos códigos fictícios (começa após o maior existente)
_next_estate_code = max((v["estate_code"] for v in ESTATE_MAPPING.values()), default=0) + 1

# ---------------------------------------------------------------------------
# Funções de anonimização
# ---------------------------------------------------------------------------

_faker = Faker("pt_BR")
Faker.seed(FAKER_SEED)

# Cache para nomes fictícios de titulares (garante consistência entre meses)
_titular_name_cache: dict[str, str] = {}


def _hash(value: str, length: int) -> str:
    """SHA-256 com salt, truncado em `length` caracteres."""
    raw = f"{HASH_SALT}{value}"
    return hashlib.sha256(raw.encode()).hexdigest()[:length]


def detect_titular_type(code: str) -> str:
    """Detecta 'PF' (CPF) ou 'PJ' (CNPJ) pelo formato do código original."""
    import re
    code = str(code).strip()
    if re.match(r"^\d{3}\.\d{3}\.\d{3}-\d{2}$", code):
        return "PF"
    if re.match(r"^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$", code):
        return "PJ"
    # Fallback: tenta detectar por comprimento após remover não-dígitos
    digits = re.sub(r"\D", "", code)
    return "PF" if len(digits) == 11 else "PJ"


def anonymize_titular_name(original_name: str) -> str:
    """Substitui por nome fictício via Faker com seed fixo. Cacheado por nome original."""
    if original_name not in _titular_name_cache:
        _titular_name_cache[original_name] = _faker.name()
    return _titular_name_cache[original_name]


def anonymize_titular_code(original_code: str) -> str:
    """Hash SHA-256 + salt, truncado em 12 chars."""
    return _hash(str(original_code).strip(), 12)


def anonymize_contract_code(original_code: str) -> str:
    """Hash SHA-256 + salt, truncado em 8 chars."""
    return _hash(str(original_code).strip(), 8)


def anonymize_estate_fields(
    estate_code: int, estate_name: str, estate_address: str
) -> dict:
    """
    Mapeamento determinístico para dados do empreendimento.
    Gera um novo mapeamento fictício se o empreendimento ainda não foi mapeado.
    """
    global _next_estate_code
    key = (estate_code, estate_name, estate_address)
    if key not in ESTATE_MAPPING:
        logger.warning(
            "Novo empreendimento detectado — criando mapeamento fictício. "
            "Atualize ESTATE_MAPPING com este valor para preservar consistência: "
            f"key={key}"
        )
        ESTATE_MAPPING[key] = {
            "estate_code": _next_estate_code,
            "estate_name": _faker.company() + " Residencial",
            "estate_address": _faker.address().replace("\n", ", "),
        }
        _next_estate_code += 1
    return ESTATE_MAPPING[key]


def anonymize_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Aplica todas as transformações de anonimização ao DataFrame."""
    df = df.copy()

    # titular_type: derivado ANTES do hash
    df["titular_type"] = df["titular_code"].apply(
        lambda c: detect_titular_type(str(c))
    )

    # titular_name: substituição por nome fictício
    df["titular_name"] = df["titular_name"].apply(anonymize_titular_name)

    # titular_code: hash
    df["titular_code"] = df["titular_code"].apply(anonymize_titular_code)

    # contract_code: hash
    df["contract_code"] = df["contract_code"].apply(anonymize_contract_code)

    # estate_code, estate_name, estate_address: mapeamento determinístico
    estate_anonymized = df.apply(
        lambda row: anonymize_estate_fields(
            row["estate_code"], row["estate_name"], row["estate_address"]
        ),
        axis=1,
    )
    df["estate_code"]    = estate_anonymized.apply(lambda x: x["estate_code"])
    df["estate_name"]    = estate_anonymized.apply(lambda x: x["estate_name"])
    df["estate_address"] = estate_anonymized.apply(lambda x: x["estate_address"])

    return df


# ---------------------------------------------------------------------------
# Carregamento no BigQuery
# ---------------------------------------------------------------------------

def load_to_bigquery(
    client: bigquery.Client,
    df: pd.DataFrame,
    table_id: str,
) -> int:
    """Carrega DataFrame no BigQuery via WRITE_APPEND. Retorna número de linhas."""
    job_config = bigquery.LoadJobConfig(
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        autodetect=False,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
    )
    job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
    job.result()
    return len(df)


def check_reprocessing(
    client: bigquery.Client, month_reference: str
) -> bool:
    """Verifica se o mês já foi carregado anteriormente em pipeline_runs."""
    table_id = f"{GCP_PROJECT_ID}.{RAW_DATASET}.pipeline_runs"
    query = f"""
        SELECT COUNT(*) AS cnt
        FROM `{table_id}`
        WHERE month_reference = DATE('{month_reference}-01')
          AND month_status = 'success'
    """
    try:
        result = client.query(query).result()
        for row in result:
            return row.cnt > 0
    except Exception:
        return False
    return False


def insert_pipeline_run(
    client: bigquery.Client,
    run_id: str,
    started_at: datetime,
    finished_at: datetime,
    run_status: str,
    month_reference: str,
    month_status: str,
    rows_loaded_payments: int,
    rows_loaded_receivables: int,
    date_upload: datetime,
    error_message: str | None = None,
) -> None:
    """Insere um registro de execução em raw.pipeline_runs."""
    table_id = f"{GCP_PROJECT_ID}.{RAW_DATASET}.pipeline_runs"
    rows = [{
        "run_id":                  run_id,
        "started_at":              started_at.isoformat(),
        "finished_at":             finished_at.isoformat(),
        "duration_seconds":        int((finished_at - started_at).total_seconds()),
        "run_status":              run_status,
        "month_reference":         f"{month_reference}-01",
        "month_status":            month_status,
        "rows_loaded_payments":    rows_loaded_payments,
        "rows_loaded_receivables": rows_loaded_receivables,
        "date_upload":             date_upload.isoformat(),
        "error_message":           error_message,
    }]
    errors = client.insert_rows_json(table_id, rows)
    if errors:
        logger.warning(f"Falha ao inserir em pipeline_runs: {errors}")


# ---------------------------------------------------------------------------
# Pipeline principal
# ---------------------------------------------------------------------------

def process_month(
    client: bigquery.Client,
    month_dir: Path,
    run_id: str,
    date_upload: datetime,
) -> dict:
    """
    Processa um mês: lê XLSX, anonimiza, salva Parquet, carrega no BigQuery.
    Retorna dicionário com status, linhas carregadas e possível mensagem de erro.
    """
    month = month_dir.name  # formato YYYY-MM
    xlsx_files = list(month_dir.glob("*.xlsx"))

    if len(xlsx_files) == 0:
        raise FileNotFoundError(f"Nenhum arquivo .xlsx encontrado em {month_dir}")
    if len(xlsx_files) > 1:
        raise ValueError(
            f"Mais de um arquivo .xlsx encontrado em {month_dir}: "
            + ", ".join(f.name for f in xlsx_files)
        )

    xlsx_path = xlsx_files[0]
    date_reference = f"{month}-01"

    # Lê as duas abas
    df_payments    = pd.read_excel(xlsx_path, sheet_name="payments")
    df_receivables = pd.read_excel(xlsx_path, sheet_name="receivables")

    # Adiciona value_payment e date_payment como NULL em receivables
    df_receivables["value_payment"] = None
    df_receivables["date_payment"]  = None

    # Anonimiza
    df_payments    = anonymize_dataframe(df_payments)
    df_receivables = anonymize_dataframe(df_receivables)

    # Adiciona colunas de rastreabilidade
    for df in [df_payments, df_receivables]:
        df["run_id"]         = run_id
        df["date_reference"] = pd.to_datetime(date_reference).date()
        df["date_upload"]    = date_upload

    # Salva Parquet local
    processed_dir = DATA_PROCESSED_DIR / month
    processed_dir.mkdir(parents=True, exist_ok=True)
    df_payments.to_parquet(processed_dir / "payments.parquet",    index=False)
    df_receivables.to_parquet(processed_dir / "receivables.parquet", index=False)

    # Carrega no BigQuery
    rows_payments = load_to_bigquery(
        client, df_payments,
        f"{GCP_PROJECT_ID}.{RAW_DATASET}.raw_payments"
    )
    logger.info(f"[{month}] payments: {rows_payments} linhas carregadas")

    rows_receivables = load_to_bigquery(
        client, df_receivables,
        f"{GCP_PROJECT_ID}.{RAW_DATASET}.raw_receivables"
    )
    logger.info(f"[{month}] receivables: {rows_receivables} linhas carregadas")

    return {
        "month":                   month,
        "status":                  "success",
        "rows_loaded_payments":    rows_payments,
        "rows_loaded_receivables": rows_receivables,
        "date_upload":             date_upload.isoformat(),
    }


def main() -> None:
    run_id      = str(uuid.uuid4())
    started_at  = datetime.now(timezone.utc)
    date_upload = started_at

    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    log_file = LOGS_DIR / f"{started_at.strftime('%Y-%m-%d_%H-%M-%S')}_run.json"

    # Descobre meses disponíveis
    month_dirs = sorted(
        [d for d in DATA_ORIGINAL_DIR.iterdir() if d.is_dir()],
        key=lambda d: d.name,
    )
    if not month_dirs:
        logger.critical(f"Nenhuma subpasta encontrada em {DATA_ORIGINAL_DIR}")
        return

    logger.info(
        f"Iniciando pipeline: {len(month_dirs)} meses encontrados em {DATA_ORIGINAL_DIR}"
    )

    client = bigquery.Client(project=GCP_PROJECT_ID)
    months_processed = []
    errors = []
    overall_status = "success"

    for month_dir in month_dirs:
        month = month_dir.name
        try:
            if check_reprocessing(client, month):
                logger.warning(
                    f"[{month}] Reprocessamento detectado — mês já carregado anteriormente"
                )

            result = process_month(client, month_dir, run_id, date_upload)
            months_processed.append(result)

            finished_at = datetime.now(timezone.utc)
            insert_pipeline_run(
                client=client,
                run_id=run_id,
                started_at=started_at,
                finished_at=finished_at,
                run_status="success",
                month_reference=month,
                month_status="success",
                rows_loaded_payments=result["rows_loaded_payments"],
                rows_loaded_receivables=result["rows_loaded_receivables"],
                date_upload=date_upload,
            )

        except Exception as exc:
            error_msg = str(exc)
            logger.error(f"[{month}] Falha: {error_msg}")
            errors.append({"month": month, "error": error_msg})
            months_processed.append({
                "month":  month,
                "status": "error",
                "error":  error_msg,
            })
            overall_status = "partial" if months_processed else "error"

            finished_at = datetime.now(timezone.utc)
            insert_pipeline_run(
                client=client,
                run_id=run_id,
                started_at=started_at,
                finished_at=finished_at,
                run_status=overall_status,
                month_reference=month,
                month_status="error",
                rows_loaded_payments=0,
                rows_loaded_receivables=0,
                date_upload=date_upload,
                error_message=error_msg,
            )

    finished_at = datetime.now(timezone.utc)
    duration    = int((finished_at - started_at).total_seconds())
    successes   = sum(1 for m in months_processed if m.get("status") == "success")

    logger.info(
        f"Pipeline concluído: {successes}/{len(month_dirs)} meses com sucesso "
        f"— duração: {duration}s"
    )

    # Salva log local
    log_data = {
        "run_id":           run_id,
        "started_at":       started_at.isoformat(),
        "finished_at":      finished_at.isoformat(),
        "duration_seconds": duration,
        "status":           overall_status,
        "months_processed": months_processed,
        "errors":           errors,
    }
    log_file.write_text(json.dumps(log_data, indent=2, default=str), encoding="utf-8")
    logger.info(f"Log salvo em {log_file}")


if __name__ == "__main__":
    main()
