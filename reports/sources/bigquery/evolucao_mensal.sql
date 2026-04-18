SELECT
  date_reference,
  ROUND(SUM(present_value), 2)                         AS carteira_total,
  ROUND(SUM(CASE WHEN payment_status = 'paid'
    THEN value_payment ELSE 0 END), 2)                 AS valor_recebido,
  ROUND(SUM(CASE WHEN payment_status = 'pending'
    THEN present_value ELSE 0 END), 2)                 AS valor_em_aberto,
  COUNT(DISTINCT contract_sk)                           AS contratos_ativos,
  COUNT(*)                                              AS total_parcelas
FROM dbt_dev_marts.fct_installments
GROUP BY date_reference
ORDER BY date_reference
