SELECT
  f.date_reference,
  t.titular_type,
  COUNT(DISTINCT f.contract_sk)                        AS contratos,
  COUNTIF(f.payment_status = 'pending')                AS pendentes,
  COUNTIF(f.payment_status = 'paid')                   AS pagas
FROM dbt_dev_marts.fct_installments f
JOIN dbt_dev_marts.dim_titular t
  ON f.titular_sk = t.titular_sk
GROUP BY f.date_reference, t.titular_type
ORDER BY f.date_reference, t.titular_type
