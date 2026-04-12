WITH source AS (
    SELECT * FROM {{ ref('int_installments_unified') }}
),

ranked AS (
    SELECT
        titular_code,
        titular_name,
        titular_type,
        ROW_NUMBER() OVER (
            PARTITION BY titular_code
            ORDER BY date_reference DESC, date_upload DESC
        ) AS rn
    FROM source
),

deduped AS (
    SELECT
        titular_code,
        titular_name,
        titular_type
    FROM ranked
    WHERE rn = 1
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['titular_code']) }} AS titular_sk,
        titular_code,
        titular_name,
        titular_type
    FROM deduped
)

SELECT * FROM final
