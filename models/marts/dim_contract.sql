WITH source AS (
    SELECT * FROM {{ ref('int_contracts') }}
),

dim_titular AS (
    SELECT titular_sk, titular_code
    FROM {{ ref('dim_titular') }}
),

dim_unit AS (
    SELECT unit_sk, unit_id
    FROM {{ ref('dim_unit') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['source.contract_code']) }} AS contract_sk,
        source.contract_code,
        dt.titular_sk,
        du.unit_sk,
        source.emission_date,
        source.base_date,
        source.financing_type,
        source.value_original
    FROM source
    LEFT JOIN dim_titular dt
        ON source.titular_code = dt.titular_code
    LEFT JOIN dim_unit du
        ON source.unit_id = du.unit_id
)

SELECT * FROM final
