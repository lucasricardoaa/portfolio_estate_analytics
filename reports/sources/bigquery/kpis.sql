SELECT
  COUNT(DISTINCT contract_sk)                                         AS total_contratos,
  COUNT(*)                                                            AS total_parcelas,
  COUNTIF(payment_status = 'pending')                                AS parcelas_pendentes,
  COUNTIF(payment_status = 'paid')                                   AS parcelas_pagas,
  ROUND(
    COUNTIF(payment_status = 'pending') / COUNT(*) * 100, 1
  )                                                                   AS taxa_inadimplencia_pct,
  ROUND(SUM(CASE WHEN payment_status = 'pending'
    THEN present_value ELSE 0 END), 2)                               AS valor_em_aberto,
  ROUND(SUM(CASE WHEN payment_status = 'paid'
    THEN value_payment ELSE 0 END), 2)                               AS valor_recebido
FROM dbt_dev_marts.fct_installments
