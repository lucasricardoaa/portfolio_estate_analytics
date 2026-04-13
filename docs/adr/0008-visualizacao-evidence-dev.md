# ADR-008: Visualização com Evidence.dev

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** visualização, evidence-dev, dashboard, portfólio, sql, markdown

---

## Contexto

O projeto `portfolio_estate_analytics` entrega modelos analíticos
dimensionais na camada de marts do BigQuery (ADR-005). Para que o
portfólio seja completo e demonstre habilidades além da engenharia
de dados, é necessária uma camada de visualização que consuma esses
modelos e produza análises navegáveis.

Evidence.dev é uma ferramenta de dashboards como código: análises
são escritas em Markdown com blocos SQL embutidos e renderizadas
como páginas web estáticas. O resultado pode ser publicado como
site estático no GitHub Pages, Netlify ou Vercel — sem servidor,
sem custo e com URL pública acessível por recrutadores.

A escolha de Evidence.dev como camada de visualização principal
é motivada pelo alinhamento com a filosofia do projeto: tudo como
código, versionado no Git, reproduzível. Dashboards em Markdown + SQL
são revisáveis, difusíveis e demonstram fluência analítica de forma
mais transparente do que uma ferramenta de arrastar e soltar.

---

## Decisão

Adotamos **Evidence.dev** como ferramenta de visualização principal
do projeto, conectada diretamente ao BigQuery via plugin oficial
`@evidence-labs/bigquery`. Os dashboards são escritos em Markdown
com SQL embutido, versionados no Git e publicados como site estático
com URL pública.

### Conexão com o BigQuery

Evidence.dev se conecta ao BigQuery via service account ou OAuth.
As credenciais são configuradas localmente via variáveis de ambiente
— nunca versionadas.

```
EVIDENCE_BIGQUERY_PROJECT_ID=...
EVIDENCE_BIGQUERY_CREDENTIALS=...  ← path para service account JSON local
```

### Fonte de dados

Evidence.dev consome exclusivamente os modelos da camada de marts:

```
portfolio_estate_analytics_marts.fct_installments
portfolio_estate_analytics_marts.dim_titular
portfolio_estate_analytics_marts.dim_contract
portfolio_estate_analytics_marts.dim_unit
portfolio_estate_analytics_marts.dim_date
```

Nunca consultar staging ou intermediate diretamente.

### Publicação

O site gerado pelo Evidence.dev (`build/`) é publicado via Vercel
ou Netlify apontando para o subdiretório `reports/` do monorepo.
A plataforma de publicação será confirmada durante a implementação
— ambas suportam sites estáticos gratuitamente com URL pública.

O diretório `reports/build/` nunca é versionado por três razões:

1. **É um artefato gerado, não código-fonte** — assim como o
   diretório `target/` do dbt, o `build/` é o resultado de um
   processo (`evidence build`) que pode ser recriado a qualquer
   momento a partir do código-fonte. Versionar artefatos gerados
   é uma má prática.
2. **Causa ruído no histórico do Git** — a cada build, centenas
   de arquivos mudam (HTML, JS, JSON com dados das queries).
   O histórico do repositório ficaria poluído com commits de
   build que não representam nenhuma decisão de código.
3. **É desnecessário** — o Vercel ou Netlify recebe o código-fonte
   (`reports/pages/`), executa o `evidence build` no próprio
   servidor e publica o resultado automaticamente. O `build/`
   local nunca precisa ser enviado.

O que é versionado é o **código** (`reports/pages/*.md`);
a plataforma de publicação gera o **site** (`reports/build/`).

### Estrutura no monorepo

O Evidence.dev é versionado no mesmo repositório que o dbt, sob
o diretório `reports/`. Essa decisão mantém o projeto coeso —
pipeline, modelos e dashboards em um único repositório navegável
por recrutadores e agentes Claude CLI.

```
portfolio_estate_analytics/
├── models/          ← dbt (staging, intermediate, marts)
├── docs/adr/        ← ADRs
├── scripts/         ← ingestão e anonimização
└── reports/         ← Evidence.dev
      ├── pages/     ← arquivos .md com SQL embutido
      ├── sources/   ← configuração de conexão com BigQuery
      └── evidence.plugins.yaml
```

O diretório `reports/build/` gerado pelo Evidence.dev nunca é
versionado — apenas o código-fonte das páginas e configurações
entra no repositório.

Adições ao `.gitignore`:

```
# Evidence.dev
/reports/build/
/reports/.evidence/
/reports/node_modules/
```

---

## Motivação

- **Dashboard como código:** análises versionadas no Git são
  revisáveis, difusíveis e demonstram raciocínio analítico de
  forma transparente — diferencial de portfólio
- **Publicação estática gratuita:** sem servidor, sem custo,
  URL pública acessível por qualquer recrutador
- **SQL nativo:** Evidence.dev executa SQL diretamente no BigQuery —
  sem camada de abstração adicional, sem duplicação de lógica
- **Alinhamento com a stack:** Markdown + SQL + Git é coerente com
  a filosofia do projeto e com o perfil de Analytics Engineer
- **Complementaridade com Metabase:** Evidence.dev demonstra
  habilidade técnica (código); Metabase demonstra fluência em
  ferramenta visual de mercado — os dois juntos cobrem perfis
  distintos de avaliadores

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Looker Studio | Gratuito e integrado ao Google, mas sem versionamento de código — não demonstra habilidade técnica |
| Streamlit | Válido para portfólio de dados, mas mais associado a ciência de dados do que a analytics engineering |
| Redash | Self-hosted, mais complexo de publicar com URL pública gratuita |
| Apenas Metabase | Não demonstra capacidade de trabalhar com visualização como código — objetivo específico do Evidence.dev neste projeto |

---

## Consequências

### Positivas

- Dashboards versionados e revisáveis no Git — qualidade de código
  visível para recrutadores técnicos
- URL pública estática sem custo e sem servidor
- SQL dos dashboards pode ser auditado e executado independentemente
- Demonstra conhecimento de uma ferramenta moderna e crescente
  no ecossistema de Analytics Engineering

### Negativas / Trade-offs

- **Curva de aprendizado:** Evidence.dev tem sintaxe própria
  de componentes — requer familiarização antes da implementação
- **Build necessário a cada mudança:** diferente de Metabase,
  que atualiza dinamicamente, Evidence.dev requer rebuild para
  refletir mudanças nos dados

---

## Decisões relacionadas

- **Depende de:** ADR-005 (Modelagem dimensional) — os modelos
  de marts são a fonte de dados exclusiva dos dashboards
- **Depende de:** ADR-000 (Visão geral) — a decisão de monorepo
  foi tomada e está registrada no ADR-000; o Evidence.dev vive
  em `reports/` dentro do repositório principal
- **Relacionado a:** ADR-009 (Metabase) — as duas ferramentas
  são complementares e devem cobrir análises distintas sem
  duplicação

---

## Notas para agentes Claude CLI

- Evidence.dev consome apenas modelos de **marts** — nunca
  gere queries apontando para staging ou intermediate
- O projeto Evidence.dev fica no diretório `reports/` do monorepo
- Credenciais do BigQuery para o Evidence.dev são configuradas
  via variáveis de ambiente — nunca hardcoded em arquivos
  de configuração versionados
- Os diretórios `reports/build/`, `reports/.evidence/` e
  `reports/node_modules/` nunca são versionados — garantir
  que estão no `.gitignore` antes do primeiro build
- Ao gerar estrutura de arquivos para o Evidence.dev, sempre
  usar `reports/` como diretório raiz dentro do monorepo
