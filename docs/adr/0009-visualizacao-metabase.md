# ADR-009: Visualização com Metabase

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** visualização, metabase, dashboard, portfólio, cloud, bigquery

---

## Contexto

O projeto `portfolio_estate_analytics` inclui duas camadas de
visualização complementares (ADR-000). O Metabase atua como
camada de dashboard visual — ferramenta amplamente adotada no
mercado para exploração e apresentação de dados por times de
analytics, produto e negócio.

O objetivo de incluir Metabase no portfólio é demonstrar fluência
em uma ferramenta visual de mercado, complementando o Evidence.dev
(ADR-008), que demonstra habilidade técnica com visualização como
código. Juntas, as duas ferramentas cobrem perfis distintos de
avaliadores.

Para que os dashboards sejam acessíveis por recrutadores, o Metabase
precisa de uma URL pública — sem necessidade de login ou instalação
local por parte de quem acessa.

---

## Decisão

Adotamos **Metabase Cloud** como plataforma de hospedagem do Metabase,
conectado ao BigQuery via conector nativo. O plano gratuito do
Metabase Cloud suporta até 5 usuários e oferece URL pública imediata,
sem necessidade de servidor ou infraestrutura adicional.

### Hospedagem

```
Metabase Cloud (metabase.com)
  └── Plano: Starter (gratuito)
  └── URL pública: <subdomínio>.metabaseapp.com
  └── Acesso: público para leitura — sem login para visualização
```

### Conexão com o BigQuery

O Metabase Cloud se conecta ao BigQuery via conector nativo,
autenticado por service account JSON configurada diretamente
na interface do Metabase Cloud — não exposta no repositório.

**Dataset exposto ao Metabase:**

```
portfolio_estate_analytics_marts
  ├── fct_installments
  ├── dim_titular
  ├── dim_contract
  ├── dim_unit
  └── dim_date
```

Apenas o dataset de marts é conectado ao Metabase — staging e
intermediate não são expostos.

### Dashboards planejados

Os dashboards serão definidos durante a implementação, mas devem
cobrir ao menos:

- Visão geral de inadimplência por mês de referência
- Distribuição de contratos por tipo de titular (PF vs PJ)
- Evolução de valores de parcelas ao longo do tempo
- Concentração de parcelas por tipologia de imóvel

### O que é e não é versionado

O Metabase Cloud armazena dashboards e perguntas em sua própria
infraestrutura — não há artefatos de dashboard para versionar
no repositório Git. O que é versionado é apenas este ADR.

---

## Motivação

- **Acesso público imediato:** Metabase Cloud oferece URL pública
  sem configuração de servidor — recrutadores acessam os dashboards
  diretamente pelo link, sem instalar nada
- **Ferramenta de mercado reconhecida:** Metabase é amplamente
  usado em empresas de todos os tamanhos — demonstrar fluência
  nela é um sinal de mercado relevante
- **Plano gratuito suficiente:** o plano Starter cobre o caso
  de uso do portfólio sem custo
- **Complementaridade com Evidence.dev:** Evidence.dev demonstra
  habilidade técnica com código; Metabase demonstra fluência
  visual — os dois juntos cobrem o espectro completo de
  apresentação de dados
- **Zero infraestrutura:** sem Docker, sem servidor, sem
  configuração de rede — foco total nos dashboards

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Self-hosted via Railway ou Render | Mais controle, mas adiciona complexidade de infraestrutura e risco de indisponibilidade — Metabase Cloud é mais estável para portfólio |
| Self-hosted local | Sem URL pública — recrutadores não conseguem acessar |
| Looker Studio | Gratuito e integrado ao Google, mas menos reconhecido como ferramenta de analytics engineering do que Metabase |
| Redash | Self-hosted por padrão, mais complexo de publicar com acesso público gratuito |
| Apenas Evidence.dev | Não demonstra fluência em ferramenta visual de mercado — objetivo específico do Metabase neste projeto |

---

## Consequências

### Positivas

- URL pública permanente acessível por qualquer recrutador
  sem login ou instalação
- Zero custo e zero infraestrutura para manter
- Conector nativo com BigQuery — configuração simples e estável
- Demonstra conhecimento de ferramenta amplamente adotada
  no mercado

### Negativas / Trade-offs

- **Dashboards não versionados:** perguntas e dashboards criados
  no Metabase Cloud ficam na infraestrutura da ferramenta —
  não há versionamento Git nativo; se a conta for encerrada,
  os dashboards se perdem
- **Limite do plano gratuito:** o plano Starter tem restrições
  de funcionalidades avançadas (alertas, embedding público
  irrestrito, etc.) — suficiente para portfólio, mas limitado
  para uso em produção
- **Dependência de serviço externo:** o Metabase Cloud pode
  mudar seus termos ou encerrar o plano gratuito — risco baixo
  mas existente para um portfólio de longo prazo

---

## Decisões relacionadas

- **Depende de:** ADR-005 (Modelagem dimensional) — os modelos
  de marts são a fonte de dados exclusiva dos dashboards
- **Relacionado a:** ADR-008 (Evidence.dev) — as duas ferramentas
  são complementares; dashboards não devem ser duplicados entre
  elas sem propósito claro
- **Relacionado a:** ADR-001 (Engine) — o BigQuery é o destino
  de dados compartilhado entre dbt, Evidence.dev e Metabase

---

## Notas para agentes Claude CLI

- O Metabase consome apenas modelos de **marts** — nunca oriente
  o usuário a expor staging ou intermediate ao Metabase
- Dashboards e perguntas são criados na interface do Metabase Cloud
  — não gere código de dashboard para o Metabase
- A service account usada para conectar o Metabase ao BigQuery
  é configurada na interface do Metabase Cloud — nunca exposta
  no repositório Git
- Se o usuário pedir para versionar dashboards do Metabase,
  explique que o Metabase Cloud não suporta versionamento Git
  nativo — dashboards e perguntas ficam na infraestrutura da ferramenta
- O Metabase é configurado diretamente a partir dos datasets
  no BigQuery — não são necessários arquivos de referência no repositório
