-- Referência: Dashboard de Titulares — Metabase
-- Fonte: portfolio_estate_analytics_marts

-- 1. Distribuição PF vs PJ — contratos e valores
SELECT
  t.titular_type,
  COUNT(DISTINCT f.contract_sk)                        AS total_contratos,
  COUNT(*)                                              AS total_parcelas,
  ROUND(SUM(f.present_value), 2)                       AS valor_total_carteira,
  ROUND(SUM(CASE WHEN f.payment_status = 'pending'
    THEN f.present_value ELSE 0 END), 2)               AS valor_em_aberto,
  ROUND(SUM(CASE WHEN f.payment_status = 'paid'
    THEN f.value_payment ELSE 0 END), 2)               AS valor_recebido,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_titular` t
  ON f.titular_sk = t.titular_sk
GROUP BY t.titular_type
ORDER BY t.titular_type;


-- 2. Evolução mensal de contratos ativos por tipo de titular
SELECT
  f.date_reference,
  t.titular_type,
  COUNT(DISTINCT f.contract_sk)                        AS contratos_ativos,
  COUNT(*)                                              AS total_parcelas
FROM `portfolio_estate_analytics_marts.fct_installments` f
JOIN `portfolio_estate_analytics_marts.dim_titular` t
  ON f.titular_sk = t.titular_sk
GROUP BY f.date_reference, t.titular_type
ORDER BY f.date_reference, t.titular_type;
