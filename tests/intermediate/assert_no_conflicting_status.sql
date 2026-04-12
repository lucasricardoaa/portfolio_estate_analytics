-- Falha se uma parcela aparecer como 'paid' e 'pending'
-- no mesmo mês de referência.
-- Se este teste falhar, verifique a lógica de deduplicação em staging
-- e o UNION ALL em int_installments_unified.
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(DISTINCT payment_status) AS status_count
FROM {{ ref('int_installments_unified') }}
GROUP BY 1, 2, 3
HAVING status_count > 1
