WITH payments AS (
    SELECT * FROM {{ ref('stg_payments') }}
),

receivables AS (
    SELECT * FROM {{ ref('stg_receivables') }}
),

unified AS (
    SELECT * FROM payments
    UNION ALL
    SELECT * FROM receivables
)

SELECT * FROM unified
