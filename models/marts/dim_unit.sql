WITH source AS (
    SELECT * FROM {{ ref('int_units') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['unit_id']) }} AS unit_sk,
        unit_id,
        unit_name,
        estate_code,
        estate_name,
        estate_address,
        estate_schedule_code,
        estate_typology_code,
        property_type,
        floor,
        private_area,
        common_area,
        usable_area,
        terrain_area
    FROM source
)

SELECT * FROM final
