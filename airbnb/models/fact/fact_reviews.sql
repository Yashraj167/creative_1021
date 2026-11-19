{{
  config(
    materialized = 'incremental',
    on_schema_change='fail'
    )
}}
WITH src_reviews AS (
  SELECT * FROM {{ ref('reviews_src') }}
)
SELECT * FROM src_reviews
WHERE review_text is not null