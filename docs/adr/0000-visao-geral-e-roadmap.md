# ADR-000: Visão Geral e Roadmap do Projeto

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** visão-geral, roadmap, portfólio, âncora, onboarding

---

## O que é este documento

Este é o documento de âncora do projeto `portfolio_estate_analytics`.
Ele não documenta uma decisão técnica isolada — documenta o projeto
como um todo: seu propósito, sua stack, seu estado atual e o caminho
até a entrega final.

Qualquer pessoa que chegue ao repositório pela primeira vez — recrutador,
colaborador ou agente Claude CLI — deve começar por aqui antes de ler
qualquer outro ADR.

---

## Contexto

`portfolio_estate_analytics` é um projeto de portfólio técnico público
de Analytics Engineering construído por Lucas de Araújo (@lucasricardoaa).

O objetivo é demonstrar domínio end-to-end da disciplina de Analytics
Engineering: desde a ingestão e anonimização de dados reais até a
entrega de modelos analíticos dimensionais e dashboards consumíveis.

**Fonte de dados:** 12 arquivos XLSX mensais de contratos imobiliários
de uma incorporadora real, contendo parcelas pagas (`payments`) e não
pagas (`receivables`). Os dados foram anonimizados conforme LGPD antes
de qualquer ingestão — nenhum dado original é versionado ou exposto
publicamente. O processo de anonimização está documentado no ADR-003.

**Uso de IA no desenvolvimento:** o projeto utiliza Claude CLI como
ferramenta de desenvolvimento assistido — geração de SQL, estruturação
de ADRs e desenvolvimento do pipeline. Essa escolha é intencional e
transparente: o uso de IA como ferramenta de engenharia é uma habilidade
profissional, não um substituto para o raciocínio técnico do autor.
Todas as decisões arquiteturais foram tomadas e validadas por Lucas —
a IA executou, não decidiu.

---

## Stack completa do projeto

| Camada | Tecnologia | Papel |
|---|---|---|
| Anonimização e ingestão | Python (`openpyxl`, `pandas`, `Faker`, `google-cloud-bigquery`, `pyarrow`, `colorlog`) | Lê os XLSX originais, anonimiza em memória e carrega no BigQuery |
| Armazenamento e processamento | Google BigQuery | Engine principal — armazena dados raw, staging, intermediate e marts |
| Transformação | dbt Core + dbt-bigquery + dbt_utils | Camadas staging → intermediate → marts com testes integrados |
| Visualização — código | Evidence.dev | Dashboard como código — análises em Markdown + SQL, versionadas no Git |
| Visualização — visual | Metabase | Dashboard visual complementar — demonstração de ferramenta amplamente adotada no mercado |
| Documentação arquitetural | ADRs (este repositório) | Fonte de verdade para decisões técnicas — lidos por agentes CLI e colaboradores |
| Desenvolvimento assistido | Claude CLI (Anthropic) | Geração de SQL, scripts e estruturação de documentação |
| Versionamento | Git + GitHub (público) | Repositório público — dados sensíveis nunca versionados |

---

## Fluxo de dados end-to-end

```
[Máquina local — nunca versionado]
/data/original/YYYY-MM/arquivo.xlsx
        ↓
scripts/anonymize_and_load.py
  · Anonimiza em memória (ADR-003)
  · Salva cópia Parquet em /data/processed/ (auditoria local)
  · Registra execução em raw.pipeline_runs (ADR-007)
  · Carrega em raw.raw_payments e raw.raw_receivables
        ↓
[BigQuery — privado na conta GCP]
dataset: raw
  ├── raw_payments
  ├── raw_receivables
  └── pipeline_runs
        ↓
dbt build
dataset: portfolio_estate_analytics_staging
  ├── stg_payments      (deduplicação por MAX(date_upload))
  └── stg_receivables   (deduplicação por MAX(date_upload))
        ↓
dataset: portfolio_estate_analytics_intermediate
  ├── int_installments_unified
  ├── int_contracts
  └── int_units
        ↓
dataset: portfolio_estate_analytics_marts
  ├── fct_installments
  ├── dim_titular
  ├── dim_contract
  ├── dim_unit
  └── dim_date
        ↓
Evidence.dev  →  Dashboard como código (SQL + Markdown)
Metabase      →  Dashboard visual complementar
```

---

## Mapa de ADRs

| ADR | Título | Status |
|---|---|---|
| ADR-000 | Visão geral e roadmap do projeto (este documento) | Aceito |
| ADR-001 | Engine de processamento e armazenamento (BigQuery) | Aceito |
| ADR-002 | Estratégia de ingestão dos arquivos XLSX | Aceito |
| ADR-003 | Anonimização e privacidade (LGPD) | Aceito |
| ADR-004 | Arquitetura de camadas dbt | Aceito |
| ADR-005 | Modelagem dimensional (Star Schema) | Aceito |
| ADR-006 | Estratégia de testes e qualidade de dados | Aceito |
| ADR-007 | Observabilidade e monitoramento do pipeline | Aceito |
| ADR-008 | Visualização com Evidence.dev | Aceito |
| ADR-009 | Visualização com Metabase | Aceito |

Os ADRs 008 e 009 foram aceitos antes do início da implementação
da camada de visualização.

---

## Estrutura do repositório

```
portfolio_estate_analytics/
├── analyses/
├── data/
│   ├── original/        ← nunca versionado — dados reais
│   └── processed/       ← nunca versionado — Parquet anonimizados
├── docs/
│   └── adr/             ← todos os ADRs do projeto
├── logs/                ← nunca versionado — logs de execução
├── macros/
├── models/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
├── reports/             ← Evidence.dev (monorepo)
│   ├── pages/
│   ├── sources/
│   └── evidence.plugins.yaml
├── scripts/
│   ├── anonymize_and_load_template.py  ← versionado (sem salt)
│   └── verify_anonymization.py         ← versionado
├── seeds/
├── tests/
│   ├── raw/
│   ├── staging/
│   ├── intermediate/
│   └── marts/
├── packages.yml
├── dbt_project.yml
├── requirements.txt
├── .gitignore
└── README.md
```

---

## Roadmap de implementação

### Fase 1 — Fundação
- Definição da stack e arquitetura
- Documentação dos ADRs 000–007
- Estrutura do repositório e `.gitignore`
- Publicação do repositório no GitHub

### Fase 2 — Ingestão e anonimização
- `scripts/anonymize_and_load_template.py`
- `scripts/anonymize_and_load.py` (local, sem salt — nunca versionado)
- `scripts/verify_anonymization.py`
- Carga inicial dos 12 meses no BigQuery
- Validação da tabela `raw.pipeline_runs`

### Fase 3 — Transformação dbt
- `dbt_project.yml` e `profiles.yml`
- `packages.yml` com dbt_utils
- Modelos de staging (`stg_payments`, `stg_receivables`)
- Modelos intermediate (`int_installments_unified`, `int_contracts`, `int_units`)
- Modelos de marts (`fct_installments`, `dim_titular`, `dim_contract`, `dim_unit`, `dim_date`)
- Testes por camada (ADR-006)
- `dbt docs generate`

### Fase 4 — Visualização
- ADR-008 (Evidence.dev)
- ADR-009 (Metabase)
- Dashboards em Evidence.dev
- Dashboards em Metabase

### Fase 5 — Finalização do portfólio
- README.md completo com instruções de reprodução
- Revisão final dos ADRs
- Publicação e divulgação

---

## Convenções globais do projeto

- **Idioma do código:** inglês — nomes de colunas, modelos, variáveis e funções
- **Idioma da documentação:** português — ADRs, comentários e README
- **Tipos BigQuery:** `INT64`, `STRING`, `NUMERIC`, `DATE`, `DATETIME` — nunca tipos de outros engines
- **Credenciais:** sempre via `env_var()` ou variável de ambiente — nunca hardcoded
- **Dados sensíveis:** nunca versionados em nenhuma forma — ver ADR-001 e ADR-003
- **Decisões arquiteturais:** sempre documentadas em ADR antes da implementação

---

## Decisões relacionadas

Este documento referencia todos os ADRs do projeto. Para qualquer
decisão técnica específica, consulte o ADR correspondente no mapa
acima.

---

## Notas para agentes Claude CLI

- **Comece sempre por este documento** antes de ler qualquer outro ADR
- Após ler o ADR-000, leia os ADRs 001–009 em ordem numérica
- Para saber em qual fase do roadmap o projeto se encontra, inspecione
  a estrutura de arquivos e os commits do repositório
- Os ADRs 008 (Evidence.dev) e 009 (Metabase) estão Aceitos — decisões
  de visualização podem ser tomadas com base neles
- O uso de Claude CLI no desenvolvimento é uma decisão aceita e
  documentada — não é necessário disclaimar isso em cada resposta
- Nunca referencie `/data/original/`, `/data/processed/` ou `/logs/`
  em código versionado — essas pastas existem apenas localmente
- Se encontrar conflito entre este documento e qualquer outro ADR,
  o ADR específico prevalece — este documento é orientação geral,
  não especificação técnica
