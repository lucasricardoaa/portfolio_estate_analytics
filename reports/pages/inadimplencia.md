---
title: Inadimplência
---

# Inadimplência

Análise de parcelas pendentes por mês de referência, tipo de titular e empreendimento.

```sql por_mes
SELECT * FROM bigquery.inadimplencia_mensal
```

## Por Mês de Referência

<DataTable data={por_mes} rows=15>
  <Column id="date_reference" title="Mês" />
  <Column id="total_parcelas" title="Total" />
  <Column id="pagas" title="Pagas" />
  <Column id="pendentes" title="Pendentes" />
  <Column id="taxa_pct" title="Taxa (%)" fmt="num1" />
  <Column id="valor_pendente" title="Valor Pendente (R$)" fmt="num2" />
</DataTable>

<BarChart
  data={por_mes}
  x="date_reference"
  y="taxa_pct"
  title="Taxa de inadimplência por mês (%)"
  xAxisTitle="Mês de referência"
  yAxisTitle="Taxa (%)"
/>

---

```sql por_titular_type
SELECT * FROM bigquery.distribuicao_titular
```

## Por Tipo de Titular

<BarChart
  data={por_titular_type}
  x="titular_type"
  y="taxa_inadimplencia_pct"
  title="Taxa de inadimplência por tipo de titular (%)"
  xAxisTitle="Tipo de titular"
  yAxisTitle="Taxa (%)"
/>

---

```sql por_empreendimento
SELECT * FROM bigquery.por_empreendimento
```

## Por Empreendimento

<DataTable data={por_empreendimento}>
  <Column id="estate_name" title="Empreendimento" />
  <Column id="total_parcelas" title="Total" />
  <Column id="pendentes" title="Pendentes" />
  <Column id="taxa_pct" title="Taxa (%)" fmt="num1" />
  <Column id="valor_pendente" title="Valor Pendente (R$)" fmt="num2" />
</DataTable>

---

> [Voltar à visão geral](/)
