WITH source AS (
    SELECT * FROM {{ ref('int_installments_unified') }}
),

ranked AS (
    SELECT
        contract_code,
        titular_code,
        titular_name,
        titular_type,
        unit_id,
        emission_date,
        base_date,
        financing_type,
        value_original,
        ROW_NUMBER() OVER (
            PARTITION BY contract_code
            ORDER BY date_reference DESC, date_upload DESC
        ) AS rn
    FROM source
),

deduped AS (
    SELECT
        contract_code,
        titular_code,
        titular_name,
        titular_type,
        unit_id,
        emission_date,
        base_date,
        financing_type,
        value_original
    FROM ranked
    WHERE rn = 1
)

SELECT * FROM deduped
