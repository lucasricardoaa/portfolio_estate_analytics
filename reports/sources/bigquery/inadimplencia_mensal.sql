SELECT
  date_reference,
  COUNT(*)                                              AS total_parcelas,
  COUNTIF(payment_status = 'pending')                  AS pendentes,
  COUNTIF(payment_status = 'paid')                     AS pagas,
  ROUND(
    COUNTIF(payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_pct,
  ROUND(SUM(CASE WHEN payment_status = 'pending'
    THEN present_value ELSE 0 END), 2)                 AS valor_pendente
FROM dbt_dev_marts.fct_installments
GROUP BY date_reference
ORDER BY date_reference
