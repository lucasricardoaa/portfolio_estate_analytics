---
title: Evolução Financeira
---

# Evolução Financeira

Evolução mensal dos valores de parcelas: valor recebido, valor em aberto e carteira total.

```sql evolucao_mensal
SELECT * FROM bigquery.evolucao_mensal
```

<LineChart
  data={evolucao_mensal}
  x="date_reference"
  y={["valor_recebido", "valor_em_aberto"]}
  title="Valor recebido vs. em aberto por mês (R$)"
  xAxisTitle="Mês de referência"
  yAxisTitle="Valor (R$)"
/>

<BarChart
  data={evolucao_mensal}
  x="date_reference"
  y="carteira_total"
  title="Carteira total por mês (R$)"
  xAxisTitle="Mês de referência"
  yAxisTitle="Valor (R$)"
/>

<DataTable data={evolucao_mensal} rows=15>
  <Column id="date_reference" title="Mês" />
  <Column id="contratos_ativos" title="Contratos" />
  <Column id="carteira_total" title="Carteira Total (R$)" fmt="num2" />
  <Column id="valor_recebido" title="Recebido (R$)" fmt="num2" />
  <Column id="valor_em_aberto" title="Em Aberto (R$)" fmt="num2" />
</DataTable>

---

```sql por_tipo_parcela
SELECT * FROM bigquery.por_tipo_parcela
```

## Por Tipo de Parcela

<DataTable data={por_tipo_parcela}>
  <Column id="installment_type" title="Tipo de Parcela" />
  <Column id="total_parcelas" title="Qtd." />
  <Column id="carteira_total" title="Carteira (R$)" fmt="num2" />
  <Column id="valor_recebido" title="Recebido (R$)" fmt="num2" />
  <Column id="valor_em_aberto" title="Em Aberto (R$)" fmt="num2" />
  <Column id="taxa_inadimplencia_pct" title="Inadimplência (%)" fmt="num1" />
</DataTable>

---

> [Voltar à visão geral](/)
