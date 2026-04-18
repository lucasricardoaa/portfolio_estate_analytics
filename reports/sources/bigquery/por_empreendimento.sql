SELECT
  u.estate_name,
  COUNT(*)                                              AS total_parcelas,
  COUNTIF(f.payment_status = 'pending')                AS pendentes,
  ROUND(
    COUNTIF(f.payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                     AS taxa_pct,
  ROUND(SUM(CASE WHEN f.payment_status = 'pending'
    THEN f.present_value ELSE 0 END), 2)               AS valor_pendente
FROM dbt_dev_marts.fct_installments f
JOIN dbt_dev_marts.dim_unit u
  ON f.unit_sk = u.unit_sk
GROUP BY u.estate_name
ORDER BY taxa_pct DESC
