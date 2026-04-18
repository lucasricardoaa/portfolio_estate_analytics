# portfolio_estate_analytics

Projeto de portfólio de Analytics Engineering construído por [Lucas de Araújo](https://github.com/lucasricardoaa).

Demonstra um pipeline end-to-end sobre dados reais de contratos imobiliários:
anonimização conforme LGPD → ingestão no BigQuery → transformação com dbt → dashboards com Evidence.dev.

---

## Stack

| Camada | Tecnologia |
|---|---|
| Anonimização e ingestão | Python (`pandas`, `openpyxl`, `Faker`, `google-cloud-bigquery`, `pyarrow`, `colorlog`) |
| Armazenamento | Google BigQuery |
| Transformação | dbt Core + dbt-bigquery + dbt_utils |
| Visualização (código) | Evidence.dev |
| Visualização (visual) | Metabase |
| Versionamento | Git + GitHub |

---

## Arquitetura

```
[Local — nunca versionado]
/data/original/*.xlsx  (12 meses de contratos imobiliários)
        ↓
scripts/anonymize_and_load.py
  · Anonimiza CPF/CNPJ e nomes em memória (Faker)
  · Carrega em BigQuery (raw.raw_payments, raw.raw_receivables)
  · Registra execução em raw.pipeline_runs
        ↓
[BigQuery]
raw          → raw_payments, raw_receivables, pipeline_runs
        ↓  dbt build
staging      → stg_payments, stg_receivables
        ↓
intermediate → int_installments_unified, int_contracts, int_units
        ↓
marts        → fct_installments, dim_titular, dim_contract, dim_unit, dim_date
        ↓
Evidence.dev  (dashboards como código)
Metabase      (dashboards visuais)
```

**Modelo dimensional:** star schema com `fct_installments` como tabela fato (granularidade parcela × mês) e 4 dimensões. Três FKs para `dim_date` (mês de referência, vencimento, pagamento). SCD Type 1 em todas as dimensões.

---

## Estrutura do repositório

```
portfolio_estate_analytics/
├── analyses/              ← queries de referência para Metabase
├── docs/
│   └── adr/               ← ADRs 000–009 (fonte de verdade arquitetural)
├── models/
│   ├── staging/           ← stg_payments, stg_receivables
│   ├── intermediate/      ← int_installments_unified, int_contracts, int_units
│   └── marts/             ← fct_installments, dim_*, dim_date
├── reports/               ← Evidence.dev (páginas + queries BigQuery)
├── scripts/
│   ├── anonymize_and_load_template.py   ← template sem credenciais
│   └── verify_anonymization.py          ← valida ausência de PII
├── tests/
│   ├── raw/               ← 4 testes de PII residual (CPF/CNPJ)
│   ├── staging/           ← 3 testes (deduplicação, date_reference)
│   ├── intermediate/      ← 2 testes (unicidade pós-UNION, status)
│   └── marts/             ← 2 testes de consistência financeira
├── dbt_project.yml
├── packages.yml
└── requirements.txt
```

---

## Como reproduzir

### Pré-requisitos

- Python 3.10+
- Google Cloud SDK (`gcloud`) autenticado
- Projeto GCP com BigQuery habilitado
- Node.js 18+ (para Evidence.dev)

### 1. Instalar dependências Python

```bash
pip install -r requirements.txt
dbt deps
```

### 2. Configurar credenciais

```bash
gcloud auth application-default login
export GCP_PROJECT_ID=seu-projeto-gcp
```

Copie o template de ingestão e preencha `HASH_SALT`, `FAKER_SEED` e `ESTATE_MAPPING`:

```bash
cp scripts/anonymize_and_load_template.py scripts/anonymize_and_load.py
```

### 3. Ingestão

```bash
# Anonimiza os XLSX e carrega no BigQuery
python scripts/anonymize_and_load.py

# Valida ausência de PII antes de qualquer commit
python scripts/verify_anonymization.py
```

### 4. Transformação dbt

```bash
dbt build
```

### 5. Documentação dbt

```bash
dbt docs generate
dbt docs serve
# → http://localhost:8080
```

### 6. Dashboards Evidence.dev

```bash
cd reports
npm install --legacy-peer-deps
npm run sources   # executa queries contra BigQuery
npm run dev       # → http://localhost:3000
```

---

## Testes de qualidade

| Camada | Testes |
|---|---|
| `raw` | Ausência de CPF e CNPJ em `raw_payments` e `raw_receivables` |
| `staging` | Deduplicação por `MAX(date_upload)`, `date_reference` = 1º do mês |
| `intermediate` | Unicidade pós-UNION, ausência de status conflitante |
| `marts` | `date_payment_sk` nulo apenas para `pending`, `value_payment` nulo apenas para `pending` |

---

## Privacidade e LGPD

Nenhum dado original é versionado ou exposto publicamente.
A anonimização ocorre **em memória**, antes de qualquer escrita no disco ou no BigQuery:
CPF e CNPJ são substituídos por hashes com salt; nomes por pseudônimos gerados com Faker.
O script `verify_anonymization.py` valida a ausência de PII residual nas tabelas raw.
Detalhes em [ADR-003](docs/adr/0003-anonimizacao-e-privacidade.md).

---

## Decisões arquiteturais

Todas as decisões técnicas estão documentadas em ADRs em `docs/adr/`.
Comece pelo [ADR-000](docs/adr/0000-visao-geral-e-roadmap.md) para uma visão geral do projeto.

---

## Uso de IA no desenvolvimento

Este projeto utiliza Claude CLI como ferramenta de desenvolvimento assistido —
geração de SQL, estruturação de ADRs e desenvolvimento do pipeline.
Essa escolha é intencional e transparente: o uso de IA como ferramenta de engenharia
é uma habilidade profissional, não um substituto para o raciocínio técnico do autor.
Todas as decisões arquiteturais foram tomadas e validadas por Lucas — a IA executou, não decidiu.
