-- Falha se date_reference não for o primeiro dia do mês.
-- Se este teste falhar, uma subpasta em /data/original/ tem nome incorreto
-- (não está no formato YYYY-MM) ou o script de ingestão gerou date_reference incorreto.
SELECT *
FROM {{ ref('stg_payments') }}
WHERE EXTRACT(DAY FROM date_reference) != 1

UNION ALL

SELECT *
FROM {{ ref('stg_receivables') }}
WHERE EXTRACT(DAY FROM date_reference) != 1
