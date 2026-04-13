# ADR-007: Observabilidade e Monitoramento do Pipeline

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** observabilidade, monitoramento, logs, bigquery, pipeline, qualidade

---

## Contexto

O pipeline do projeto é composto por duas etapas sequenciais executadas
manualmente pelo desenvolvedor:

1. `scripts/anonymize_and_load.py` — anonimiza os XLSX e carrega no BigQuery
2. `dbt build` — executa transformações e testes camada a camada

Ambas as etapas podem falhar silenciosamente ou parcialmente:
- O script pode carregar alguns meses com sucesso e falhar em outros
- O `dbt build` pode passar em alguns testes e falhar em outros
- Reprocessamentos podem ocorrer sem registro do que foi carregado antes

Sem observabilidade, o desenvolvedor não tem como responder perguntas como:
- "Esse mês já foi carregado? Quando?"
- "O último `dbt build` passou em todos os testes?"
- "Quantos registros foram carregados por mês?"

O projeto é executado localmente, sem orquestrador, sem CI/CD e sem
infraestrutura de monitoramento externa. A solução de observabilidade
deve ser simples, sem dependências externas além do que já existe no
projeto, e deve agregar valor demonstrável ao portfólio.

---

## Decisão

Adotamos duas camadas de observabilidade complementares:

**Camada 1 — Logs locais em JSON** (`/logs/`)
Registro imediato de cada execução do script, independente de
conectividade. Útil para debugar falhas de conexão com o BigQuery.

**Camada 2 — Tabela de execuções no BigQuery** (`raw.pipeline_runs`)
Histórico persistente e queryável de todas as execuções do script.
Permite análises sobre o comportamento do pipeline ao longo do tempo.

Alertas são emitidos apenas no terminal via módulo `logging` do Python,
com níveis `INFO`, `WARNING` e `ERROR` — sem dependências externas.

### Camada 1: Logs locais em JSON

**Localização:** `/logs/YYYY-MM-DD_HH-MM-SS_run.json`

**Estrutura do arquivo de log:**

```json
{
  "run_id": "uuid-gerado-a-cada-execucao",
  "started_at": "2023-01-15T14:32:01Z",
  "finished_at": "2023-01-15T14:32:47Z",
  "duration_seconds": 46,
  "status": "success",
  "months_processed": [
    {
      "month": "2023-01",
      "status": "success",
      "rows_loaded_payments": 106,
      "rows_loaded_receivables": 651,
      "date_upload": "2023-01-15T14:32:05Z"
    },
    {
      "month": "2023-02",
      "status": "success",
      "rows_loaded_payments": 98,
      "rows_loaded_receivables": 612,
      "date_upload": "2023-01-15T14:32:21Z"
    }
  ],
  "errors": []
}
```

Em caso de falha parcial, o campo `status` do mês afetado é `"error"`,
o campo `errors` lista as mensagens de erro, e os meses subsequentes
ainda são processados — o script não aborta na primeira falha.

**Configuração do `.gitignore`:**

```
# Logs de execução — nunca versionar
/logs/
```

---

### Camada 2: Tabela de execuções no BigQuery

**Tabela:** `raw.pipeline_runs`

**Schema:**

| Coluna | Tipo | Descrição |
|---|---|---|
| `run_id` | STRING | UUID único por execução do script |
| `started_at` | DATETIME | Início da execução |
| `finished_at` | DATETIME | Fim da execução |
| `duration_seconds` | INT64 | Duração total em segundos |
| `run_status` | STRING | `'success'`, `'partial'` ou `'error'` |
| `month_reference` | DATE | Mês processado (`date_reference`) |
| `month_status` | STRING | `'success'` ou `'error'` por mês |
| `rows_loaded_payments` | INT64 | Linhas carregadas em `raw_payments` |
| `rows_loaded_receivables` | INT64 | Linhas carregadas em `raw_receivables` |
| `date_upload` | DATETIME | Timestamp do carregamento (igual ao das tabelas raw) |
| `error_message` | STRING | Mensagem de erro se `month_status = 'error'` |

Uma linha é inserida por mês processado por execução. Uma execução
que processa 12 meses gera 12 linhas em `pipeline_runs`.

**Consultas úteis sobre `pipeline_runs`:**

```sql
-- Histórico de execuções por mês
SELECT
    month_reference,
    COUNT(*) AS total_execucoes,
    MAX(date_upload) AS ultima_carga,
    SUM(rows_loaded_payments) AS total_payments,
    SUM(rows_loaded_receivables) AS total_receivables
FROM raw.pipeline_runs
WHERE month_status = 'success'
GROUP BY 1
ORDER BY 1;

-- Execuções com falha
SELECT *
FROM raw.pipeline_runs
WHERE month_status = 'error'
ORDER BY started_at DESC;

-- Verificar se todos os meses foram carregados
SELECT
    month_reference,
    MAX(date_upload) AS ultima_carga,
    MAX(rows_loaded_payments) AS payments,
    MAX(rows_loaded_receivables) AS receivables
FROM raw.pipeline_runs
WHERE month_status = 'success'
GROUP BY 1
ORDER BY 1;
```

---

### Alertas no terminal via `logging`

O script usa o módulo `logging` do Python com formatação colorida
via `colorlog` (dependência adicionada ao `requirements.txt`).

**Níveis de log utilizados:**

| Nível | Quando usar |
|---|---|
| `INFO` | Início e fim de cada mês processado, contagem de linhas carregadas |
| `WARNING` | Reprocessamento detectado (mês já existente em `pipeline_runs`) |
| `ERROR` | Falha no carregamento de um mês — script continua para o próximo |
| `CRITICAL` | Falha de autenticação GCP ou conexão com BigQuery — script aborta |

**Exemplo de saída no terminal:**

```
[INFO]  2023-01-15 14:32:01 — Iniciando pipeline: 12 meses encontrados em /data/original/
[INFO]  2023-01-15 14:32:05 — [2023-01] payments: 106 linhas carregadas
[INFO]  2023-01-15 14:32:07 — [2023-01] receivables: 651 linhas carregadas
[WARNING] 2023-01-15 14:32:07 — [2023-01] Reprocessamento detectado — mês já carregado em 2023-01-10
[INFO]  2023-01-15 14:32:21 — [2023-02] payments: 98 linhas carregadas
...
[INFO]  2023-01-15 14:32:47 — Pipeline concluído: 12/12 meses com sucesso — duração: 46s
```

---

### Observabilidade do `dbt build`

O `dbt build` já produz saída detalhada no terminal por padrão.
Para preservar histórico das execuções dbt, redirecionar a saída
para um arquivo de log:

```bash
dbt build 2>&1 | tee logs/dbt_$(date +%Y-%m-%d_%H-%M-%S).log
```

Os logs do dbt são salvos em `/logs/` junto com os logs do script
de ingestão — mesma pasta, mesmo `.gitignore`.

---

### Entradas no `.gitignore`

A seguinte entrada foi adicionada ao `.gitignore` do projeto
(já aplicada):

```
# Logs de execução — nunca versionar
/logs/
```

---

### Dependência no `requirements.txt`

A seguinte dependência foi adicionada ao `requirements.txt`
(já aplicada):

```
colorlog
```

---

## Motivação

- **Logs locais em JSON:** independentes de conectividade — se o
  BigQuery estiver indisponível, o log local ainda registra a tentativa;
  formato JSON permite parsing programático se necessário
- **Tabela `pipeline_runs` no BigQuery:** histórico persistente e
  queryável; demonstra conhecimento de instrumentação de pipelines —
  diferencial de portfólio; permite detectar meses não carregados
  via query simples
- **Alerta de reprocessamento (`WARNING`):** informa o desenvolvedor
  quando um mês está sendo carregado mais de uma vez, sem bloquear
  a execução — comportamento documentado como intencional no ADR-002
- **`logging` do Python + `colorlog`:** sem dependências externas
  além do ecossistema Python; saída clara e legível no terminal;
  padrão reconhecido no mercado
- **Logs do `dbt` em arquivo:** preserva histórico de execuções dbt
  sem nenhuma configuração adicional — `tee` é suficiente para o escopo

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Apenas logs no terminal (sem persistência) | Não permite responder "esse mês já foi carregado?" após fechar o terminal |
| Apenas tabela BigQuery (sem arquivo local) | Falhas de conexão com o BigQuery não seriam registradas em nenhum lugar |
| Alertas por e-mail | Adiciona dependência externa (SMTP ou serviço de e-mail) desnecessária para uso local |
| Prefect ou Airflow para orquestração e logs | Excessivo para um pipeline executado manualmente uma vez por mês; adiciona complexidade de infraestrutura incompatível com o escopo |
| OpenTelemetry ou Datadog | Ferramentas de observabilidade de produção; custo e complexidade incompatíveis com portfólio local |

---

## Consequências

### Positivas

- O desenvolvedor sabe exatamente o que foi carregado, quando e
  quantas linhas — sem precisar fazer queries nas tabelas raw
- Reprocessamentos são visíveis e rastreáveis sem interromper o pipeline
- A tabela `pipeline_runs` é um artefato analítico por si só —
  demonstra instrumentação de pipeline no portfólio
- Logs locais garantem rastreabilidade mesmo sem conexão com o BigQuery
- Histórico de execuções do `dbt build` preservado em `/logs/`

### Negativas / Trade-offs

- **`colorlog` como dependência adicional:** pequena, mas é mais
  uma dependência no `requirements.txt`
- **Logs locais não são versionados:** se a máquina for formatada,
  o histórico local se perde — a tabela BigQuery é o histórico
  persistente definitivo
- **`pipeline_runs` é append-only:** assim como as tabelas raw,
  acumula linhas a cada execução — para o volume deste projeto
  o custo é irrelevante

---

## Decisões relacionadas

- **Depende de:** ADR-001 (Engine) — a tabela `pipeline_runs` é
  criada no mesmo projeto GCP e dataset `raw` definidos no ADR-001;
  `/logs/` entra no `.gitignore` definido no ADR-001
- **Depende de:** ADR-002 (Ingestão) — o `run_id` e `date_upload`
  registrados em `pipeline_runs` são os mesmos gravados nas tabelas
  raw, permitindo correlação entre execuções e dados carregados
- **Depende de:** ADR-006 (Testes) — os logs do `dbt build` são
  preservados em `/logs/` com o mesmo padrão de nomenclatura

---

## Notas para agentes Claude CLI

- A tabela `pipeline_runs` fica no dataset `raw` do BigQuery —
  nunca no dataset de staging ou marts
- O `run_id` em `pipeline_runs` deve ser o mesmo UUID gerado no
  início de cada execução do script — use `uuid.uuid4()` no Python
- O arquivo de log local deve ser gerado em `/logs/` com nome no
  formato `YYYY-MM-DD_HH-MM-SS_run.json` — nunca em outro diretório
- `/logs/` está no `.gitignore` — nunca instrua o usuário a versionar
  arquivos de log
- Ao gerar o script `anonymize_and_load.py`, inclua sempre:
  a inicialização do `logging` com `colorlog`, a criação do arquivo
  de log local, e a inserção de registros em `pipeline_runs` ao
  final de cada mês processado
- O alerta de `WARNING` para reprocessamento deve ser emitido quando
  `pipeline_runs` já contiver um registro com o mesmo `month_reference`
  — nunca bloqueie a execução por isso
- Para redirecionar logs do `dbt build`, sempre use o comando:
  `dbt build 2>&1 | tee logs/dbt_$(date +%Y-%m-%d_%H-%M-%S).log`
- Se o usuário perguntar "esse mês já foi carregado?", oriente a
  consultar `pipeline_runs` via BigQuery — não as tabelas raw
