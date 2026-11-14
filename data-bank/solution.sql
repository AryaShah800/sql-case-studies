-- Data Bank (Danny Ma's 8 Week SQL Challenge, case study 4) - PostgreSQL 18
-- Run schema.sql first. Scope: A (nodes), B (transactions), C (data allocation options), D (interest option).
-- The "Extension Request" (headline insights, one-page slide) is covered by the README insights, not by SQL.
-- Assumptions:
--   * end_date 9999-12-31 marks the current assignment; it is excluded from reallocation-day statistics.
--   * Reallocation days = end_date - start_date of each completed assignment row (consecutive rows on the same node are not merged).
--   * Deposits add to the balance; purchases and withdrawals subtract.
--   * Allocations are floored at 0: a negative balance needs no storage.
SET search_path = data_bank;

-- A1. Unique nodes
SELECT COUNT(DISTINCT node_id) AS unique_nodes FROM customer_nodes;
-- A2. Nodes per region (distinct node ids used in each region)
SELECT r.region_name, COUNT(DISTINCT n.node_id) AS nodes
FROM customer_nodes n JOIN regions r USING (region_id) GROUP BY r.region_name ORDER BY r.region_name;
-- A3. Customers per region (distinct customers)
SELECT r.region_name, COUNT(DISTINCT n.customer_id) AS customers
FROM customer_nodes n JOIN regions r USING (region_id) GROUP BY r.region_name ORDER BY customers DESC;
-- A4. Average days before reallocation
SELECT ROUND(AVG(end_date - start_date), 1) AS avg_days
FROM customer_nodes WHERE end_date <> DATE '9999-12-31';
-- A5. Median, 80th and 95th percentile by region
SELECT r.region_name,
       PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY n.end_date - n.start_date) AS median_days,
       PERCENTILE_CONT(0.8)  WITHIN GROUP (ORDER BY n.end_date - n.start_date) AS p80_days,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY n.end_date - n.start_date) AS p95_days
FROM customer_nodes n JOIN regions r USING (region_id)
WHERE n.end_date <> DATE '9999-12-31'
GROUP BY r.region_name ORDER BY r.region_name;

-- B1. Count and total amount per transaction type
SELECT txn_type, COUNT(*) AS txns, SUM(txn_amount) AS total_amount
FROM customer_transactions GROUP BY txn_type ORDER BY txn_type;
-- B2. Average historical deposit count and amount per customer
WITH d AS (SELECT customer_id, COUNT(*) AS n, SUM(txn_amount) AS amt FROM customer_transactions WHERE txn_type = 'deposit' GROUP BY customer_id)
SELECT ROUND(AVG(n), 2) AS avg_deposit_count, ROUND(AVG(amt), 2) AS avg_deposit_total, ROUND(SUM(amt) / SUM(n), 2) AS avg_deposit_size FROM d;
-- B3. Customers per month with more than 1 deposit and at least 1 purchase or withdrawal
WITH m AS (
  SELECT customer_id, DATE_TRUNC('month', txn_date)::date AS month_start,
         COUNT(*) FILTER (WHERE txn_type = 'deposit') AS deposits,
         COUNT(*) FILTER (WHERE txn_type = 'purchase') AS purchases,
         COUNT(*) FILTER (WHERE txn_type = 'withdrawal') AS withdrawals
  FROM customer_transactions GROUP BY 1, 2)
SELECT month_start, COUNT(*) AS customers
FROM m WHERE deposits > 1 AND (purchases >= 1 OR withdrawals >= 1) GROUP BY month_start ORDER BY month_start;
-- B4. Closing balance per customer at the end of each month (months with no transactions carry the previous balance forward)
DROP TABLE IF EXISTS month_end_balance;
CREATE TEMP TABLE month_end_balance AS
WITH cm AS (  -- every customer x month, Jan to Apr 2020
  SELECT c.customer_id, g::date AS month_start
  FROM (SELECT DISTINCT customer_id FROM customer_transactions) c
  CROSS JOIN generate_series(DATE '2020-01-01', DATE '2020-04-01', INTERVAL '1 month') g),
net AS (
  SELECT customer_id, DATE_TRUNC('month', txn_date)::date AS month_start,
         SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS net_change
  FROM customer_transactions GROUP BY 1, 2)
SELECT cm.customer_id, cm.month_start,
       (cm.month_start + INTERVAL '1 month - 1 day')::date AS month_end,
       SUM(COALESCE(net.net_change, 0)) OVER (PARTITION BY cm.customer_id ORDER BY cm.month_start) AS closing_balance
FROM cm LEFT JOIN net USING (customer_id, month_start);
SELECT * FROM month_end_balance WHERE customer_id IN (1, 2, 3) ORDER BY customer_id, month_start;
-- B5. Customers whose closing balance rose by more than 5% month on month (only months with a positive previous balance count):
--     share of customers with at least one such month, and share of such customer-months.
WITH g AS (
  SELECT customer_id, month_start, closing_balance,
         LAG(closing_balance) OVER (PARTITION BY customer_id ORDER BY month_start) AS prev_balance
  FROM month_end_balance)
SELECT ROUND(100.0 * COUNT(DISTINCT customer_id) FILTER (WHERE prev_balance > 0 AND closing_balance > prev_balance * 1.05)
             / COUNT(DISTINCT customer_id), 1) AS pct_customers_with_a_5pct_rise_month,
       ROUND(100.0 * COUNT(*) FILTER (WHERE prev_balance > 0 AND closing_balance > prev_balance * 1.05)
             / COUNT(*) FILTER (WHERE prev_balance > 0), 1) AS pct_of_months_with_5pct_rise
FROM g;

-- C. Data allocation: one row per customer and calendar day with the running balance
DROP TABLE IF EXISTS daily_balance;
CREATE TEMP TABLE daily_balance AS
WITH days AS (
  SELECT c.customer_id, d::date AS day
  FROM (SELECT customer_id, MIN(txn_date) AS first_day FROM customer_transactions GROUP BY customer_id) c
  CROSS JOIN LATERAL generate_series(c.first_day, DATE '2020-04-30', INTERVAL '1 day') d),
chg AS (
  SELECT customer_id, txn_date AS day, SUM(CASE WHEN txn_type = 'deposit' THEN txn_amount ELSE -txn_amount END) AS chg
  FROM customer_transactions GROUP BY 1, 2)
SELECT days.customer_id, days.day,
       SUM(COALESCE(chg.chg, 0)) OVER (PARTITION BY days.customer_id ORDER BY days.day) AS balance
FROM days LEFT JOIN chg USING (customer_id, day);
-- Per-customer minimum, average and maximum running balance (averaged over customers)
SELECT ROUND(AVG(mn), 0) AS avg_of_min, ROUND(AVG(av), 0) AS avg_of_avg, ROUND(AVG(mx), 0) AS avg_of_max
FROM (SELECT customer_id, MIN(balance) mn, AVG(balance) av, MAX(balance) mx FROM daily_balance GROUP BY customer_id) t;
-- Data required per month and option (sum over customers; allocations floored at 0)
--   Option 1: balance at the end of the previous month.
--   Option 2: average daily balance over the previous 30 days.
--   Option 3: real-time = the highest balance the customer reached during the month.
-- Options 1 and 2 need a previous period, so they start in February 2020; Option 3 covers January to April.
WITH months AS (SELECT generate_series(DATE '2020-01-01', DATE '2020-04-01', INTERVAL '1 month')::date AS month_start),
o1 AS (SELECT (month_start + INTERVAL '1 month')::date AS month_start, SUM(GREATEST(closing_balance, 0)) AS data_required
       FROM month_end_balance GROUP BY 1),
o2 AS (SELECT m.month_start, SUM(GREATEST(a.avg_bal, 0)) AS data_required
       FROM months m
       JOIN LATERAL (SELECT customer_id, AVG(balance) AS avg_bal FROM daily_balance
                     WHERE day >= m.month_start - 30 AND day < m.month_start GROUP BY customer_id) a ON TRUE
       GROUP BY m.month_start),
o3 AS (SELECT month_start, SUM(mx) AS data_required
       FROM (SELECT customer_id, DATE_TRUNC('month', day)::date AS month_start, GREATEST(MAX(balance), 0) AS mx FROM daily_balance GROUP BY 1, 2) t
       GROUP BY 1)
SELECT m.month_start, o1.data_required AS option1_prev_month_end, ROUND(o2.data_required) AS option2_prev_30d_avg, o3.data_required AS option3_peak_in_month
FROM months m LEFT JOIN o1 USING (month_start) LEFT JOIN o2 USING (month_start) LEFT JOIN o3 USING (month_start)
ORDER BY m.month_start;

-- D. Extra: 6% annual interest on the daily balance, no compounding, accrued daily.
--    Data required in a month = interest accrued during that month on positive daily balances + the month-end balance (floored at 0).
WITH interest AS (
  SELECT DATE_TRUNC('month', day)::date AS month_start, SUM(GREATEST(balance, 0) * 0.06 / 365) AS interest_alloc
  FROM daily_balance GROUP BY 1),
closing AS (
  SELECT month_start, SUM(GREATEST(closing_balance, 0)) AS closing_alloc FROM month_end_balance GROUP BY 1)
SELECT i.month_start, ROUND(i.interest_alloc, 0) AS interest_allocation, ROUND(i.interest_alloc + c.closing_alloc, 0) AS data_required_with_interest
FROM interest i JOIN closing c USING (month_start) ORDER BY i.month_start;
