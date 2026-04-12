-- Falha se date_payment_sk for não-nulo para parcelas pendentes
-- ou nulo para parcelas pagas.
-- Valida a integridade da FK para dim_date no papel de data de pagamento.
SELECT *
FROM {{ ref('fct_installments') }}
WHERE
    (payment_status = 'pending' AND date_payment_sk IS NOT NULL)
    OR
    (payment_status = 'paid'    AND date_payment_sk IS NULL)
