-- Referência: Dashboard de Evolução Financeira — Metabase
-- Fonte: portfolio_estate_analytics_marts

-- 1. Evolução mensal: valor recebido vs. em aberto
SELECT
  date_reference,
  ROUND(SUM(present_value), 2)                         AS carteira_total,
  ROUND(SUM(CASE WHEN payment_status = 'paid'
    THEN value_payment ELSE 0 END), 2)                 AS valor_recebido,
  ROUND(SUM(CASE WHEN payment_status = 'pending'
    THEN present_value ELSE 0 END), 2)                 AS valor_em_aberto,
  COUNT(DISTINCT contract_sk)                           AS contratos_ativos,
  COUNT(*)                                              AS total_parcelas
FROM `portfolio_estate_analytics_marts.fct_installments`
GROUP BY date_reference
ORDER BY date_reference;


-- 2. Distribuição de valores por tipo de parcela
SELECT
  installment_type,
  COUNT(*)                                              AS total_parcelas,
  ROUND(SUM(present_value), 2)                         AS carteira_total,
  ROUND(AVG(present_value), 2)                         AS valor_medio,
  ROUND(SUM(CASE WHEN payment_status = 'paid'
    THEN value_payment ELSE 0 END), 2)                 AS valor_recebido,
  ROUND(SUM(CASE WHEN payment_status = 'pending'
    THEN present_value ELSE 0 END), 2)                 AS valor_em_aberto,
  ROUND(
    COUNTIF(payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_inadimplencia_pct
FROM `portfolio_estate_analytics_marts.fct_installments`
GROUP BY installment_type
ORDER BY carteira_total DESC;


-- 3. Spread entre valor original e valor presente (correção/juros)
SELECT
  date_reference,
  ROUND(SUM(original_value), 2)                        AS valor_original_total,
  ROUND(SUM(present_value), 2)                         AS valor_presente_total,
  ROUND(SUM(present_value) - SUM(original_value), 2)  AS spread_total,
  ROUND(
    (SUM(present_value) - SUM(original_value))
    / NULLIF(SUM(original_value), 0) * 100, 2
  )                                                     AS spread_pct
FROM `portfolio_estate_analytics_marts.fct_installments`
WHERE payment_status = 'pending'
GROUP BY date_reference
ORDER BY date_reference;
