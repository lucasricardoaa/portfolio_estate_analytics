WITH source AS (
    SELECT * FROM {{ ref('int_installments_unified') }}
),

dim_contract AS (
    SELECT contract_sk, contract_code
    FROM {{ ref('dim_contract') }}
),

dim_unit AS (
    SELECT unit_sk, unit_id
    FROM {{ ref('dim_unit') }}
),

dim_titular AS (
    SELECT titular_sk, titular_code
    FROM {{ ref('dim_titular') }}
),

dim_date AS (
    SELECT date_sk, date_day
    FROM {{ ref('dim_date') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'source.contract_code',
            'source.installment_id',
            'source.date_reference'
        ]) }}                           AS installment_sk,

        dc.contract_sk,
        du.unit_sk,
        dt.titular_sk,
        dd_ref.date_sk                  AS date_reference_sk,
        dd_mat.date_sk                  AS date_maturity_sk,
        dd_pay.date_sk                  AS date_payment_sk,

        source.date_reference,
        source.date_upload,
        source.payment_status,
        source.installment_id,
        source.installment_type,
        source.date_maturity,
        source.date_payment,
        source.original_value,
        source.present_value,
        source.value_with_addiction,
        source.value_payment,
        source.value_original,
        source.interest_rate,
        source.index,
        source.financing_type,
        source.condition_id

    FROM source
    LEFT JOIN dim_contract dc
        ON  source.contract_code = dc.contract_code
    LEFT JOIN dim_unit du
        ON  source.unit_id = du.unit_id
    LEFT JOIN dim_titular dt
        ON  source.titular_code = dt.titular_code
    LEFT JOIN dim_date dd_ref
        ON  source.date_reference = dd_ref.date_day
    LEFT JOIN dim_date dd_mat
        ON  source.date_maturity = dd_mat.date_day
    LEFT JOIN dim_date dd_pay
        ON  source.date_payment = dd_pay.date_day
)

SELECT * FROM final
