-- Falha se houver mais de um date_upload por contract_code +
-- installment_id + date_reference após a deduplicação do staging.
-- Se este teste falhar, a lógica de MAX(date_upload) em stg_receivables não está funcionando.
SELECT
    contract_code,
    installment_id,
    date_reference,
    COUNT(DISTINCT date_upload) AS upload_count
FROM {{ ref('stg_receivables') }}
GROUP BY 1, 2, 3
HAVING upload_count > 1
