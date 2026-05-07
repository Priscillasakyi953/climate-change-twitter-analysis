--creating table 
CREATE TABLE raw_tweets (
    created_at          TEXT,
    id                  BIGINT,
    lng                 TEXT,
    lat                 TEXT,
    topic               TEXT,
    sentiment           TEXT,
    stance              TEXT,
    gender              TEXT,
    temperature_avg     TEXT,
    aggressiveness      TEXT
);

--changing column datatype to the right data type
ALTER TABLE raw_tweets
ALTER COLUMN lng TYPE NUMERIC(10,7) 
USING NULLIF(lng, '')::NUMERIC;

ALTER TABLE raw_tweets 
ALTER COLUMN lat TYPE NUMERIC(10,7) 
USING NULLIF(lat, '')::NUMERIC;

ALTER TABLE raw_tweets 
ALTER COLUMN sentiment TYPE NUMERIC(10,9) 
USING NULLIF(sentiment, '')::NUMERIC;

ALTER TABLE raw_tweets 
ALTER COLUMN temperature_avg TYPE NUMERIC(10,7) 
USING NULLIF(temperature_avg, '')::NUMERIC;

-- Change created_at to TIMESTAMP handling both formats
ALTER TABLE raw_tweets 
ALTER COLUMN created_at TYPE TIMESTAMP 
USING 
    CASE 
        WHEN created_at LIKE '%+%' THEN
            -- Format: 2018-02-13 10:13:48+00:00
            TO_TIMESTAMP(created_at, 'YYYY-MM-DD HH24:MI:SS+00:00')
        WHEN created_at LIKE '__/__/_____%' THEN
            -- Format: 13/02/2018 10:13:48
            TO_TIMESTAMP(created_at, 'DD/MM/YYYY HH24:MI:SS')
        ELSE
            NULL
    END;


-- DATA CLEANING
-- Count nulls in each column
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE created_at IS NULL) AS null_created_at,
    COUNT(*) FILTER (WHERE lat IS NULL)        AS null_lat,
    COUNT(*) FILTER (WHERE lng IS NULL)        AS null_lng,
    COUNT(*) FILTER (WHERE topic IS NULL)      AS null_topic,
    COUNT(*) FILTER (WHERE sentiment IS NULL)  AS null_sentiment,
    COUNT(*) FILTER (WHERE stance IS NULL)     AS null_stance,
    COUNT(*) FILTER (WHERE gender IS NULL)     AS null_gender,
    COUNT(*) FILTER (WHERE temperature_avg IS NULL) AS null_temp,
    COUNT(*) FILTER (WHERE aggressiveness IS NULL)  AS null_aggr
FROM raw_tweets;

--Duplicate tweet IDs
SELECT COUNT(*) - COUNT(DISTINCT id) AS duplicate_ids
FROM raw_tweets;
--No duplicate tweet IDs were found after validation

-- Distinct values in categorical columns
SELECT DISTINCT stance FROM raw_tweets;
SELECT DISTINCT gender FROM raw_tweets;
SELECT DISTINCT aggressiveness FROM raw_tweets;

--Fix undefined gender
UPDATE raw_tweets
SET gender = 'unknown'
WHERE TRIM(LOWER(gender)) = 'undefined';

-- Sentiment out of range (-1 to 1)
SELECT COUNT(*) AS out_of_range_sentiment
FROM raw_tweets
WHERE sentiment < -1 OR sentiment > 1;

-- Date range
SELECT 
    MIN(created_at) AS earliest_tweet,
    MAX(created_at) AS latest_tweet
FROM raw_tweets;

--standardising text column
UPDATE raw_tweets
SET stance = TRIM(LOWER(stance));

UPDATE raw_tweets
SET aggressiveness = TRIM(LOWER(aggressiveness));

UPDATE raw_tweets
SET gender = TRIM(LOWER(gender));

UPDATE raw_tweets
SET topic = TRIM(topic);

--creating year and month column
ALTER TABLE raw_tweets
ADD COLUMN year INT,
ADD COLUMN month INT;

UPDATE raw_tweets
SET 
    year = EXTRACT(YEAR FROM created_at),
    month = EXTRACT(MONTH FROM created_at);


--creating new cleaned table with no null
CREATE TABLE tweets_clean AS
SELECT
    id,
    created_at,
    EXTRACT(YEAR FROM created_at) AS year,
    EXTRACT(MONTH FROM created_at) AS month,
    lat,
    lng,
    topic,
    sentiment,
    stance,
    gender,
    temperature_avg,
    aggressiveness,
    CASE 
        WHEN lat IS NOT NULL AND lng IS NOT NULL THEN TRUE 
        ELSE FALSE 
    END AS has_location,
    CASE 
        WHEN temperature_avg IS NOT NULL THEN TRUE 
        ELSE FALSE 
    END AS has_temperature
FROM raw_tweets
WHERE created_at IS NOT NULL;	

--CREATING VIEWS
--Sentiment Trend
CREATE VIEW vw_sentiment_trend AS
SELECT
    year,
    COUNT(*) AS total_tweets,
    ROUND(AVG(sentiment), 4) AS avg_sentiment
FROM tweets_clean
GROUP BY year
ORDER BY year;

--Stance Trend
CREATE VIEW vw_stance_trend AS
SELECT
    year,
    stance,
    COUNT(*) AS total_tweets
FROM tweets_clean
GROUP BY year, stance
ORDER BY year;

--Aggressiveness by Topic
CREATE VIEW vw_aggressiveness_by_topic AS
SELECT
    topic,
    COUNT(*) AS total_tweets,
    COUNT(*) FILTER (WHERE aggressiveness = 'aggressive') AS aggressive_tweets,
    ROUND(
        COUNT(*) FILTER (WHERE aggressiveness = 'aggressive')::NUMERIC 
        / COUNT(*) * 100, 
    2) AS aggressive_pct,
    ROUND(AVG(sentiment), 4) AS avg_sentiment
FROM tweets_clean
GROUP BY topic
ORDER BY aggressive_pct DESC;

--Temperature by Sentiment
CREATE VIEW vw_temperature_sentiment AS
SELECT
    ROUND(temperature_avg, 1) AS temp_bucket,
    COUNT(*) AS total_tweets,
    ROUND(AVG(sentiment), 4) AS avg_sentiment
FROM tweets_clean
WHERE temperature_avg IS NOT NULL
GROUP BY temp_bucket
ORDER BY temp_bucket;

--Aggression by Location#
CREATE VIEW vw_geo_aggression AS
SELECT
    ROUND(lat, 1) AS lat_group,
    ROUND(lng, 1) AS lng_group,
    COUNT(*) AS total_tweets,
    COUNT(*) FILTER (WHERE aggressiveness = 'aggressive') AS aggressive_tweets,
    ROUND(AVG(sentiment), 4) AS avg_sentiment
FROM tweets_clean
WHERE lat IS NOT NULL AND lng IS NOT NULL
GROUP BY lat_group, lng_group;

-- Gender Analysis
CREATE OR REPLACE VIEW vw_gender_analysis AS
SELECT
    gender,
    stance,
    COUNT(*)                                                    AS total_tweets,
    COUNT(*) FILTER (WHERE aggressiveness = 'aggressive')      AS aggressive_tweets,
    ROUND(AVG(sentiment), 4)                                   AS avg_sentiment
FROM tweets_clean
GROUP BY gender, stance
ORDER BY total_tweets DESC;

--Topic by Stance 
CREATE OR REPLACE VIEW vw_topic_stance AS
SELECT
    topic,
    stance,
    COUNT(*)                                                    AS total_tweets,
    ROUND(AVG(sentiment), 4)                                   AS avg_sentiment,
    COUNT(*) FILTER (WHERE aggressiveness = 'aggressive')      AS aggressive_tweets
FROM tweets_clean
GROUP BY topic, stance
ORDER BY total_tweets DESC;

--Monthly Tweet Volume
CREATE OR REPLACE VIEW vw_monthly_volume AS
SELECT
    year,
    month,
    stance,
    COUNT(*)                                                    AS total_tweets,
    ROUND(AVG(sentiment), 4)                                   AS avg_sentiment,
    COUNT(*) FILTER (WHERE aggressiveness = 'aggressive')      AS aggressive_tweets
FROM tweets_clean
GROUP BY year, month, stance
ORDER BY year, month;
