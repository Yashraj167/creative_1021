WITH raw_hosts AS (
    SELECT
        *
    FROM
        AIRBNB.RAW.RAW_HOSTS
)
SELECT
    id as host_id,
    name as host_name ,
    IS_SUPERHOST,
    CREATED_AT ,
    UPDATED_AT
FROM
    raw_hosts