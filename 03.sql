-- 1021 Creative POC: bronze landing tables + pull config
USE ROLE POC_1021_ADMIN;

-- Raw API responses (one row per API call, full payload kept as VARIANT)
CREATE TABLE IF NOT EXISTS POC_1021_BRONZE.TUBULAR.RAW_API_RESPONSES (
  RUN_ID        STRING,
  INGESTED_AT   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
  ENDPOINT      STRING,
  SCOPE         STRING,
  REQUEST       VARIANT,
  HTTP_STATUS   NUMBER,
  RESPONSE      VARIANT,
  RATE_HEADERS  VARIANT
);

CREATE TABLE IF NOT EXISTS POC_1021_BRONZE.MELTWATER.RAW_API_RESPONSES (
  RUN_ID        STRING,
  INGESTED_AT   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
  ENDPOINT      STRING,
  SCOPE         STRING,          -- analysis_name, or 'searches' for the list sync
  SEARCH_ID     NUMBER,
  REQUEST       VARIANT,
  HTTP_STATUS   NUMBER,
  RESPONSE      VARIANT,
  RATE_HEADERS  VARIANT
);

-- Tubular: one row per scheduled request
CREATE TABLE IF NOT EXISTS POC_1021_BRONZE.TUBULAR.PULL_CONFIG (
  SCOPE     STRING,
  ENDPOINT  STRING,
  BODY      VARIANT,
  ENABLED   BOOLEAN DEFAULT TRUE
);

MERGE INTO POC_1021_BRONZE.TUBULAR.PULL_CONFIG t
USING (
  SELECT 'global' AS SCOPE, 'video.trends_top' AS ENDPOINT, PARSE_JSON('{
    "include": {"upload_date": {"min": "last_90"}},
    "aggregation": {"metric": "views", "time_bucket": "daily",
                    "gain_date_range": {"min": "last_7"},
                    "segmentation": [{"field": "platform", "depth": 10}]},
    "top": 10,
    "fields": {"snippet": true, "publisher": true, "performance": true, "taxonomy": true}
  }') AS BODY
  UNION ALL
  -- trends_summary rejects queries over 100M videos; views >= 100k keeps it under the cap
  SELECT 'global', 'video.trends_summary', PARSE_JSON('{
    "include": {"upload_date": {"min": "last_90"}, "views": {"min": 100000}},
    "aggregation": {"metric": {"views": true, "engagements": true, "uploads": true},
                    "time_bucket": "daily",
                    "gain_date_range": {"min": "last_7"},
                    "segmentation": [{"field": "platform", "depth": 10}]}
  }')
) s
ON t.SCOPE = s.SCOPE AND t.ENDPOINT = s.ENDPOINT
WHEN NOT MATCHED THEN INSERT (SCOPE, ENDPOINT, BODY, ENABLED) VALUES (s.SCOPE, s.ENDPOINT, s.BODY, TRUE);

-- Meltwater: saved searches (synced from GET /v3/searches by the ingest proc)
CREATE TABLE IF NOT EXISTS POC_1021_BRONZE.MELTWATER.SEARCH_CONFIG (
  SEARCH_ID       NUMBER,
  SEARCH_NAME     STRING,
  UPDATED         TIMESTAMP_TZ,
  ENABLED         BOOLEAN DEFAULT FALSE,
  ACTIVE          BOOLEAN DEFAULT TRUE,
  FIRST_SEEN_AT   TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP(),
  LAST_SYNCED_AT  TIMESTAMP_TZ DEFAULT CURRENT_TIMESTAMP()
);

-- Seed the 4 POC searches as enabled; everything else syncs in disabled
MERGE INTO POC_1021_BRONZE.MELTWATER.SEARCH_CONFIG t
USING (
  SELECT * FROM VALUES
    (29212903, 'Gaming Industry'),
    (29212910, 'Fashion Industry'),
    (29212930, 'Anime & Manga (Topic)'),
    (29212935, 'Sports (Topic)') AS v(SEARCH_ID, SEARCH_NAME)
) s
ON t.SEARCH_ID = s.SEARCH_ID
WHEN NOT MATCHED THEN INSERT (SEARCH_ID, SEARCH_NAME, ENABLED) VALUES (s.SEARCH_ID, s.SEARCH_NAME, TRUE);

-- Meltwater: analyses run per enabled search
CREATE TABLE IF NOT EXISTS POC_1021_BRONZE.MELTWATER.ANALYSIS_CONFIG (
  ANALYSIS_NAME  STRING,
  METHOD         STRING,   -- 'custom' (POST /analytics/{id}/custom) or 'predefined' (GET /analytics/{id}/<path>)
  PATH           STRING,
  BODY           VARIANT,  -- the "analysis" object for custom requests
  ENABLED        BOOLEAN DEFAULT TRUE
);

MERGE INTO POC_1021_BRONZE.MELTWATER.ANALYSIS_CONFIG t
USING (
  SELECT 'daily_sentiment' AS ANALYSIS_NAME, 'custom' AS METHOD, 'custom' AS PATH, PARSE_JSON('{
    "type": "date_histogram", "granularity": "day",
    "analysis": {"type": "top_terms", "dimension": "sentiment", "limit": 5}}') AS BODY
  UNION ALL SELECT 'daily_language', 'custom', 'custom', PARSE_JSON('{
    "type": "date_histogram", "granularity": "day",
    "analysis": {"type": "top_terms", "dimension": "language", "limit": 20}}')
  UNION ALL SELECT 'daily_keyphrases', 'custom', 'custom', PARSE_JSON('{
    "type": "date_histogram", "granularity": "day",
    "analysis": {"type": "top_terms", "dimension": "keyphrase", "limit": 25}}')
  UNION ALL SELECT 'daily_engagement', 'custom', 'custom', PARSE_JSON('{
    "type": "date_histogram", "granularity": "day",
    "analysis": {"type": "measure_statistics", "measures": ["engagement", "reach", "views"]}}')
  UNION ALL SELECT 'top_topics', 'predefined', 'top_topics', NULL
) s
ON t.ANALYSIS_NAME = s.ANALYSIS_NAME
WHEN NOT MATCHED THEN INSERT (ANALYSIS_NAME, METHOD, PATH, BODY, ENABLED) VALUES (s.ANALYSIS_NAME, s.METHOD, s.PATH, s.BODY, TRUE);
