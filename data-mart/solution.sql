-- Data Mart (Danny Ma's 8 Week SQL Challenge, case study 5) - PostgreSQL
-- Run schema.sql first. Scope: 1 data cleansing, 2 data exploration, 3 before & after analysis, 4 bonus.
-- Assumptions:
--   * week_date is stored as text 'D/M/YY'; every year is 20YY (2018-2020).
--   * week_number = (day_of_year - 1) / 7 + 1, so 1-7 Jan is week 1, as the brief defines it.
--   * The text 'null' in segment becomes 'unknown' (also in age_band and demographic).
--   * Percentages are shares of SUM(sales); ratios are computed from totals, never as an average of averages.
--   * "4 weeks before/after 2020-06-15" = the 4 weekly rows before it and the 4 from it onward (28 days each side);
--     "12 weeks" = 84 days each side. 2020-06-15 itself starts the "after" period.
SET search_path = data_mart;

-- ===== 1. Data cleansing =====
DROP TABLE IF EXISTS clean_weekly_sales;
CREATE TABLE clean_weekly_sales AS
SELECT
    d.week_date,
    ((EXTRACT(doy FROM d.week_date)::int - 1) / 7) + 1             AS week_number,
    EXTRACT(month FROM d.week_date)::int                          AS month_number,
    EXTRACT(year FROM d.week_date)::int                           AS calendar_year,
    w.region,
    w.platform,
    COALESCE(NULLIF(w.segment, 'null'), 'unknown')                AS segment,
    CASE RIGHT(w.segment, 1)
        WHEN '1' THEN 'Young Adults'
        WHEN '2' THEN 'Middle Aged'
        WHEN '3' THEN 'Retirees'
        WHEN '4' THEN 'Retirees'
        ELSE 'unknown' END                                         AS age_band,
    CASE LEFT(w.segment, 1)
        WHEN 'C' THEN 'Couples'
        WHEN 'F' THEN 'Families'
        ELSE 'unknown' END                                         AS demographic,
    w.customer_type,
    w.transactions,
    w.sales,
    ROUND(w.sales::numeric / w.transactions, 2)                   AS avg_transaction
FROM weekly_sales w
CROSS JOIN LATERAL (SELECT to_date(w.week_date, 'DD/MM/YY') AS week_date) d;

-- 1-check. Row count preserved and nothing left NULL
SELECT COUNT(*) AS rows_clean, (SELECT COUNT(*) FROM weekly_sales) AS rows_raw,
       COUNT(*) FILTER (WHERE week_date IS NULL OR age_band IS NULL OR demographic IS NULL) AS null_rows
FROM clean_weekly_sales;

-- ===== 2. Data exploration =====
-- 2.1 Day of week used by week_date
SELECT DISTINCT TO_CHAR(week_date, 'FMDay') AS weekday FROM clean_weekly_sales;

-- 2.2 Week numbers missing from the dataset: 1-52 minus those present, collapsed into ranges (gaps and islands)
WITH missing AS (
    SELECT m FROM generate_series(1, 52) AS m
    WHERE NOT EXISTS (SELECT 1 FROM clean_weekly_sales c WHERE c.week_number = m)
)
SELECT MIN(m) AS from_week, MAX(m) AS to_week, COUNT(*) AS weeks
FROM (SELECT m, m - ROW_NUMBER() OVER (ORDER BY m) AS grp FROM missing) g
GROUP BY grp ORDER BY from_week;

-- 2.3 Total transactions per year
SELECT calendar_year, SUM(transactions) AS total_transactions
FROM clean_weekly_sales GROUP BY calendar_year ORDER BY calendar_year;

-- 2.4 Total sales per region per month
SELECT region, month_number, SUM(sales) AS total_sales
FROM clean_weekly_sales GROUP BY region, month_number ORDER BY region, month_number;

-- 2.5 Total transactions per platform
SELECT platform, SUM(transactions) AS total_transactions
FROM clean_weekly_sales GROUP BY platform ORDER BY platform;

-- 2.6 Retail vs Shopify share of sales per month (by year too, since months repeat across years)
SELECT calendar_year, month_number,
       ROUND(100.0 * SUM(sales) FILTER (WHERE platform = 'Retail')  / SUM(sales), 2) AS retail_pct,
       ROUND(100.0 * SUM(sales) FILTER (WHERE platform = 'Shopify') / SUM(sales), 2) AS shopify_pct
FROM clean_weekly_sales GROUP BY calendar_year, month_number ORDER BY calendar_year, month_number;

-- 2.7 Sales share by demographic per year
SELECT calendar_year, demographic,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (PARTITION BY calendar_year), 2) AS pct_of_year
FROM clean_weekly_sales GROUP BY calendar_year, demographic ORDER BY calendar_year, demographic;

-- 2.8 age_band / demographic contribution to Retail sales
SELECT age_band, demographic, SUM(sales) AS retail_sales,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 2) AS pct_of_retail
FROM clean_weekly_sales WHERE platform = 'Retail'
GROUP BY age_band, demographic ORDER BY retail_sales DESC, age_band, demographic;

-- 2.9 avg_transaction cannot be averaged across rows (an average of averages ignores each row's transaction count).
--     Correct: total sales / total transactions. Both are shown to expose the difference.
SELECT calendar_year, platform,
       ROUND(AVG(avg_transaction), 2)                    AS avg_of_row_averages,
       ROUND(SUM(sales)::numeric / SUM(transactions), 2) AS true_avg_transaction
FROM clean_weekly_sales GROUP BY calendar_year, platform ORDER BY calendar_year, platform;

-- ===== 3. Before & after analysis (baseline 2020-06-15) =====
-- 3.1 / 3.2  4-week and 12-week windows in 2020 (window size is a parameter of the first CTE)
WITH windows(weeks) AS (VALUES (4), (12)),
agg AS (
    SELECT wn.weeks,
           SUM(c.sales) FILTER (WHERE c.week_date <  DATE '2020-06-15') AS before_sales,
           SUM(c.sales) FILTER (WHERE c.week_date >= DATE '2020-06-15') AS after_sales
    FROM windows wn
    JOIN clean_weekly_sales c
      ON c.week_date >= DATE '2020-06-15' - wn.weeks * 7
     AND c.week_date <  DATE '2020-06-15' + wn.weeks * 7
    GROUP BY wn.weeks
)
SELECT weeks, before_sales, after_sales, after_sales - before_sales AS change,
       ROUND(100.0 * (after_sales - before_sales) / before_sales, 2) AS pct_change
FROM agg ORDER BY weeks;

-- 3.3 The same calendar weeks in 2018, 2019 and 2020. 2020-06-15 is week_number 24,
--     so weeks 12-23 are "before" and weeks 24-35 are "after" in every year.
SELECT calendar_year,
       SUM(sales) FILTER (WHERE week_number BETWEEN 12 AND 23) AS before_sales,
       SUM(sales) FILTER (WHERE week_number BETWEEN 24 AND 35) AS after_sales,
       ROUND(100.0 * (SUM(sales) FILTER (WHERE week_number BETWEEN 24 AND 35)
                    - SUM(sales) FILTER (WHERE week_number BETWEEN 12 AND 23))
             / SUM(sales) FILTER (WHERE week_number BETWEEN 12 AND 23), 2) AS pct_change
FROM clean_weekly_sales WHERE week_number BETWEEN 12 AND 35
GROUP BY calendar_year ORDER BY calendar_year;

-- ===== 4. Bonus: 12-week before/after impact by business area (2020) =====
-- Within each dimension, worst_rank 1 is the largest percentage drop.
WITH base AS (
    SELECT * FROM clean_weekly_sales
    WHERE week_date >= DATE '2020-06-15' - 84 AND week_date < DATE '2020-06-15' + 84
),
dims AS (
    SELECT 'region' AS dimension, region AS value, week_date, sales FROM base
    UNION ALL SELECT 'platform',      platform,      week_date, sales FROM base
    UNION ALL SELECT 'age_band',      age_band,      week_date, sales FROM base
    UNION ALL SELECT 'demographic',   demographic,   week_date, sales FROM base
    UNION ALL SELECT 'customer_type', customer_type, week_date, sales FROM base
),
agg AS (
    SELECT dimension, value,
           SUM(sales) FILTER (WHERE week_date <  DATE '2020-06-15') AS before_sales,
           SUM(sales) FILTER (WHERE week_date >= DATE '2020-06-15') AS after_sales
    FROM dims GROUP BY dimension, value
)
SELECT dimension, value, before_sales, after_sales,
       ROUND(100.0 * (after_sales - before_sales) / before_sales, 2) AS pct_change,
       RANK() OVER (PARTITION BY dimension ORDER BY (after_sales - before_sales)::numeric / before_sales) AS worst_rank
FROM agg ORDER BY dimension, worst_rank, value;
