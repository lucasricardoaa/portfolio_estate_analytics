-- Falha se uma parcela 'pending' tiver value_payment preenchido
-- ou uma parcela 'paid' tiver value_payment nulo.
-- Codifica a regra de negócio: apenas parcelas pagas têm valor de pagamento.
SELECT *
FROM {{ ref('fct_installments') }}
WHERE
    (payment_status = 'pending' AND value_payment IS NOT NULL)
    OR
    (payment_status = 'paid'    AND value_payment IS NULL)
