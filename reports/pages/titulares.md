---
title: Titulares
---

# Titulares

Distribuição de contratos e parcelas por tipo de titular (Pessoa Física vs. Pessoa Jurídica).

```sql distribuicao
SELECT * FROM bigquery.distribuicao_titular
```

<DataTable data={distribuicao}>
  <Column id="titular_type" title="Tipo" />
  <Column id="total_contratos" title="Contratos" />
  <Column id="total_parcelas" title="Parcelas" />
  <Column id="valor_total_carteira" title="Carteira Total (R$)" fmt="num2" />
  <Column id="valor_em_aberto" title="Em Aberto (R$)" fmt="num2" />
  <Column id="valor_recebido" title="Recebido (R$)" fmt="num2" />
  <Column id="taxa_inadimplencia_pct" title="Inadimplência (%)" fmt="num1" />
</DataTable>

<BarChart
  data={distribuicao}
  x="titular_type"
  y="total_contratos"
  title="Contratos por tipo de titular"
  xAxisTitle="Tipo de titular"
  yAxisTitle="Qtd. contratos"
/>

---

```sql evolucao_por_tipo
SELECT * FROM bigquery.evolucao_por_tipo_titular
```

## Evolução Mensal por Tipo

<LineChart
  data={evolucao_por_tipo}
  x="date_reference"
  y="pendentes"
  series="titular_type"
  title="Parcelas pendentes por tipo de titular e mês"
  xAxisTitle="Mês de referência"
  yAxisTitle="Qtd. parcelas pendentes"
/>

---

> [Voltar à visão geral](/)
