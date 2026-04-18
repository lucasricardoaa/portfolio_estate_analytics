SELECT
  estate_typology_code                                 AS tipologia,
  property_type                                        AS tipo_propriedade,
  COUNT(DISTINCT unit_id)                               AS total_unidades,
  ROUND(AVG(private_area), 2)                          AS area_privativa_media,
  ROUND(AVG(usable_area), 2)                           AS area_util_media,
  ROUND(AVG(common_area), 2)                           AS area_comum_media,
  ROUND(AVG(terrain_area), 2)                          AS area_terreno_media
FROM dbt_dev_marts.dim_unit
GROUP BY estate_typology_code, property_type
ORDER BY total_unidades DESC
