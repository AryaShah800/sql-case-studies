-- Fresh Segments (Danny Ma's 8 Week SQL Challenge, case study 8) - PostgreSQL
-- Run schema.sql first. Scope: A data exploration and cleansing, B interest analysis, C segment analysis, D index analysis.
-- Open-ended "what do you think" questions are answered in comments next to the evidence query, not computed.
-- Assumptions:
--   * interest_id is text in interest_metrics and integer in interest_map, so it is cast to integer for joins.
--   * Rows with NULL month_year have NULL interest_id too (all but one row, see A3); they cannot be attributed to a month or an interest and are
--     excluded from all analysis (decision for question A3).
--   * "Filtered" dataset = interests present in at least 6 distinct months (the cut-off found in B2).
--   * Average composition = composition / index_value, rounded to 2 decimals, as the brief defines it.
SET search_path = fresh_segments;

-- ===== A. Data exploration and cleansing =====
-- A1. month_year text 'MM-YYYY' -> date at the start of the month (guarded so the script can be re-run)
DO $$
BEGIN
    IF (SELECT data_type FROM information_schema.columns
        WHERE table_schema = 'fresh_segments' AND table_name = 'interest_metrics' AND column_name = 'month_year') <> 'date' THEN
        ALTER TABLE interest_metrics ALTER COLUMN month_year TYPE date USING to_date('01-' || month_year, 'DD-MM-YYYY');
    END IF;
END $$;
SELECT MIN(month_year) AS first_month, MAX(month_year) AS last_month, pg_typeof(MIN(month_year))::text AS type FROM interest_metrics;

-- A2. Records per month_year, NULLs first
SELECT month_year, COUNT(*) AS records FROM interest_metrics GROUP BY month_year ORDER BY month_year NULLS FIRST;

-- A3. What to do with NULL month_year rows? Check what else is missing in them.
SELECT COUNT(*) AS null_month_rows,
       COUNT(*) FILTER (WHERE interest_id IS NULL) AS also_null_interest,
       COUNT(*) FILTER (WHERE composition IS NULL) AS also_null_composition
FROM interest_metrics WHERE month_year IS NULL;
-- Decision: they carry an interest-less, month-less measurement, so they cannot answer any question here: drop them
-- from analysis (done below through "WHERE month_year IS NOT NULL" in a view) but keep them in the raw table for audit.
DROP VIEW IF EXISTS metrics CASCADE;
CREATE VIEW metrics AS
SELECT month_year, interest_id::int AS interest_id, composition, index_value, ranking, percentile_ranking
FROM interest_metrics WHERE month_year IS NOT NULL;

-- A4. interest_ids in metrics but not in map, and the other way round
SELECT (SELECT COUNT(DISTINCT interest_id) FROM metrics m
        WHERE NOT EXISTS (SELECT 1 FROM interest_map i WHERE i.id = m.interest_id)) AS in_metrics_not_map,
       (SELECT COUNT(*) FROM interest_map i
        WHERE NOT EXISTS (SELECT 1 FROM metrics m WHERE m.interest_id = i.id)) AS in_map_not_metrics;

-- A5. Record count per id in interest_map (ids are unique: every id appears once)
SELECT records_per_id, COUNT(*) AS ids FROM (SELECT id, COUNT(*) AS records_per_id FROM interest_map GROUP BY id) t
GROUP BY records_per_id;

-- A6. Join choice: INNER JOIN metrics -> map. Every metric row has a map entry (A4 = 0), and a metric without a name
-- is not usable; map rows with no metrics add nothing to a time series. Check on interest_id = 21246.
SELECT m.*, i.interest_name, i.interest_summary, i.created_at, i.last_modified
FROM metrics m JOIN interest_map i ON i.id = m.interest_id
WHERE m.interest_id = 21246 ORDER BY m.month_year;

-- A7. month_year earlier than the interest's created_at?
-- month_year is the first of the month, created_at is a timestamp inside a month: compare at month level.
SELECT COUNT(*) AS rows_before_created,
       COUNT(*) FILTER (WHERE date_trunc('month', i.created_at) = m.month_year) AS created_same_month
FROM metrics m JOIN interest_map i ON i.id = m.interest_id
WHERE m.month_year < i.created_at;
-- Reading: every such row is dated in the month the interest was created (the metric is monthly, created_at is mid-month),
-- so the metric month starts before the creation instant but the interest already existed in that month: valid.

-- ===== B. Interest analysis =====
-- B1. Interests present in all 14 months
SELECT COUNT(*) AS interests_in_all_months FROM (
    SELECT interest_id FROM metrics GROUP BY interest_id
    HAVING COUNT(DISTINCT month_year) = (SELECT COUNT(DISTINCT month_year) FROM metrics)) t;

-- B2. Cumulative % of interests by total_months, starting at 14 months
WITH per_interest AS (
    SELECT interest_id, COUNT(DISTINCT month_year) AS total_months FROM metrics GROUP BY interest_id
),
dist AS (SELECT total_months, COUNT(*) AS interests FROM per_interest GROUP BY total_months)
SELECT total_months, interests,
       ROUND(100.0 * SUM(interests) OVER (ORDER BY total_months DESC) / SUM(interests) OVER (), 2) AS cumulative_pct
FROM dist ORDER BY total_months DESC;

-- B3. Data points removed if interests with total_months < 6 are dropped (the first month count past 90%, see B2)
WITH per_interest AS (
    SELECT interest_id, COUNT(DISTINCT month_year) AS total_months FROM metrics GROUP BY interest_id
)
SELECT COUNT(*) AS rows_removed, COUNT(DISTINCT m.interest_id) AS interests_removed
FROM metrics m JOIN per_interest p USING (interest_id) WHERE p.total_months < 6;
-- B4. Does removal make sense? Yes for a segment product: an interest seen in only a few months has no stable audience
-- to target or trend to read, and its few rows would skew rankings; interests present in all 14 months give a full time series.
-- The cost is losing genuinely new or seasonal interests, so the removed list should be reviewed, not just discarded.

-- Filtered dataset used below
DROP VIEW IF EXISTS metrics_filtered;
CREATE VIEW metrics_filtered AS
SELECT m.* FROM metrics m
WHERE m.interest_id IN (SELECT interest_id FROM metrics GROUP BY interest_id HAVING COUNT(DISTINCT month_year) >= 6);

-- B5. Unique interests per month after filtering
SELECT month_year, COUNT(DISTINCT interest_id) AS interests FROM metrics_filtered GROUP BY month_year ORDER BY month_year;

-- ===== C. Segment analysis =====
-- C1. Top 10 and bottom 10 interests by their maximum composition (with the month it occurred)
WITH best AS (
    SELECT DISTINCT ON (interest_id) interest_id, month_year, composition
    FROM metrics_filtered ORDER BY interest_id, composition DESC, month_year
),
ranked AS (
    SELECT i.interest_name, b.month_year, b.composition,
           ROW_NUMBER() OVER (ORDER BY b.composition DESC, i.interest_name) AS top_rank,
           ROW_NUMBER() OVER (ORDER BY b.composition ASC,  i.interest_name) AS bottom_rank
    FROM best b JOIN interest_map i ON i.id = b.interest_id
)
SELECT CASE WHEN top_rank <= 10 THEN 'top' ELSE 'bottom' END AS side,
       interest_name, month_year, composition
FROM ranked WHERE top_rank <= 10 OR bottom_rank <= 10
ORDER BY side DESC, composition DESC, interest_name;

-- C2. 5 interests with the lowest average ranking (rank 1 = best, so lowest number)
SELECT i.interest_name, ROUND(AVG(m.ranking), 2) AS avg_ranking
FROM metrics_filtered m JOIN interest_map i ON i.id = m.interest_id
GROUP BY i.interest_name ORDER BY avg_ranking, i.interest_name LIMIT 5;

-- C3. 5 interests with the largest standard deviation of percentile_ranking
SELECT i.interest_name, ROUND(STDDEV(m.percentile_ranking)::numeric, 2) AS sd_percentile_ranking
FROM metrics_filtered m JOIN interest_map i ON i.id = m.interest_id
GROUP BY i.interest_name ORDER BY sd_percentile_ranking DESC, i.interest_name LIMIT 5;

-- C4. For those 5: min and max percentile_ranking with their months
WITH volatile AS (
    SELECT interest_id FROM metrics_filtered GROUP BY interest_id
    ORDER BY STDDEV(percentile_ranking) DESC, interest_id LIMIT 5
),
ext AS (
    SELECT m.interest_id, m.month_year, m.percentile_ranking,
           ROW_NUMBER() OVER (PARTITION BY m.interest_id ORDER BY m.percentile_ranking DESC, m.month_year) AS hi,
           ROW_NUMBER() OVER (PARTITION BY m.interest_id ORDER BY m.percentile_ranking ASC,  m.month_year) AS lo
    FROM metrics_filtered m JOIN volatile v USING (interest_id)
)
SELECT i.interest_name,
       MAX(e.percentile_ranking) FILTER (WHERE hi = 1) AS max_pct_rank, MAX(e.month_year) FILTER (WHERE hi = 1) AS max_month,
       MAX(e.percentile_ranking) FILTER (WHERE lo = 1) AS min_pct_rank, MAX(e.month_year) FILTER (WHERE lo = 1) AS min_month
FROM ext e JOIN interest_map i ON i.id = e.interest_id
WHERE hi = 1 OR lo = 1 GROUP BY i.interest_name ORDER BY MAX(e.percentile_ranking) FILTER (WHERE hi = 1) - MAX(e.percentile_ranking) FILTER (WHERE lo = 1) DESC, i.interest_name;
-- C5. Reading (open-ended): four of the five volatile interests peak in the first months (mostly July 2018 or
-- March-November 2018) and sink to a single-digit percentile by mid 2019, so they behave as short-lived or news-driven
-- topics rather than stable audience traits. Target the consistently high-composition,
-- low-average-rank interests (C1, C2) with always-on campaigns and avoid building long-term offers on the volatile ones.

-- ===== D. Index analysis =====
-- avg_composition = composition / index_value, rounded to 2 dp. Computed on the unfiltered (non-null month) data.
DROP VIEW IF EXISTS avg_comp;
CREATE VIEW avg_comp AS
SELECT m.month_year, m.interest_id, i.interest_name, ROUND((m.composition / m.index_value)::numeric, 2) AS avg_composition
FROM metrics m JOIN interest_map i ON i.id = m.interest_id;

-- D1. Top 10 interests by average composition for each month
SELECT month_year, rnk, interest_name, avg_composition FROM (
    SELECT a.*, ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY avg_composition DESC, interest_name) AS rnk
    FROM avg_comp a) t
WHERE rnk <= 10 ORDER BY month_year, rnk;

-- D2. Of all those monthly top-10 entries, which interest appears most often?
WITH top10 AS (
    SELECT * FROM (SELECT a.*, ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY avg_composition DESC, interest_name) AS rnk
                   FROM avg_comp a) t WHERE rnk <= 10
)
SELECT interest_name, COUNT(*) AS months_in_top10 FROM top10
GROUP BY interest_name ORDER BY months_in_top10 DESC, interest_name LIMIT 5;

-- D3. Average of the top-10 average compositions, per month
WITH top10 AS (
    SELECT * FROM (SELECT a.*, ROW_NUMBER() OVER (PARTITION BY month_year ORDER BY avg_composition DESC, interest_name) AS rnk
                   FROM avg_comp a) t WHERE rnk <= 10
)
SELECT month_year, ROUND(AVG(avg_composition), 2) AS avg_of_top10 FROM top10 GROUP BY month_year ORDER BY month_year;

-- D4. Highest average composition per month with a 3-month moving average and the two previous months' leaders,
-- September 2018 to August 2019 (July and August 2018 are pulled in only as look-back context).
WITH monthly_max AS (
    SELECT DISTINCT ON (month_year) month_year, interest_name, avg_composition AS max_index_composition
    FROM avg_comp ORDER BY month_year, avg_composition DESC, interest_name
),
w AS (
    SELECT month_year, interest_name, max_index_composition,
           ROUND(AVG(max_index_composition) OVER (ORDER BY month_year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS moving_avg_3m,
           LAG(interest_name, 1) OVER (ORDER BY month_year) || ': ' || LAG(max_index_composition, 1) OVER (ORDER BY month_year) AS one_month_ago,
           LAG(interest_name, 2) OVER (ORDER BY month_year) || ': ' || LAG(max_index_composition, 2) OVER (ORDER BY month_year) AS two_months_ago
    FROM monthly_max
)
SELECT month_year, interest_name, max_index_composition, moving_avg_3m, one_month_ago, two_months_ago
FROM w WHERE month_year >= DATE '2018-09-01' ORDER BY month_year;
-- D5. Reading (open-ended): the monthly maximum falls from 9.14 (Oct 2018) to 2.73 (Aug 2019) and the leader changes
-- from Work Comes First Travelers to a different interest almost every month after Feb 2019. Falling maxima suggest the client's audience engages less intensely with any one
-- interest over time (or the index is normalised against growing averages), which is worth raising with the client rather
-- than a proof that the business model is broken.
