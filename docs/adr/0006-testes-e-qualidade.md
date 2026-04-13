# ADR-006: Estratégia de Testes e Qualidade de Dados

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** testes, qualidade, dbt, bigquery, data-quality, staging, marts

---

## Contexto

O projeto transforma dados reais anonimizados de contratos imobiliários
em modelos analíticos dimensionais. A cadeia de transformação envolve
três camadas dbt (staging → intermediate → marts) alimentadas por duas
tabelas raw no BigQuery (`raw_payments` e `raw_receivables`).

Há dois vetores de risco de qualidade neste projeto:

**Risco de ingestão:** o script `anonymize_and_load.py` pode carregar
dados incompletos, duplicados (por reprocessamento) ou com anonimização
mal aplicada. Esses problemas chegam silenciosamente ao dbt se não
houver testes nas tabelas raw e na camada de staging.

**Risco de transformação:** joins incorretos, deduplicação falha por
`MAX(date_upload)`, chaves surrogate não únicas ou referências FK
quebradas podem corromper silenciosamente os modelos de marts sem
que o `dbt build` falhe.

A estratégia de testes deve cobrir ambos os vetores, camada por camada,
sem criar overhead excessivo para um projeto de portfólio.

---

## Decisão

Adotamos testes dbt nativos (genéricos) e testes singulares (SQL customizado)
organizados por camada. Cada camada tem um conjunto de testes com foco
específico. Todos os testes são executados via `dbt test` antes de qualquer
entrega de modelo.

### Visão geral por camada

```
[raw]        → testes de completude e ausência de PII residual
[staging]    → testes de deduplicação, tipagem e campos obrigatórios
[intermediate] → testes de unicidade pós-union e integridade de joins
[marts]      → testes de integridade referencial e consistência de negócio
```

---

### Testes na camada Raw

Os testes raw são executados via `dbt source test` sobre as tabelas
`raw.raw_payments` e `raw.raw_receivables` declaradas em `_stg_sources.yml`.

**Testes genéricos:**

```yaml
sources:
  - name: raw
    tables:
      - name: raw_payments
        columns:
          - name: date_reference
            tests:
              - not_null
          - name: date_upload
            tests:
              - not_null
          - name: contract_code
            tests:
              - not_null
          - name: installment_id
            tests:
              - not_null

      - name: raw_receivables
        columns:
          - name: date_reference
            tests:
              - not_null
          - name: date_upload
            tests:
              - not_null
          - name: contract_code
            tests:
              - not_null
          - name: installment_id
            tests:
              - not_null
```

**Testes singulares — ausência de PII residual:**

Arquivo: `tests/raw/assert_no_cpf_in_raw_payments.sql`
```sql
-- Falha se encontrar qualquer valor no formato de CPF (NNN.NNN.NNN-NN)
-- na coluna titular_code após anonimização
SELECT *
FROM {{ source('raw', 'raw_payments') }}
WHERE REGEXP_CONTAINS(
    CAST(titular_code AS STRING),
    r'^\d{3}\.\d{3}\.\d{3}-\d{2}$'
)
```

Arquivo: `tests/raw/assert_no_cnpj_in_raw_payments.sql`
```sql
-- Falha se encontrar qualquer valor no formato de CNPJ
SELECT *
FROM {{ source('raw', 'raw_payments') }}
WHERE REGEXP_CONTAINS(
    CAST(titular_code AS STRING),
    r'^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$'
)
```

Os mesmos dois testes são replicados para `raw_receivables`.

---

### Testes na camada Staging

Foco: deduplicação por `MAX(date_upload)`, campos obrigatórios e
valores aceitos.

**Testes genéricos em `_stg_models.yml`:**

```yaml
models:
  - name: stg_payments
    columns:
      - name: date_reference
        tests:
          - not_null
      - name: date_upload
        tests:
          - not_null
      - name: contract_code
        tests:
          - not_null
      - name: installment_id
        tests:
          - not_null
      - name: titular_code
        tests:
          - not_null
      - name: payment_status
        tests:
          - not_null
          - accepted_values:
              values: ['paid']
      - name: titular_type
        tests:
          - not_null
          - accepted_values:
              values: ['PF', 'PJ']

  - name: stg_receivables
    columns:
      - name: payment_status
        tests:
          - not_null
          - accepted_values:
              values: ['pending']
      - name: titular_type
        tests:
          - not_null
          - accepted_values:
              values: ['PF', 'PJ']
```

**Teste singular — verificação de deduplicação:**

Arquivo: `tests/staging/assert_stg_payments_deduplicated.sql`
```sql
-- Falha se houver mais de um date_upload por contract_code +
-- installment_id + date_reference após a deduplicação do staging
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(DISTINCT date_upload) AS upload_count
FROM {{ ref('stg_payments') }}
GROUP BY 1, 2, 3
HAVING upload_count > 1
```

O mesmo teste é replicado para `stg_receivables`.

**Teste singular — formato de `date_reference`:**

Arquivo: `tests/staging/assert_date_reference_is_first_of_month.sql`
```sql
-- Falha se date_reference não for o primeiro dia do mês
-- (indica subpasta com nome incorreto em /data/original/)
SELECT *
FROM {{ ref('stg_payments') }}
WHERE EXTRACT(DAY FROM date_reference) != 1
```

---

### Testes na camada Intermediate

Foco: unicidade pós-UNION ALL e consistência de atributos entre abas.

**Teste singular — unicidade em `int_installments_unified`:**

Arquivo: `tests/intermediate/assert_int_installments_unique.sql`
```sql
-- Falha se a mesma parcela aparecer mais de uma vez por mês
-- após o UNION ALL de payments e receivables
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(*) AS occurrences
FROM {{ ref('int_installments_unified') }}
GROUP BY 1, 2, 3
HAVING occurrences > 1
```

**Teste singular — mesma parcela não pode ser paid e pending no mesmo mês:**

Arquivo: `tests/intermediate/assert_no_conflicting_status.sql`
```sql
-- Falha se uma parcela aparecer como 'paid' e 'pending'
-- no mesmo mês de referência
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(DISTINCT payment_status) AS status_count
FROM {{ ref('int_installments_unified') }}
GROUP BY 1, 2, 3
HAVING status_count > 1
```

---

### Testes na camada Marts

Foco: integridade referencial das FKs, unicidade das chaves surrogate
e consistência de negócio.

**Testes genéricos em `_marts_models.yml`:**

```yaml
models:
  - name: fct_installments
    columns:
      - name: installment_sk
        tests:
          - not_null
          - unique
      - name: contract_sk
        tests:
          - not_null
          - relationships:
              to: ref('dim_contract')
              field: contract_sk
      - name: unit_sk
        tests:
          - not_null
          - relationships:
              to: ref('dim_unit')
              field: unit_sk
      - name: titular_sk
        tests:
          - not_null
          - relationships:
              to: ref('dim_titular')
              field: titular_sk
      - name: date_reference_sk
        tests:
          - not_null
          - relationships:
              to: ref('dim_date')
              field: date_sk
      - name: date_maturity_sk
        tests:
          - not_null
          - relationships:
              to: ref('dim_date')
              field: date_sk
      - name: payment_status
        tests:
          - not_null
          - accepted_values:
              values: ['paid', 'pending']

  - name: dim_contract
    columns:
      - name: contract_sk
        tests:
          - not_null
          - unique

  - name: dim_unit
    columns:
      - name: unit_sk
        tests:
          - not_null
          - unique

  - name: dim_titular
    columns:
      - name: titular_sk
        tests:
          - not_null
          - unique
      - name: titular_type
        tests:
          - not_null
          - accepted_values:
              values: ['PF', 'PJ']

  - name: dim_date
    columns:
      - name: date_sk
        tests:
          - not_null
          - unique
```

**Teste singular — consistência financeira:**

Arquivo: `tests/marts/assert_payment_value_only_for_paid.sql`
```sql
-- Falha se uma parcela 'pending' tiver value_payment preenchido
-- ou uma parcela 'paid' tiver value_payment nulo
SELECT *
FROM {{ ref('fct_installments') }}
WHERE
    (payment_status = 'pending' AND value_payment IS NOT NULL)
    OR
    (payment_status = 'paid' AND value_payment IS NULL)
```

**Teste singular — `date_payment_sk` nulo apenas para pendentes:**

Arquivo: `tests/marts/assert_date_payment_sk_null_only_pending.sql`
```sql
SELECT *
FROM {{ ref('fct_installments') }}
WHERE
    (payment_status = 'pending' AND date_payment_sk IS NOT NULL)
    OR
    (payment_status = 'paid' AND date_payment_sk IS NULL)
```

---

### Ordem de execução dos testes

```bash
dbt test --select source:raw          # 1. Testa tabelas raw
dbt test --select staging             # 2. Testa modelos de staging
dbt test --select intermediate        # 3. Testa modelos intermediate
dbt test --select marts               # 4. Testa modelos de marts
```

Ou em uma única execução com `dbt build`:

```bash
dbt build  # executa run + test por camada em ordem de dependência
```

---

## Motivação

- **Testes de PII residual na camada raw:** garantem que o script de
  anonimização funcionou corretamente antes que os dados entrem no
  pipeline dbt — a camada mais próxima da fonte é o melhor lugar
  para detectar vazamentos
- **Teste de deduplicação em staging:** valida que a lógica de
  `MAX(date_upload)` está funcionando corretamente — sem este teste,
  duplicatas de reprocessamento passariam silenciosamente para as
  camadas superiores
- **Testes de integridade referencial em marts:** garantem que nenhuma
  FK em `fct_installments` aponta para uma chave inexistente nas
  dimensões — erros de join seriam invisíveis sem esses testes
- **Testes de consistência de negócio:** regras como "parcela paga
  deve ter `value_payment`" e "parcela pendente não pode ter
  `date_payment_sk`" codificam conhecimento do domínio e protegem
  contra regressões futuras
- **`dbt build`:** executa run e test em ordem de dependência —
  um modelo com teste falhando não é promovido para a próxima camada

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Testes apenas em marts | Não detecta problemas de ingestão ou deduplicação — erros chegam silenciosamente ao modelo final |
| Great Expectations ou Soda | Ferramentas válidas para produção, mas adicionam dependências externas desnecessárias para um portfólio que já usa testes nativos do dbt |
| Testes apenas genéricos (sem singulares) | Testes genéricos não cobrem regras de negócio como conflito de status ou consistência de valores financeiros |
| Testes de PII apenas locais (fora do dbt) | O script `verify_anonymization.py` já faz isso localmente, mas duplicar o teste no dbt garante cobertura mesmo se o script local for pulado |

---

## Consequências

### Positivas

- Qualquer falha de anonimização é detectada antes de contaminar
  os modelos dbt
- Duplicatas de reprocessamento são bloqueadas na camada de staging
- Integridade referencial do modelo dimensional é garantida
  automaticamente a cada `dbt build`
- Regras de negócio do domínio imobiliário estão codificadas e
  documentadas como testes — servem também como documentação viva
- `dbt docs generate` exibe os testes junto à documentação dos modelos

### Negativas / Trade-offs

- **Volume de testes para um dataset pequeno:** a cobertura de testes
  é mais extensa do que o estritamente necessário para 629 KB —
  mas é adequada para demonstração de boas práticas em portfólio
- **Testes singulares requerem manutenção:** se o schema mudar,
  os SQLs dos testes singulares precisam ser atualizados manualmente
- **Testes de relacionamento (`relationships`) em BigQuery consomem
  queries:** cada teste de FK executa uma query no BigQuery — para
  este volume o custo é zero, mas deve ser monitorado em escala

---

## Decisões relacionadas

- **Depende de:** ADR-002 (Ingestão) — os testes de PII residual e
  deduplicação são consequência direta das decisões de carregamento
  append-only e reprocessamento definidas no ADR-002
- **Depende de:** ADR-003 (Anonimização) — os testes de PII residual
  validam que o script de anonimização cumpriu sua função
- **Depende de:** ADR-004 (Camadas dbt) — a organização dos testes
  por camada segue a estrutura de diretórios definida no ADR-004
- **Depende de:** ADR-005 (Modelagem dimensional) — os testes de
  integridade referencial e consistência de negócio são derivados
  diretamente do modelo dimensional definido no ADR-005

---

## Notas para agentes Claude CLI

- Ao gerar um novo modelo dbt, sempre gere também o bloco de testes
  genéricos correspondente no arquivo YAML da camada
- Testes de PII (`assert_no_cpf_*` e `assert_no_cnpj_*`) devem existir
  para **ambas** as tabelas raw — nunca apenas para uma
- O teste de deduplicação (`assert_stg_*_deduplicated`) deve existir
  para **ambos** os modelos de staging
- Nunca remova o teste `relationships` de uma FK em `fct_installments`
  sem substituí-lo por outro mecanismo de validação de integridade
- O teste `assert_no_conflicting_status` é crítico — uma parcela não
  pode ser `paid` e `pending` no mesmo mês; se esse teste falhar,
  o problema está na lógica de deduplicação ou no UNION ALL de
  `int_installments_unified`
- Ao adicionar novos campos a `fct_installments`, avalie se há uma
  regra de consistência de negócio associada e crie o teste singular
  correspondente
- Use `dbt build` em vez de `dbt run` seguido de `dbt test` —
  `build` garante que modelos com testes falhando não são promovidos
- Testes de `accepted_values` para `payment_status` devem sempre
  incluir apenas `['paid', 'pending']` — nunca adicione outros valores
  sem atualizar este ADR
