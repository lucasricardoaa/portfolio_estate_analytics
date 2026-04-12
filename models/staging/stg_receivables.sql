WITH source AS (
    SELECT * FROM {{ source('raw', 'raw_receivables') }}
),

latest_upload AS (
    SELECT
        date_reference,
        MAX(date_upload) AS max_date_upload
    FROM source
    GROUP BY date_reference
),

deduplicated AS (
    SELECT source.*
    FROM source
    INNER JOIN latest_upload
        ON  source.date_reference = latest_upload.date_reference
        AND source.date_upload    = latest_upload.max_date_upload
),

renamed AS (
    SELECT
        -- metadados de rastreabilidade
        CAST(run_id               AS STRING)   AS run_id,
        CAST(date_reference       AS DATE)     AS date_reference,
        CAST(date_upload          AS DATETIME) AS date_upload,
        CAST(titular_type         AS STRING)   AS titular_type,
        'pending'                              AS payment_status,

        -- campos anonimizados
        CAST(estate_code          AS INT64)    AS estate_code,
        CAST(estate_name          AS STRING)   AS estate_name,
        CAST(estate_address       AS STRING)   AS estate_address,
        CAST(contract_code        AS STRING)   AS contract_code,
        CAST(titular_name         AS STRING)   AS titular_name,
        CAST(titular_code         AS STRING)   AS titular_code,

        -- campos operacionais
        CAST(unit_id              AS INT64)    AS unit_id,
        CAST(unit_name            AS STRING)   AS unit_name,
        CAST(installment_id       AS INT64)    AS installment_id,
        CAST(installment_type     AS STRING)   AS installment_type,
        CAST(emission_date        AS DATE)     AS emission_date,
        CAST(base_date            AS DATE)     AS base_date,
        CAST(date_maturity        AS DATE)     AS date_maturity,
        CAST(NULL                 AS DATE)     AS date_payment,
        CAST(situation            AS STRING)   AS situation,
        CAST(condition_id         AS STRING)   AS condition_id,

        -- campos do imóvel
        CAST(property_type        AS STRING)   AS property_type,
        CAST(floor                AS STRING)   AS floor,
        CAST(private_area         AS NUMERIC)  AS private_area,
        CAST(common_area          AS NUMERIC)  AS common_area,
        CAST(usable_area          AS NUMERIC)  AS usable_area,
        CAST(terrain_area         AS NUMERIC)  AS terrain_area,
        CAST(estate_schedule_code AS STRING)   AS estate_schedule_code,
        CAST(estate_typology_code AS STRING)   AS estate_typology_code,

        -- campos financeiros
        CAST(original_value       AS NUMERIC)  AS original_value,
        CAST(present_value        AS NUMERIC)  AS present_value,
        CAST(value_with_addiction AS NUMERIC)  AS value_with_addiction,
        CAST(NULL                 AS NUMERIC)  AS value_payment,
        CAST(value_original       AS NUMERIC)  AS value_original,
        CAST(interest_rate        AS NUMERIC)  AS interest_rate,
        CAST(index                AS STRING)   AS index,
        CAST(financing_type       AS STRING)   AS financing_type,

        -- campos auxiliares
        CAST(note                 AS STRING)   AS note

    FROM deduplicated
)

SELECT * FROM renamed
