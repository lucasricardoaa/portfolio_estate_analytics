# ADR-002: Estratégia de Ingestão dos Arquivos XLSX

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** ingestão, xlsx, python, bigquery, gcp, staging

---

## Contexto

O projeto recebe 12 arquivos XLSX de envio mensal, cada um contendo duas
abas com nomes fixos em inglês: `payments` (parcelas pagas) e `receivables`
(parcelas não pagas) de contratos imobiliários de uma incorporadora.

As duas abas compartilham a maior parte do schema, com uma diferença
estrutural relevante: a aba `payments` possui duas colunas adicionais
ausentes em `receivables` — `value_payment` e `date_payment` — o que é
semanticamente correto, pois parcelas não pagas ainda não possuem data
ou valor de pagamento efetivo.

A estrutura de colunas é idêntica entre os 12 arquivos mensais. Os arquivos
originais ficam em `/data/original/` na máquina do desenvolvedor,
organizados em subpastas por mês de referência. Nenhum arquivo original
é versionado. O BigQuery é o destino final dos dados anonimizados (ADR-001).

Todos os 12 arquivos estão disponíveis desde o início do projeto —
não há ingestão incremental contínua.

### Schema da aba `payments` (parcelas pagas)

| Coluna | Tipo observado | Classificação |
|---|---|---|
| `estate_code` | INTEGER | Dado comercial sensível — identifica a incorporadora |
| `estate_name` | VARCHAR | Dado comercial sensível — nome do empreendimento |
| `contract_code` | VARCHAR | Dado operacional sensível |
| `titular_name` | VARCHAR | PII — nome do titular |
| `titular_code` | VARCHAR | PII — CPF ou CNPJ do titular |
| `estate_schedule_code` | VARCHAR | Dado operacional |
| `estate_typology_code` | VARCHAR | Dado operacional |
| `emission_date` | DATE | Dado operacional |
| `situation` | VARCHAR | Dado operacional |
| `property_type` | VARCHAR | Dado operacional |
| `floor` | VARCHAR | Dado operacional |
| `private_area` | DECIMAL | Dado operacional |
| `common_area` | DECIMAL | Dado operacional |
| `usable_area` | DECIMAL | Dado operacional |
| `terrain_area` | DECIMAL | Dado operacional |
| `note` | VARCHAR | Dado operacional |
| `estate_address` | VARCHAR | Dado comercial sensível — endereço do empreendimento |
| `unit_id` | INTEGER | Dado operacional |
| `unit_name` | VARCHAR | Dado operacional |
| `installment_type` | VARCHAR | Dado operacional |
| `date_maturity` | DATE | Dado operacional |
| `present_value` | DECIMAL | Dado financeiro |
| `original_value` | DECIMAL | Dado financeiro |
| `value_with_addiction` | DECIMAL | Dado financeiro |
| `condition_id` | VARCHAR | Dado operacional |
| `installment_id` | INTEGER | Dado operacional |
| `base_date` | DATE | Dado operacional |
| `value_payment` | DECIMAL | Exclusivo `payments` — valor pago |
| `date_payment` | DATE | Exclusivo `payments` — data do pagamento |
| `interest_rate` | DECIMAL | Dado financeiro |
| `index` | VARCHAR | Dado operacional |
| `financing_type` | VARCHAR | Dado operacional |
| `value_original` | DECIMAL | Dado financeiro |

### Schema da aba `receivables` (parcelas não pagas)

Schema idêntico ao de `payments`, exceto pela **ausência** de:
- `value_payment`
- `date_payment`

---

## Decisão

Adotamos um script Python local (`scripts/anonymize_and_load.py`) que
processa **todos os arquivos XLSX em uma única execução**, iterando sobre
as subpastas de `/data/original/`. O script anonimiza cada arquivo em
memória (ADR-003) e carrega os dados diretamente nas tabelas nativas do
BigQuery via `google-cloud-bigquery` API.

Após cada carga bem-sucedida por arquivo, uma cópia Parquet dos dados
anonimizados é salva em `/data/processed/YYYY-MM/`. Se já existir um
arquivo Parquet para aquele mês, ele é sobrescrito.

### Organização dos arquivos originais em `/data/original/`

Cada arquivo XLSX deve estar em uma subpasta nomeada com o mês de
referência no formato `YYYY-MM`. O nome do arquivo dentro da pasta
pode ser qualquer um — o script usa apenas o nome da pasta pai como
`date_reference`.

```
/data/original/
  ├── 2023-01/
  │     └── relatorio_gallipar_extension_1_2023_0_0_3.xlsx
  ├── 2023-02/
  │     └── relatorio_gallipar_extension_2_2023_0_0_3.xlsx
  ├── 2023-03/
  │     └── relatorio_gallipar_extension_3_2023_0_0_3.xlsx
  ...
  └── 2023-12/
        └── relatorio_gallipar_extension_12_2023_0_0_3.xlsx
```

Cada subpasta deve conter **exatamente um arquivo XLSX**. O script
encerra com erro se encontrar zero ou mais de um arquivo em qualquer
subpasta.

### Colunas de rastreabilidade adicionadas pelo script

O script adiciona quatro colunas de controle em todos os registros
antes do carregamento no BigQuery:

| Coluna | Tipo | Descrição |
|---|---|---|
| `run_id` | STRING | UUID único da execução do script que gerou este registro — correlaciona com `raw.pipeline_runs` |
| `date_reference` | DATE | Primeiro dia do mês de referência derivado do nome da subpasta (`YYYY-MM` → `YYYY-MM-01`) |
| `date_upload` | DATETIME | Timestamp UTC do momento exato da execução do script |
| `titular_type` | STRING | Classificação `'PF'` ou `'PJ'` extraída do formato original de `titular_code` **antes** do hash — gerada pelo script de anonimização |

Essas colunas permitem:
- Filtrar todos os registros de um mês específico via `date_reference`
- Identificar e distinguir múltiplos carregamentos do mesmo mês
  via `date_upload`
- Correlacionar cada linha das tabelas raw com sua execução em
  `raw.pipeline_runs` via `run_id`
- Auditar reprocessamentos sem perda de histórico

### Destino no BigQuery

```
Projeto GCP
└── dataset: raw
      ├── tabela: raw_payments      ← aba payments de todos os XLSX
      └── tabela: raw_receivables   ← aba receivables de todos os XLSX
```

As tabelas são **append-only**: cada execução do script adiciona os
registros de todos os arquivos processados. Reprocessamentos do mesmo
mês geram um novo lote identificado por `date_upload` distinto —
o histórico de carregamentos é preservado intencionalmente.

A seleção do carregamento mais recente por mês é responsabilidade
dos modelos dbt de staging, via `MAX(date_upload)` por `date_reference`
(detalhado no ADR-004).

### Tratamento da diferença de schema entre abas

A aba `receivables` não possui `value_payment` e `date_payment`.
O script adiciona essas colunas com valor `None` (NULL no BigQuery)
antes do carregamento, garantindo schema uniforme entre as duas
tabelas de destino.

### Estrutura dos arquivos gerados em `/data/processed/`

```
/data/processed/
  ├── 2023-01/
  │     ├── payments.parquet
  │     └── receivables.parquet
  ├── 2023-02/
  │     ├── payments.parquet
  │     └── receivables.parquet
  ...
```

Arquivos Parquet existentes são sobrescritos se o script for executado
novamente. Esta pasta nunca é versionada (ADR-001).

### Execução do script

```bash
python scripts/anonymize_and_load.py
```

Sem parâmetros — o script descobre automaticamente todos os meses
disponíveis em `/data/original/` e os processa em ordem cronológica.

### Dependências do script

```
google-cloud-bigquery
google-cloud-bigquery[pandas]
openpyxl
pandas
pyarrow
faker
colorlog
```

Todas registradas em `requirements.txt`, versionado no repositório.

---

## Motivação

- **Execução única:** processar todos os 12 arquivos em uma chamada
  é mais robusto, reproduzível e elegante do que execuções manuais
  por arquivo — elimina risco de esquecer meses ou executar fora de ordem
- **Pasta como `date_reference`:** derivar o mês do nome da subpasta
  elimina a necessidade de arquivo de configuração externo ou renomeação
  dos arquivos originais — convenção simples e sem ambiguidade
- **`date_reference` + `date_upload`:** solução de rastreabilidade
  que permite auditoria completa de carregamentos sem apagar histórico,
  com custo de armazenamento irrelevante para este volume
- **Anonimização em memória:** dados sensíveis nunca são persistidos
  em disco em formato intermediário
- **Cópia Parquet local:** permite inspeção e validação dos dados
  anonimizados sem queries no BigQuery

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Execução por arquivo com parâmetro `--month` | Mais frágil, exige 12 execuções manuais, maior risco de inconsistência entre meses |
| Arquivo de configuração com mapeamento nome → mês | Adiciona um artefato de configuração para manter; a convenção de subpastas é mais simples e autoexplicativa |
| WRITE_TRUNCATE por partição no BigQuery | Abordagem correta para produção, mas remove o histórico de carregamentos — optou-se por preservar rastreabilidade via `date_upload` neste portfólio |
| `read_xlsx()` nativo do DuckDB | Dependia do DuckDB como engine — descartado com a migração para BigQuery (ADR-001) |
| Upload para GCS + External Tables | Adiciona GCS como dependência sem benefício real; External Tables não suportam XLSX nativamente |
| dbt seeds | Não projetados para dados brutos; sem suporte a XLSX |

---

## Consequências

### Positivas

- Uma única execução processa todos os 12 meses de forma ordenada
  e reproduzível
- A rastreabilidade por `date_reference` e `date_upload` permite
  auditoria completa de todos os carregamentos
- Múltiplos carregamentos do mesmo mês são identificáveis e não
  corrompem dados anteriores
- Dados sensíveis nunca tocam o disco local em formato intermediário
- Adicionar um novo mês exige apenas criar a subpasta correspondente
  em `/data/original/` — nenhuma alteração de código

### Negativas / Trade-offs

- **Acúmulo de dados por reprocessamento:** carregamentos repetidos
  do mesmo mês acumulam registros na tabela raw — em produção seria
  inaceitável pelo custo de armazenamento; para este portfólio é
  aceitável e documentado como decisão intencional
- **Seleção do carregamento mais recente no dbt:** os modelos de
  staging precisam filtrar pelo `MAX(date_upload)` por `date_reference`
  — adiciona uma camada de lógica que não existiria com WRITE_TRUNCATE
- **Exatamente um XLSX por subpasta:** o script falha se a convenção
  for violada — mas essa falha explícita é preferível a comportamento
  silencioso incorreto
- **Sem paralelismo:** os arquivos são processados sequencialmente;
  irrelevante para 12 arquivos de ~52 KB cada

---

## Decisões relacionadas

- **Depende de:** ADR-001 (Engine) — BigQuery é o destino definido
  no ADR-001; o script é o mecanismo de carga escolhido
- **Depende de:** ADR-003 (Anonimização) — a anonimização ocorre
  dentro do script antes do carregamento; as técnicas são definidas
  no ADR-003
- **Influencia:** ADR-004 (Camadas dbt) — os modelos de staging
  referenciam `raw.raw_payments` e `raw.raw_receivables` e devem
  implementar a lógica de seleção pelo `MAX(date_upload)`
- **Influencia:** ADR-005 (Modelagem dimensional) — a diferença de
  schema entre abas (`value_payment` e `date_payment` NULL em
  receivables) impacta a modelagem da tabela de fatos

---

## Notas para agentes Claude CLI

- As tabelas de entrada do dbt são `raw.raw_payments` e
  `raw.raw_receivables` no BigQuery — nunca `read_xlsx()` ou seeds
- Todas as tabelas raw possuem quatro colunas de rastreabilidade
  adicionadas pelo script: `run_id` (STRING), `date_reference` (DATE),
  `date_upload` (DATETIME) e `titular_type` (STRING)
- O `run_id` correlaciona cada linha das tabelas raw com sua execução
  em `raw.pipeline_runs` — preserve-o até pelo menos a camada
  intermediate
- **Padrão obrigatório em staging:** sempre filtrar pelo carregamento
  mais recente usando `MAX(date_upload)` agrupado por `date_reference`
  — nunca expor registros duplicados de reprocessamentos para camadas
  superiores
- `raw_receivables` possui `value_payment` e `date_payment` com
  valor NULL — trate essas colunas como nullable sem surpresa
- Nunca gere código que referencie `/data/original/` ou
  `/data/processed/` — essas pastas existem apenas localmente
- O script processa todos os meses em uma única execução — nunca
  oriente o usuário a executá-lo com parâmetros por arquivo
- Se o usuário reportar duplicatas nas tabelas raw, explique que
  é comportamento esperado em caso de reprocessamento — a deduplicação
  ocorre na camada de staging via `MAX(date_upload)`
- Ao gerar testes dbt para staging, inclua validação de
  `date_reference` como NOT NULL e dentro do intervalo esperado
  de datas do projeto
