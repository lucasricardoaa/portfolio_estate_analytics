---
title: Tipologia de Imóveis
---

# Tipologia de Imóveis

Concentração de contratos e inadimplência por tipologia de imóvel e tipo de propriedade.

```sql por_tipologia
SELECT * FROM bigquery.por_tipologia
```

<DataTable data={por_tipologia}>
  <Column id="tipologia" title="Tipologia" />
  <Column id="tipo_propriedade" title="Tipo de Propriedade" />
  <Column id="total_contratos" title="Contratos" />
  <Column id="total_parcelas" title="Parcelas" />
  <Column id="carteira_total" title="Carteira (R$)" fmt="num2" />
  <Column id="valor_em_aberto" title="Em Aberto (R$)" fmt="num2" />
  <Column id="taxa_inadimplencia_pct" title="Inadimplência (%)" fmt="num1" />
</DataTable>

<BarChart
  data={por_tipologia}
  x="tipologia"
  y="total_contratos"
  title="Contratos por tipologia"
  xAxisTitle="Tipologia"
  yAxisTitle="Qtd. contratos"
/>

<BarChart
  data={por_tipologia}
  x="tipologia"
  y="taxa_inadimplencia_pct"
  title="Taxa de inadimplência por tipologia (%)"
  xAxisTitle="Tipologia"
  yAxisTitle="Taxa (%)"
/>

---

```sql area_media
SELECT * FROM bigquery.area_media
```

## Características das Unidades por Tipologia

<DataTable data={area_media}>
  <Column id="tipologia" title="Tipologia" />
  <Column id="tipo_propriedade" title="Tipo" />
  <Column id="total_unidades" title="Unidades" />
  <Column id="area_privativa_media" title="Área Privativa Média (m²)" fmt="num1" />
  <Column id="area_util_media" title="Área Útil Média (m²)" fmt="num1" />
  <Column id="area_comum_media" title="Área Comum Média (m²)" fmt="num1" />
</DataTable>

---

> [Voltar à visão geral](/)
