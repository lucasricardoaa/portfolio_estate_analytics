-- Referência: Dashboard de Inadimplência — Metabase
-- Fonte: portfolio_estate_analytics_marts
-- Uso: criar perguntas e dashboard no Metabase Cloud conectado ao BigQuery

-- 1. Taxa de inadimplência por mês de referência
SELECT
  f.date_reference,
  COUNT(*)                                              AS total_parcelas,
  COUNTIF(f.payment_status = 'pending')                AS pendentes,
  COUNTIF(f.payment_status = 'paid')                   AS pagas,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct,
  ROUND(SUM(CASE WHEN f.payment_status = 'pending'
    THEN f.present_value ELSE 0 END), 2)               AS valor_pendente
FROM `portfolio_estate_analytics_marts.fct_installments` f
GROUP BY f.date_reference
ORDER BY f.date_reference;


-- 2. Inadimplência por empreendimento
SELECT
  u.estate_name,
  COUNT(*)                                              AS total_parcelas,
  COUNTIF(f.payment_status = 'pending')                AS pendentes,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct,
  ROUND(SUM(CASE WHEN f.payment_status = 'pending'
    THEN f.present_value ELSE 0 END), 2)               AS valor_pendente
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_unit` u
  ON f.unit_sk = u.unit_sk
GROUP BY u.estate_name
ORDER BY taxa_inadimplencia_pct DESC;


-- 3. Inadimplência por tipo de titular e mês
SELECT
  f.date_reference,
  t.titular_type,
  COUNTIF(f.payment_status = 'pending')                AS pendentes,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_titular` t
  ON f.titular_sk = t.titular_sk
GROUP BY f.date_reference, t.titular_type
ORDER BY f.date_reference, t.titular_type;
