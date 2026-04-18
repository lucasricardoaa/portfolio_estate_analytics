-- Referência: Dashboard de Tipologia de Imóveis — Metabase
-- Fonte: portfolio_estate_analytics_marts

-- 1. Concentração de contratos e inadimplência por tipologia
SELECT
  u.estate_typology_code                               AS tipologia,
  u.property_type                                      AS tipo_propriedade,
  COUNT(DISTINCT f.contract_sk)                        AS total_contratos,
  COUNT(*)                                              AS total_parcelas,
  ROUND(SUM(f.present_value), 2)                       AS carteira_total,
  ROUND(SUM(CASE WHEN f.payment_status = 'pending'
    THEN f.present_value ELSE 0 END), 2)               AS valor_em_aberto,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_unit` u
  ON f.unit_sk = u.unit_sk
GROUP BY u.estate_typology_code, u.property_type
ORDER BY total_contratos DESC;


-- 2. Características físicas das unidades por tipologia
SELECT
  estate_typology_code                                 AS tipologia,
  property_type                                        AS tipo_propriedade,
  COUNT(DISTINCT unit_id)                               AS total_unidades,
  ROUND(AVG(private_area), 2)                          AS area_privativa_media,
  ROUND(AVG(usable_area), 2)                           AS area_util_media,
  ROUND(AVG(common_area), 2)                           AS area_comum_media,
  ROUND(AVG(terrain_area), 2)                          AS area_terreno_media
FROM `portfolio_estate_analytics_marts.dim_unit`
GROUP BY estate_typology_code, property_type
ORDER BY total_unidades DESC;


-- 3. Evolução de inadimplência por tipologia e mês
SELECT
  f.date_reference,
  u.estate_typology_code                               AS tipologia,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct,
  COUNTIF(f.payment_status = 'pending')                AS pendentes
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_unit` u
  ON f.unit_sk = u.unit_sk
GROUP BY f.date_reference, u.estate_typology_code
ORDER BY f.date_reference, u.estate_typology_code;
