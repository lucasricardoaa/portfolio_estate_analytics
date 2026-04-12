# ADR-001: Engine de Processamento e Estratégia de Armazenamento

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** storage, engine, bigquery, dbt, gcp, infraestrutura, portfólio, privacidade

---

## Contexto

Este projeto é um portfólio técnico público hospedado no GitHub, construído
com dbt Core. A fonte de dados consiste em 12 arquivos XLSX (total ~629 KB)
de envio mensal contendo parcelas pagas e não pagas de contratos imobiliários
de uma incorporadora, organizadas em duas abas por arquivo.

Os dados são reais e contêm informações sensíveis de pessoas físicas
(potencialmente CPF, CNPJ, nome) e dados comercialmente sensíveis da
incorporadora. Nenhum dado original pode ser exposto publicamente.
O repositório GitHub é público, portanto qualquer arquivo versionado
é considerado dado público.

O desenvolvedor possui conta GCP ativa com BigQuery habilitado. O volume
do projeto (629 KB) está dentro da camada gratuita do BigQuery para
armazenamento e processamento.

---

## Decisão

Adotamos **BigQuery** como engine de armazenamento e processamento,
integrado ao dbt Core via adaptador **dbt-bigquery**. Os dados são
carregados no BigQuery via script Python local que anonimiza os arquivos
em memória e os envia diretamente para tabelas nativas — sem persistência
intermediária de dados anonimizados em disco e sem uso de GCS.

Uma cópia local em formato Parquet é salva em `/data/processed/` após
cada carga bem-sucedida, para fins de log e inspeção. Essa pasta nunca
é versionada.

### O que entra no repositório Git (público)

- Modelos dbt, testes, documentação e configurações do projeto
- Scripts Python sem credenciais, salt ou mapeamentos reais:
  `scripts/anonymize_and_load_template.py` e
  `scripts/verify_anonymization.py`
- ADRs em `docs/adr/`

### O que NUNCA entra no repositório Git

- Os arquivos XLSX originais com dados reais (`/data/original/`)
- Os arquivos Parquet anonimizados (`/data/processed/`)
- Credenciais GCP (service account JSON, `application_default_credentials.json`)
- O script completo de anonimização com salt e mapeamentos reais
  (`scripts/anonymize_and_load.py`)
- O arquivo `profiles.yml` do dbt

### Fluxo completo de dados

```
[Máquina local — fora do repositório]

/data/original/XLSX originais (dados reais)
        ↓
scripts/anonymize_and_load.py
  1. Lê o XLSX original via openpyxl
  2. Anonimiza campos sensíveis em memória (ADR-003)
  3. Salva cópia Parquet em /data/processed/YYYY-MM/
     (sobrescreve se já existir)
  4. Carrega no BigQuery via google-cloud-bigquery API
        ↓
BigQuery (dataset: raw)           ← privado na conta GCP
  ├── raw_payments
  └── raw_receivables
        ↓
dbt run (staging → intermediate → marts)

[Nunca entra no Git]
/data/original/     ❌
/data/processed/    ❌
credentials/        ❌
profiles.yml        ❌
anonymize_and_load.py (completo) ❌
```

### Salvaguardas técnicas obrigatórias no `.gitignore`

```
# Dados — NUNCA versionar
/data/original/
/data/processed/

# Credenciais GCP — NUNCA versionar
*.json
application_default_credentials.json
service_account*.json

# dbt
profiles.yml

# Script completo de anonimização (com salt e mapeamentos)
scripts/anonymize_and_load.py

# Logs de execução — nunca versionar
/logs/
```

---

## Motivação

- **Valor de portfólio:** BigQuery é amplamente adotado em produção
  em empresas de todos os tamanhos — demonstrar domínio de dbt com
  BigQuery tem maior reconhecimento de mercado do que soluções locais
- **Custo zero:** 629 KB de dados estão muito abaixo dos limites
  gratuitos do BigQuery — 10 GB de armazenamento e 1 TB de queries
  por mês sem cobrança
- **Segurança superior à abordagem local:** dados anonimizados nunca
  são persistidos em disco local nem no repositório — saem da memória
  do script direto para o BigQuery, eliminando o risco de commit
  acidental de dados tratados
- **Infraestrutura gerenciada:** sem necessidade de instalar, configurar
  ou manter um banco de dados local
- **dbt-bigquery** é o adaptador dbt mais utilizado em produção,
  com documentação extensa e comunidade ativa

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| DuckDB local + dbt-duckdb | Menor valor de portfólio; zero custo mas sem demonstração de habilidades cloud; descartado em favor do BigQuery |
| GCS + BigQuery External Tables | Adiciona GCS como serviço intermediário sem benefício real; External Tables não suportam XLSX nativamente; mais complexo sem ganho |
| PostgreSQL local + dbt-postgres | Sem valor de cloud; exige instalação e manutenção local; inferior ao BigQuery para portfólio |
| BigQuery + upload manual via console GCP | Processo manual e não reproduzível; incompatível com boas práticas de engenharia de dados |
| Converter XLSX para CSV antes do carregamento | Etapa manual adicional; perde estrutura de abas; o script Python resolve isso em memória sem necessidade de conversão explícita |

---

## Consequências

### Positivas

- O portfólio demonstra conhecimento de BigQuery, dbt-bigquery e
  integração Python com GCP — stack relevante no mercado
- Dados originais nunca saem da máquina do desenvolvedor
- Dados anonimizados nunca tocam o repositório Git público
- A cópia Parquet em `/data/processed/` permite inspeção e auditoria
  local do que foi carregado no BigQuery sem necessidade de queries
- O dataset no BigQuery é privado — apenas o código é público

### Negativas / Trade-offs

- **Barreira de entrada para avaliadores:** quem clonar o repositório
  precisará de conta GCP com BigQuery e credenciais configuradas para
  executar o projeto do zero — diferente de DuckDB, que roda sem
  dependências externas
- **Dependência de conectividade:** o script de carga requer conexão
  com a internet; DuckDB funcionaria offline
- **Risco de billing GCP:** improvável para este volume, mas o cartão
  vinculado à conta GCP pode ser acionado em caso de erro de
  configuração — recomenda-se ativar alertas de billing no console GCP
- **Credenciais locais:** o desenvolvedor deve gerenciar credenciais
  GCP na máquina local com cuidado — nunca versioná-las

### Implicações de privacidade

- Os dados originais contêm informações de pessoas físicas sujeitas
  à LGPD. Esses dados nunca saem da máquina do desenvolvedor e nunca
  são versionados
- Os dados que chegam ao BigQuery são anonimizados conforme ADR-003
  e não configuram dados pessoais nos termos da LGPD
- O dataset BigQuery é privado — acessível apenas com credenciais
  da conta GCP do desenvolvedor
- O desenvolvedor deve garantir que `/data/original/` nunca seja
  sincronizado com serviços de nuvem pública (Google Drive, Dropbox,
  iCloud, etc.) sem criptografia adicional

---

## Decisões relacionadas

- **Influencia:** ADR-002 (Ingestão) — o script Python substitui
  o `read_xlsx()` do DuckDB como mecanismo de ingestão
- **Influencia:** ADR-003 (Anonimização) — a anonimização ocorre
  em memória dentro do script antes do carregamento no BigQuery
- **Influencia:** ADR-004 (Camadas dbt) — o adaptador dbt-bigquery
  define materializações, schemas e comportamento dos modelos

---

## Notas para agentes Claude CLI

- Este projeto usa **dbt-bigquery** como adaptador. Nunca gere
  configurações de `profiles.yml` para outros adaptadores
- O `profiles.yml` está no `.gitignore` — nunca instrua o usuário
  a versioná-lo
- Os dados chegam ao dbt via tabelas nativas do BigQuery no dataset
  `raw` — nunca via `read_xlsx()` ou seeds
- As tabelas de entrada são `raw.raw_payments` e `raw.raw_receivables`
- Nunca referencie `/data/original/` ou `/data/processed/` em
  modelos dbt, scripts versionados ou documentação pública
- Credenciais GCP nunca entram no repositório em nenhuma forma —
  nem como variáveis hardcoded, nem como arquivos JSON
- Se o usuário pedir para configurar autenticação GCP, oriente a usar
  `gcloud auth application-default login` ou service account
  configurada via variável de ambiente `GOOGLE_APPLICATION_CREDENTIALS`
- Ao gerar alertas de billing, oriente o usuário a configurá-los
  no console GCP em Billing → Budgets & Alerts
