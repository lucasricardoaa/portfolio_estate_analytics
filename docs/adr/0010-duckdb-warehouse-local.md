# ADR-0010: Adoção de DuckDB como Warehouse de Desenvolvimento Local

**Status:** Aceito
**Data:** 2026-06-18
**Autor:** Lucas (revisado e implementado por Claude Code)

---

## Contexto

O acesso ao Google Cloud Platform (BigQuery) foi descontinuado por questão de custo. O desenvolvimento do pipeline dbt ficou bloqueado sem um ambiente de execução disponível. Os dados raw continuam existindo localmente em Parquet (`data/processed/{ano-mes}/`), mas não havia como materializar as marts para habilitar a próxima fase (visualização Power BI).

---

## Alternativas Consideradas

1. **Reativar BigQuery temporariamente** — custo não justificado para desenvolvimento/portfólio; acesso OAuth expirado.

2. **Script Python ad-hoc para rematerializar marts** — contorna o dbt e duplica lógica de transformação; perda de rastreabilidade e testes.

3. **DuckDB local com dbt-fusion** _(escolhida)_ — reutiliza 100% do pipeline dbt existente, zero custo de cloud, performance suficiente para o volume (~5k linhas), compatível com Power BI via arquivo `.duckdb`.

---

## Decisão

Adotar DuckDB como target padrão de desenvolvimento. BigQuery é preservado como target `dev` para uso futuro em produção ou quando houver acesso GCP disponível.

### Engine

O projeto usa **dbt-fusion 2.0.0-preview** (binário Rust) que suporta DuckDB nativamente. Não é necessário instalar `dbt-duckdb` (Python adapter) para rodar localmente.

### Configuração de profiles

O arquivo `~/.dbt/profiles.yml` passou a ter dois outputs para o perfil `portfolio_estate_analytics`:

```yaml
portfolio_estate_analytics:
  target: local          # padrão alterado de dev para local
  outputs:
    dev:                 # BigQuery — preservado sem alterações
      type: bigquery
      ...
    local:               # DuckDB — novo
      type: duckdb
      path: '<projeto>/data/local.duckdb'
      threads: 4
      extensions:
        - parquet
```

### Carregamento de fontes raw

O dbt-fusion não suporta `meta.external_location` em fontes (funcionalidade do adapter Python `dbt-duckdb`). Em vez disso, os Parquets são registrados como **views DuckDB** via script de inicialização:

```bash
py -3.14 scripts/init_duckdb.py
```

O script cria o schema `raw` e as views `raw.raw_payments` e `raw.raw_receivables` apontando para todos os Parquets via `read_parquet(..., union_by_name=true)`. Só precisa ser executado uma vez (ou após apagar o arquivo `.duckdb`).

### Nome do arquivo DuckDB

O arquivo chama-se `local.duckdb` (não `warehouse.duckdb`) porque o DuckDB usa o nome do arquivo sem extensão como nome do catálogo SQL. O source `database: "{{ env_var('GCP_PROJECT_ID', 'local') }}"` resolve para `local` quando sem credenciais GCP, e o SQL compilado referencia `"local"."raw"."raw_payments"` — que corresponde ao catálogo `local.duckdb`.

---

## Ajustes de Compatibilidade nos Models

Dois padrões de SQL BigQuery-específico foram substituídos por equivalentes ANSI para garantir portabilidade:

| Arquivo | Antes (BigQuery) | Depois (ANSI/cross-DB) |
|---------|-----------------|------------------------|
| `stg_payments.sql`, `stg_receivables.sql` | `SELECT * EXCEPT (_row_num)` | `SELECT *` (coluna descartada pela CTE `renamed`) |
| `dim_date.sql` | `FORMAT_DATE('%Y-%m', date_day)` | `CAST(EXTRACT(YEAR ...) AS STRING) \|\| '-' \|\| LPAD(...)` |

**Nota sobre `EXTRACT(DAYOFWEEK FROM date_day)` em `dim_date.sql`:** DuckDB retorna 0=Domingo, 6=Sábado (indexação 0-based) enquanto BigQuery retorna 1=Domingo, 7=Sábado. A fórmula `MOD(DAYOFWEEK + 5, 7) + 1` calibrada para BigQuery produz valores de `day_of_week`, `day_name` e `is_weekend` incorretos em DuckDB. Isso é uma limitação conhecida: os dados de fct_installments e dimensões financeiras são corretos; apenas esses campos de metadado do calendário diferem. Uma correção futura pode usar Jinja condicional por target.

Os testes de PII (`tests/raw/assert_no_cpf_*.sql`, `tests/raw/assert_no_cnpj_*.sql`) também foram adaptados para usar `regexp_full_match()` em DuckDB e `REGEXP_CONTAINS()` em BigQuery, via bloco Jinja `{% if target.type == 'duckdb' %}`.

---

## Raciocínio

- **Portabilidade máxima**: mesmo pipeline dbt, dois engines. Trocar de target não muda lógica de negócio.
- **Zero custo**: DuckDB é embarcado, sem infraestrutura cloud.
- **Performance suficiente**: volume ~5k linhas materializa em < 1 segundo.
- **Abertura para BI**: Power BI, DBeaver e outros clientes ODBC/JDBC podem conectar diretamente no `.duckdb`.
- **Reversibilidade**: `dbt build --target dev` retoma o pipeline em BigQuery quando o acesso GCP for restaurado.

---

## Consequências

- O arquivo `data/local.duckdb` nunca deve ser versionado (adicionado ao `.gitignore`).
- Rodar `py -3.14 scripts/init_duckdb.py` é pré-requisito do primeiro `dbt build --target local` em uma máquina nova.
- Para BigQuery (`--target dev`): usar o binário `dbt` (dbt-fusion) normalmente.
- `dim_date` produzirá valores incorretos de `day_of_week`/`day_name`/`is_weekend` em DuckDB até correção futura.
