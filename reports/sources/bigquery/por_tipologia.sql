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
FROM dbt_dev_marts.fct_installments f
JOIN dbt_dev_marts.dim_unit u
  ON f.unit_sk = u.unit_sk
GROUP BY u.estate_typology_code, u.property_type
ORDER BY total_contratos DESC
