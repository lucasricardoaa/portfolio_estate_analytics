---
title: Visão Geral — Portfolio Estate Analytics
---

# Portfolio Estate Analytics

Análise de contratos imobiliários de uma incorporadora real.
Dados anonimizados conforme LGPD. Parcelas pagas e a receber de 12 meses de referência.

```sql kpis
SELECT * FROM bigquery.kpis
```

<BigValue data={kpis} value="total_contratos" title="Contratos" />
<BigValue data={kpis} value="total_parcelas" title="Parcelas" />
<BigValue data={kpis} value="taxa_inadimplencia_pct" title="Taxa de Inadimplência" fmt="num1" suffix="%" />
<BigValue data={kpis} value="valor_em_aberto" title="Valor em Aberto (R$)" fmt="num2" />
<BigValue data={kpis} value="valor_recebido" title="Valor Recebido (R$)" fmt="num2" />

---

```sql inadimplencia_mensal
SELECT * FROM bigquery.inadimplencia_mensal
```

## Inadimplência por Mês de Referência

<BarChart
  data={inadimplencia_mensal}
  x="date_reference"
  y={["pagas", "pendentes"]}
  type="stacked"
  title="Parcelas pagas vs. pendentes por mês"
  xAxisTitle="Mês de referência"
  yAxisTitle="Qtd. parcelas"
/>

<LineChart
  data={inadimplencia_mensal}
  x="date_reference"
  y="taxa_pct"
  title="Taxa de inadimplência mensal (%)"
  xAxisTitle="Mês de referência"
  yAxisTitle="Taxa (%)"
/>

---

> **Navegação:** [Inadimplência](/inadimplencia) · [Titulares](/titulares) · [Evolução Financeira](/evolucao-financeira) · [Tipologia](/tipologia)
