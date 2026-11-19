-- 1021 Creative POC: API ingestion stored procedures (Python)
USE ROLE POC_1021_ADMIN;

-- ---------------------------------------------------------------------------
-- Tubular: run every enabled PULL_CONFIG row, land raw responses in bronze.
-- Trends endpoints allow 6 req/min, so calls are spaced SLEEP_SECONDS apart.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE POC_1021_BRONZE.TUBULAR.SP_INGEST_TUBULAR()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (POC_1021_TUBULAR_EAI)
SECRETS = ('api_key' = POC_1021_BRONZE.TUBULAR.TUBULAR_API_KEY)
AS
$$
import json, time, uuid
import requests
import _snowflake

BASE_URL = "https://tubularlabs.com/api/v4/"
SLEEP_SECONDS = 11

def land(session, run_id, endpoint, scope, body, status, payload, headers):
    session.sql(
        """INSERT INTO POC_1021_BRONZE.TUBULAR.RAW_API_RESPONSES
           (RUN_ID, ENDPOINT, SCOPE, REQUEST, HTTP_STATUS, RESPONSE, RATE_HEADERS)
           SELECT ?, ?, ?, PARSE_JSON(?), TRY_TO_NUMBER(?), PARSE_JSON(?), PARSE_JSON(?)""",
        params=[run_id, endpoint, scope, json.dumps(body), str(status or ""),
                json.dumps(payload), json.dumps(headers)],
    ).collect()

def call(session, run_id, endpoint, scope, body):
    api_key = _snowflake.get_generic_secret_string("api_key")
    try:
        r = requests.post(BASE_URL + endpoint, json=body, timeout=120,
                          headers={"Api-Key": api_key, "Content-Type": "application/json"})
        try:
            payload = r.json()
        except ValueError:
            payload = {"raw_text": r.text[:10000]}
        headers = {k.lower(): v for k, v in r.headers.items() if k.lower().startswith("tubular-")}
        land(session, run_id, endpoint, scope, body, r.status_code, payload, headers)
        return {"scope": scope, "endpoint": endpoint, "status": r.status_code,
                "quota_units": headers.get("tubular-quota-units-consumed")}
    except Exception as e:
        land(session, run_id, endpoint, scope, body, None, {"error": str(e)}, {})
        return {"scope": scope, "endpoint": endpoint, "status": None, "error": str(e)}

def run(session):
    run_id = str(uuid.uuid4())
    rows = session.sql(
        "SELECT SCOPE, ENDPOINT, BODY FROM POC_1021_BRONZE.TUBULAR.PULL_CONFIG WHERE ENABLED"
    ).collect()
    results = []
    for i, row in enumerate(rows):
        if i > 0:
            time.sleep(SLEEP_SECONDS)
        results.append(call(session, run_id, row["ENDPOINT"], row["SCOPE"], json.loads(row["BODY"])))
    return {"run_id": run_id, "calls": results}
$$;

-- ---------------------------------------------------------------------------
-- Tubular ad hoc search: analysts pass any video.search body and a label.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE POC_1021_BRONZE.TUBULAR.SP_TUBULAR_SEARCH(BODY VARIANT, LABEL STRING)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (POC_1021_TUBULAR_EAI)
SECRETS = ('api_key' = POC_1021_BRONZE.TUBULAR.TUBULAR_API_KEY)
AS
$$
import json, uuid
import requests
import _snowflake

def run(session, body, label):
    run_id = str(uuid.uuid4())
    body = json.loads(body) if isinstance(body, str) else body
    r = requests.post("https://tubularlabs.com/api/v4/video.search", json=body, timeout=120,
                      headers={"Api-Key": _snowflake.get_generic_secret_string("api_key"),
                               "Content-Type": "application/json"})
    try:
        payload = r.json()
    except ValueError:
        payload = {"raw_text": r.text[:10000]}
    headers = {k.lower(): v for k, v in r.headers.items() if k.lower().startswith("tubular-")}
    session.sql(
        """INSERT INTO POC_1021_BRONZE.TUBULAR.RAW_API_RESPONSES
           (RUN_ID, ENDPOINT, SCOPE, REQUEST, HTTP_STATUS, RESPONSE, RATE_HEADERS)
           SELECT ?, 'video.search', ?, PARSE_JSON(?), ?, PARSE_JSON(?), PARSE_JSON(?)""",
        params=[run_id, label, json.dumps(body), r.status_code, json.dumps(payload), json.dumps(headers)],
    ).collect()
    return {"run_id": run_id, "status": r.status_code,
            "error": payload.get("error") if isinstance(payload, dict) else None}
$$;

-- ---------------------------------------------------------------------------
-- Meltwater: sync saved searches, then run each enabled analysis for each
-- enabled search over [START_DATE, END_DATE). Defaults to the last 2 full UTC days:
-- day-bucketed analyses re-pull the prior day (picks up late-indexed mentions at no
-- extra calls); non-bucketed analyses (top_topics) always use only the last full day.
-- Stops early if the daily rate limit (50/day) gets close.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE POC_1021_BRONZE.MELTWATER.SP_INGEST_MELTWATER(
  START_DATE DATE DEFAULT NULL,
  END_DATE   DATE DEFAULT NULL)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (POC_1021_MELTWATER_EAI)
SECRETS = ('api_key' = POC_1021_BRONZE.MELTWATER.MELTWATER_API_KEY)
AS
$$
import json, uuid, datetime
import requests
import _snowflake

BASE_URL = "https://api.meltwater.com/v3/"
MIN_DAILY_REMAINING = 5
MAX_WINDOW_DAYS = 30

def land(session, run_id, endpoint, scope, search_id, req, status, payload, headers):
    session.sql(
        """INSERT INTO POC_1021_BRONZE.MELTWATER.RAW_API_RESPONSES
           (RUN_ID, ENDPOINT, SCOPE, SEARCH_ID, REQUEST, HTTP_STATUS, RESPONSE, RATE_HEADERS)
           SELECT ?, ?, ?, TRY_TO_NUMBER(?), PARSE_JSON(?), TRY_TO_NUMBER(?), PARSE_JSON(?), PARSE_JSON(?)""",
        params=[run_id, endpoint, scope, str(search_id or ""), json.dumps(req), str(status or ""),
                json.dumps(payload), json.dumps(headers)],
    ).collect()

def request(method, path, api_key, params=None, body=None):
    r = requests.request(method, BASE_URL + path, params=params, json=body, timeout=120,
                         headers={"apikey": api_key, "Accept": "application/json",
                                  "Content-Type": "application/json"})
    try:
        payload = r.json()
    except ValueError:
        payload = {"raw_text": r.text[:10000]}
    headers = {k.lower(): v for k, v in r.headers.items() if k.lower().startswith("ratelimit")}
    remaining = headers.get("ratelimit-day-remaining")
    return r.status_code, payload, headers, (int(remaining) if remaining is not None else None)

def sync_searches(session, run_id, api_key):
    status, payload, headers, remaining = request("GET", "searches", api_key)
    land(session, run_id, "searches", "searches", None, {}, status, payload, headers)
    if status != 200:
        return status, remaining
    session.sql(
        """MERGE INTO POC_1021_BRONZE.MELTWATER.SEARCH_CONFIG t
           USING (SELECT f.value:id::NUMBER AS SEARCH_ID, f.value:name::STRING AS SEARCH_NAME,
                         f.value:updated::TIMESTAMP_TZ AS UPDATED
                  FROM TABLE(FLATTEN(INPUT => PARSE_JSON(?):searches)) f) s
           ON t.SEARCH_ID = s.SEARCH_ID
           WHEN MATCHED THEN UPDATE SET SEARCH_NAME = s.SEARCH_NAME, UPDATED = s.UPDATED,
                ACTIVE = TRUE, LAST_SYNCED_AT = CURRENT_TIMESTAMP()
           WHEN NOT MATCHED THEN INSERT (SEARCH_ID, SEARCH_NAME, UPDATED, ENABLED, ACTIVE)
                VALUES (s.SEARCH_ID, s.SEARCH_NAME, s.UPDATED, FALSE, TRUE)""",
        params=[json.dumps(payload)],
    ).collect()
    ids = [int(s["id"]) for s in payload.get("searches", [])]
    if ids:
        session.sql(
            "UPDATE POC_1021_BRONZE.MELTWATER.SEARCH_CONFIG SET ACTIVE = FALSE "
            "WHERE NOT ARRAY_CONTAINS(SEARCH_ID::VARIANT, PARSE_JSON(?))",
            params=[json.dumps(ids)],
        ).collect()
    return status, remaining

def run(session, start_date, end_date):
    # Meltwater day buckets are UTC; the session runs in Pacific time
    today = datetime.datetime.utcnow().date()
    start_date = start_date or (today - datetime.timedelta(days=2))
    end_date = end_date or today
    if (end_date - start_date).days > MAX_WINDOW_DAYS or end_date <= start_date:
        return {"error": f"window must be 1-{MAX_WINDOW_DAYS} days, got {start_date} to {end_date}"}

    api_key = _snowflake.get_generic_secret_string("api_key")
    run_id = str(uuid.uuid4())
    start_s, end_s = f"{start_date}T00:00:00", f"{end_date}T00:00:00"
    last_day_s = f"{end_date - datetime.timedelta(days=1)}T00:00:00"

    sync_status, remaining = sync_searches(session, run_id, api_key)
    searches = session.sql(
        "SELECT SEARCH_ID, SEARCH_NAME FROM POC_1021_BRONZE.MELTWATER.SEARCH_CONFIG "
        "WHERE ENABLED AND ACTIVE ORDER BY SEARCH_ID").collect()
    analyses = session.sql(
        "SELECT ANALYSIS_NAME, METHOD, PATH, BODY FROM POC_1021_BRONZE.MELTWATER.ANALYSIS_CONFIG "
        "WHERE ENABLED ORDER BY ANALYSIS_NAME").collect()

    results, stopped = [], None
    for s in searches:
        for a in analyses:
            if remaining is not None and remaining < MIN_DAILY_REMAINING:
                stopped = f"daily rate limit guard hit (remaining={remaining})"
                break
            sid, name = int(s["SEARCH_ID"]), a["ANALYSIS_NAME"]
            body_cfg = json.loads(a["BODY"]) if a["BODY"] else {}
            win_start = start_s if body_cfg.get("type") == "date_histogram" else last_day_s
            if a["METHOD"] == "custom":
                req = {"start": win_start, "end": end_s, "tz": "UTC", "analysis": body_cfg}
                method, path, params, body = "POST", f"analytics/{sid}/custom", None, req
            else:
                req = {"start": win_start, "end": end_s, "tz": "UTC"}
                method, path, params, body = "GET", f"analytics/{sid}/{a['PATH']}", req, None
            try:
                status, payload, headers, rem = request(method, path, api_key, params, body)
                remaining = rem if rem is not None else remaining
                land(session, run_id, path, name, sid, req, status, payload, headers)
                results.append({"search_id": sid, "analysis": name, "status": status})
            except Exception as e:
                land(session, run_id, path, name, sid, req, None, {"error": str(e)}, {})
                results.append({"search_id": sid, "analysis": name, "status": None, "error": str(e)})
        if stopped:
            break

    return {"run_id": run_id, "window": [start_s, end_s], "search_sync_status": sync_status,
            "calls": results, "daily_remaining": remaining, "stopped": stopped}
$$;
