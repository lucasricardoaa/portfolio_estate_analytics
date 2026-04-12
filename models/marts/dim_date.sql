WITH date_spine AS (
    {{
        dbt_utils.date_spine(
            datepart="day",
            start_date="cast('2022-01-01' as date)",
            end_date="cast('2028-12-31' as date)"
        )
    }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['date_day']) }}        AS date_sk,
        date_day,
        EXTRACT(YEAR FROM date_day)                                 AS year,
        EXTRACT(QUARTER FROM date_day)                             AS quarter,
        EXTRACT(MONTH FROM date_day)                               AS month,
        CASE EXTRACT(MONTH FROM date_day)
            WHEN 1  THEN 'Janeiro'
            WHEN 2  THEN 'Fevereiro'
            WHEN 3  THEN 'Março'
            WHEN 4  THEN 'Abril'
            WHEN 5  THEN 'Maio'
            WHEN 6  THEN 'Junho'
            WHEN 7  THEN 'Julho'
            WHEN 8  THEN 'Agosto'
            WHEN 9  THEN 'Setembro'
            WHEN 10 THEN 'Outubro'
            WHEN 11 THEN 'Novembro'
            WHEN 12 THEN 'Dezembro'
        END                                                         AS month_name,
        EXTRACT(WEEK FROM date_day)                                 AS week_of_year,
        -- Converte DAYOFWEEK do BigQuery (1=Dom, 7=Sáb) para (1=Seg, 7=Dom)
        MOD(EXTRACT(DAYOFWEEK FROM date_day) + 5, 7) + 1          AS day_of_week,
        CASE MOD(EXTRACT(DAYOFWEEK FROM date_day) + 5, 7) + 1
            WHEN 1 THEN 'Segunda-feira'
            WHEN 2 THEN 'Terça-feira'
            WHEN 3 THEN 'Quarta-feira'
            WHEN 4 THEN 'Quinta-feira'
            WHEN 5 THEN 'Sexta-feira'
            WHEN 6 THEN 'Sábado'
            WHEN 7 THEN 'Domingo'
        END                                                         AS day_name,
        MOD(EXTRACT(DAYOFWEEK FROM date_day) + 5, 7) + 1 IN (6, 7) AS is_weekend,
        FORMAT_DATE('%Y-%m', date_day)                              AS year_month
    FROM date_spine
)

SELECT * FROM final
