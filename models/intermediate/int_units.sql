WITH source AS (
    SELECT * FROM {{ ref('int_installments_unified') }}
),

ranked AS (
    SELECT
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
        terrain_area,
        ROW_NUMBER() OVER (
            PARTITION BY unit_id
            ORDER BY date_reference DESC, date_upload DESC
        ) AS rn
    FROM source
),

deduped AS (
    SELECT
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
    FROM ranked
    WHERE rn = 1
)

SELECT * FROM deduped
