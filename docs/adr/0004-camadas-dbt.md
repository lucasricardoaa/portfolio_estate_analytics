# ADR-004: Arquitetura de Camadas dbt

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** dbt, staging, intermediate, marts, bigquery, modelagem, arquitetura

---

## Contexto

O projeto usa dbt Core com adaptador dbt-bigquery para transformar tabelas
nativas do BigQuery em modelos analíticos prontos para consumo. Os dados
chegam ao dbt já anonimizados, carregados pelo script de ingestão (ADR-002)
nas tabelas `raw.raw_payments` e `raw.raw_receivables`.

As duas tabelas de origem compartilham o mesmo schema, com `value_payment`
e `date_payment` presentes em `raw_payments` e NULL em `raw_receivables`.

O nome do projeto dbt é **`portfolio_estate_analytics`**.

---

## Decisão

Adotamos a arquitetura de três camadas padrão do dbt: **staging**,
**intermediate** e **marts**. Cada camada tem responsabilidades
exclusivas e bem delimitadas.

### Visão geral da arquitetura

```
BigQuery — dataset: raw  (carregado pelo script de ingestão)
  ├── raw_payments
  ├── raw_receivables
  └── pipeline_runs
        ↓
[staging]  — dataset: portfolio_estate_analytics_staging
  ├── stg_payments
  └── stg_receivables
        ↓
[intermediate]  — dataset: portfolio_estate_analytics_intermediate
  ├── int_installments_unified
  ├── int_contracts
  └── int_units
        ↓
[marts]  — dataset: portfolio_estate_analytics_marts
  ├── fct_installments
  ├── dim_titular
  ├── dim_contract
  ├── dim_unit
  └── dim_date
```

---

### Camada: Staging (`models/staging/`)

**Responsabilidade única:** referenciar as tabelas raw, aplicar tipagem
explícita, renomear colunas se necessário e adicionar colunas de controle.
Nenhuma lógica de negócio, nenhum join, nenhuma agregação.

**Modelos:**

`stg_payments` — referencia `raw.raw_payments`, aplica tipagem explícita,
adiciona `payment_status = 'paid'`.

`stg_receivables` — referencia `raw.raw_receivables`, aplica tipagem
explícita, adiciona `payment_status = 'pending'`. As colunas
`value_payment` e `date_payment` já chegam como NULL da tabela raw.

**Convenções de staging:**
- Prefixo obrigatório: `stg_`
- Materialização: `view` (nunca `table` em staging)
- Tipagem explícita de todas as colunas via `CAST()`
- Colunas `run_id` (STRING), `date_reference` (DATE), `date_upload`
  (DATETIME) e `titular_type` (STRING) já disponíveis nas tabelas
  raw — não recriar, apenas tipar e propagar
- Coluna `payment_status` adicionada em ambos os modelos
- **Deduplicação obrigatória:** cada modelo de staging deve expor
  apenas o carregamento mais recente por `date_reference`, filtrando
  via `MAX(date_upload)` — nunca expor múltiplos carregamentos do
  mesmo mês para camadas superiores
- As fontes raw são declaradas em `_stg_sources.yml`

**Exemplo de estrutura de `stg_payments`:**

```sql
WITH source AS (
    SELECT * FROM {{ source('raw', 'raw_payments') }}
),

-- Seleciona apenas o carregamento mais recente por mês de referência
latest_upload AS (
    SELECT
        date_reference,
        MAX(date_upload) AS max_date_upload
    FROM source
    GROUP BY date_reference
),

deduplicated AS (
    SELECT source.*
    FROM source
    INNER JOIN latest_upload
        ON  source.date_reference = latest_upload.date_reference
        AND source.date_upload    = latest_upload.max_date_upload
),

renamed AS (
    SELECT
        -- metadados de rastreabilidade
        CAST(run_id AS STRING)                  AS run_id,
        CAST(date_reference AS DATE)            AS date_reference,
        CAST(date_upload AS DATETIME)           AS date_upload,
        CAST(titular_type AS STRING)            AS titular_type,
        'paid'                                  AS payment_status,

        -- campos anonimizados
        CAST(estate_code AS INT64)              AS estate_code,
        CAST(estate_name AS STRING)             AS estate_name,
        CAST(estate_address AS STRING)          AS estate_address,
        CAST(contract_code AS STRING)           AS contract_code,
        CAST(titular_name AS STRING)            AS titular_name,
        CAST(titular_code AS STRING)            AS titular_code,

        -- campos operacionais
        CAST(unit_id AS INT64)                  AS unit_id,
        CAST(unit_name AS STRING)               AS unit_name,
        CAST(installment_id AS INT64)           AS installment_id,
        CAST(installment_type AS STRING)        AS installment_type,
        CAST(emission_date AS DATE)             AS emission_date,
        CAST(base_date AS DATE)                 AS base_date,
        CAST(date_maturity AS DATE)             AS date_maturity,
        CAST(date_payment AS DATE)              AS date_payment,
        CAST(situation AS STRING)               AS situation,
        CAST(condition_id AS STRING)            AS condition_id,

        -- campos do imóvel
        CAST(property_type AS STRING)           AS property_type,
        CAST(floor AS STRING)                   AS floor,
        CAST(private_area AS NUMERIC)           AS private_area,
        CAST(common_area AS NUMERIC)            AS common_area,
        CAST(usable_area AS NUMERIC)            AS usable_area,
        CAST(terrain_area AS NUMERIC)           AS terrain_area,
        CAST(estate_schedule_code AS STRING)    AS estate_schedule_code,
        CAST(estate_typology_code AS STRING)    AS estate_typology_code,

        -- campos financeiros
        CAST(original_value AS NUMERIC)         AS original_value,
        CAST(present_value AS NUMERIC)          AS present_value,
        CAST(value_with_addiction AS NUMERIC)   AS value_with_addiction,
        CAST(value_payment AS NUMERIC)          AS value_payment,
        CAST(value_original AS NUMERIC)         AS value_original,
        CAST(interest_rate AS NUMERIC)          AS interest_rate,
        CAST(index AS STRING)                   AS index,
        CAST(financing_type AS STRING)          AS financing_type,

        -- campos auxiliares
        CAST(note AS STRING)                    AS note

    FROM deduplicated
)

SELECT * FROM renamed
```

**Declaração de fontes em `_stg_sources.yml`:**

```yaml
version: 2

sources:
  - name: raw
    database: "{{ env_var('GCP_PROJECT_ID') }}"
    schema: raw
    tables:
      - name: raw_payments
      - name: raw_receivables
```

---

### Camada: Intermediate (`models/intermediate/`)

**Responsabilidade:** combinar, limpar e preparar os dados de staging
para a camada de marts. Aqui ocorrem joins, unions, deduplicações e
derivações de campos calculados. Não é camada de consumo final.

**Modelos:**

`int_installments_unified` — une `stg_payments` e `stg_receivables`
via `UNION ALL`, produzindo uma visão única de todas as parcelas com
`payment_status` como discriminador.

`int_contracts` — extrai a dimensão de contratos a partir de
`int_installments_unified`, deduplica por `contract_code` e consolida
atributos do contrato e do titular anonimizado.

`int_units` — extrai a dimensão de unidades imobiliárias, deduplica
por `unit_id` e consolida atributos físicos do imóvel.

**Convenções de intermediate:**
- Prefixo obrigatório: `int_`
- Materialização: `view` como padrão; `table` apenas se houver
  justificativa de performance documentada no modelo via `config()`
- Joins somente entre modelos de staging ou entre modelos intermediate
- Nunca referenciar tabelas raw diretamente
- Nunca expor modelos intermediate como entregáveis finais

---

### Camada: Marts (`models/marts/`)

**Responsabilidade:** entregar modelos prontos para consumo analítico.
Seguem modelagem dimensional detalhada no ADR-005.

**Modelos:**

`fct_installments` — tabela de fatos no nível de parcela.

`dim_titular` — dimensão do titular anonimizado (PF ou PJ).

`dim_contract` — dimensão do contrato, com FK para titular e unidade.

`dim_unit` — dimensão da unidade imobiliária.

`dim_date` — dimensão de datas gerada via `dbt_utils.date_spine`,
cobrindo o intervalo de datas do projeto.

**Convenções de marts:**
- Fatos: prefixo `fct_`
- Dimensões: prefixo `dim_`
- Materialização: `table` para todos os modelos de marts
- Nunca referenciar staging diretamente — apenas intermediate
- Chaves surrogate geradas com `{{ dbt_utils.generate_surrogate_key([...]) }}`

---

### Pacotes dbt utilizados

Declarados em `packages.yml` na raiz do projeto:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
```

Instalar com `dbt deps` antes do primeiro `dbt build`.

---

### Estrutura de diretórios do projeto

```
portfolio_estate_analytics/
├── analyses/
├── data/
│   ├── original/        ← nunca versionado (.gitignore)
│   └── processed/       ← nunca versionado (.gitignore)
├── docs/
│   └── adr/             ← todos os ADRs do projeto
├── logs/                ← nunca versionado (.gitignore)
├── macros/
├── models/
│   ├── staging/
│   │   ├── stg_payments.sql
│   │   ├── stg_receivables.sql
│   │   ├── _stg_sources.yml
│   │   └── _stg_models.yml
│   ├── intermediate/
│   │   ├── int_installments_unified.sql
│   │   ├── int_contracts.sql
│   │   ├── int_units.sql
│   │   └── _int_models.yml
│   └── marts/
│       ├── fct_installments.sql
│       ├── dim_titular.sql
│       ├── dim_contract.sql
│       ├── dim_unit.sql
│       ├── dim_date.sql
│       └── _marts_models.yml
├── reports/             ← Evidence.dev (ADR-008)
│   ├── pages/           ← arquivos .md com SQL embutido
│   ├── sources/         ← configuração de conexão com BigQuery
│   └── evidence.plugins.yaml
├── scripts/
│   ├── anonymize_and_load_template.py  ← versionado (sem salt/mapeamento)
│   └── verify_anonymization.py         ← versionado
├── seeds/
├── tests/
│   ├── raw/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
├── packages.yml
├── .gitignore
├── dbt_project.yml
├── profiles.yml              ← nunca versionado (.gitignore)
├── requirements.txt          ← versionado
└── README.md
```

---

### Configurações em `dbt_project.yml`

```yaml
name: portfolio_estate_analytics
version: "1.0.0"
config-version: 2

profile: portfolio_estate_analytics

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]

target-path: "target"
clean-targets: ["target", "dbt_packages"]

models:
  portfolio_estate_analytics:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: view
      +schema: intermediate
    marts:
      +materialized: table
      +schema: marts
```

### Configuração de `profiles.yml` (local, nunca versionado)

```yaml
portfolio_estate_analytics:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: portfolio_estate_analytics
      threads: 4
      timeout_seconds: 300
```

---

## Motivação

- **Separação de responsabilidades:** cada camada tem função clara
  e não se sobrepõe — facilita manutenção, testes e leitura do código
- **Padrão amplamente reconhecido:** staging → intermediate → marts
  é o padrão oficial recomendado pelo dbt Labs
- **BigQuery datasets por camada:** a separação em datasets distintos
  no BigQuery (`staging`, `intermediate`, `marts`) facilita controle
  de acesso e organização no console GCP
- **`dbt_utils`:** pacote padrão do ecossistema dbt, demonstra
  conhecimento além do core da ferramenta
- **`env_var()` para credenciais:** project ID via variável de ambiente
  — nunca hardcoded, compatível com múltiplos ambientes

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Duas camadas apenas (staging + marts) | Perderia o espaço para lógica de combinação — `fct_installments` ficaria com responsabilidades demais |
| Quatro camadas (+ raw) | A camada raw já existe como dataset no BigQuery, carregado pelo script de ingestão — redundante dentro do dbt |
| Um único modelo monolítico | Inaceitável para portfólio — não demonstra conhecimento de modularização |
| Marts sem dimensões (One Big Table) | Considerado no ADR-005 — modelagem dimensional demonstra mais habilidade técnica |

---

## Consequências

### Positivas

- Estrutura imediatamente reconhecível por qualquer engenheiro de dados
  familiarizado com dbt
- Datasets separados no BigQuery por camada facilitam auditoria e
  controle de acesso
- Testes aplicados camada a camada isolam problemas com precisão
- `dbt docs generate` produz documentação automática navegável

### Negativas / Trade-offs

- **Três camadas para um dataset pequeno:** para 629 KB e duas tabelas
  fonte, a arquitetura pode parecer excessiva — mas o objetivo é
  demonstração técnica
- **Modelos intermediate como views:** reprocessados a cada query;
  aceitável para este volume

---

## Decisões relacionadas

- **Depende de:** ADR-001 (Engine) — BigQuery define os tipos
  disponíveis (`INT64`, `STRING`, `NUMERIC`, `DATE`, `DATETIME`)
  e o comportamento de views e tables
- **Depende de:** ADR-002 (Ingestão) — as tabelas `raw.raw_payments`
  e `raw.raw_receivables` são os pontos de entrada do dbt
- **Depende de:** ADR-003 (Anonimização) — staging recebe dados
  já anonimizados; nenhuma lógica de privacidade ocorre no dbt
- **Influencia:** ADR-005 (Modelagem dimensional) — estrutura de
  marts e chaves surrogate detalhadas no ADR-005
- **Influencia:** ADR-006 (Testes e qualidade) — testes organizados
  por camada seguindo esta estrutura

---

## Notas para agentes Claude CLI

- O nome do projeto dbt é `portfolio_estate_analytics` — use-o em
  `dbt_project.yml` e em referências a datasets no BigQuery
- A estrutura de camadas é `staging` → `intermediate` → `marts`
  — nunca pule camadas ou crie referências inversas
- Prefixos obrigatórios: `stg_` para staging, `int_` para
  intermediate, `fct_` e `dim_` para marts
- Modelos de staging são sempre `view` — nunca sugira `table`
- Modelos de marts são sempre `table` — nunca sugira `view`
- Nunca referencie tabelas raw diretamente em intermediate ou marts
  — sempre passe por staging
- Tipos BigQuery a usar: `INT64`, `STRING`, `NUMERIC`, `DATE`,
  `DATETIME` — nunca tipos DuckDB como `VARCHAR` ou `DECIMAL`
- O `project_id` GCP deve sempre vir de `env_var('GCP_PROJECT_ID')`
  — nunca hardcoded
- O `profiles.yml` está no `.gitignore` — nunca instrua o usuário
  a versioná-lo
- Ao gerar YAML de documentação, siga o padrão: `_stg_sources.yml`
  para declaração das fontes raw, `_stg_models.yml` para testes e
  documentação dos modelos de staging, `_int_models.yml` para
  intermediate e `_marts_models.yml` para marts
- Ao usar `dbt_utils`, sempre verifique se `packages.yml` está
  presente e se `dbt deps` foi executado
