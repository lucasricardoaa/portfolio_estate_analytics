-- Falha se encontrar qualquer valor no formato de CPF (NNN.NNN.NNN-NN)
-- na coluna titular_code após anonimização.
-- Se este teste falhar, o script de anonimização não substituiu o CPF corretamente.
SELECT *
FROM {{ source('raw', 'raw_payments') }}
WHERE
{% if target.type == 'duckdb' %}
    regexp_full_match(CAST(titular_code AS STRING), '^\d{3}\.\d{3}\.\d{3}-\d{2}$')
{% else %}
    REGEXP_CONTAINS(CAST(titular_code AS STRING), r'^\d{3}\.\d{3}\.\d{3}-\d{2}$')
{% endif %}
