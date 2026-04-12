-- Falha se a mesma parcela aparecer mais de uma vez por mês
-- após o UNION ALL de payments e receivables.
-- Uma parcela não pode ser paid E pending no mesmo carregamento.
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(*) AS occurrences
FROM {{ ref('int_installments_unified') }}
GROUP BY 1, 2, 3
HAVING occurrences > 1
