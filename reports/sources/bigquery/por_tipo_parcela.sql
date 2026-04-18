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
FROM dbt_dev_marts.fct_installments
GROUP BY installment_type
ORDER BY carteira_total DESC
