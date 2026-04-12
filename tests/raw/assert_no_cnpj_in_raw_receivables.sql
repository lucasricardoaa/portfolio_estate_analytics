-- Falha se encontrar qualquer valor no formato de CNPJ (NN.NNN.NNN/NNNN-NN)
-- na coluna titular_code após anonimização.
-- Se este teste falhar, o script de anonimização não substituiu o CNPJ corretamente.
SELECT *
FROM {{ source('raw', 'raw_receivables') }}
WHERE REGEXP_CONTAINS(
    CAST(titular_code AS STRING),
    r'^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$'
)
