-- Foodie-Fi (Danny Ma's 8 Week SQL Challenge, case study 3) - PostgreSQL 18
-- Run schema.sql first. Scope: section A, B (11 questions), C (2020 payments table) and D (discussion answers).
-- Assumptions:
--   * A customer's plan history is ordered by start_date; the trial (plan_id 0) always comes first.
--   * "Churn" means a row with plan_id 4 (churn). The customer keeps the previous plan until the churn date.
--   * Data covers 2020-01-01 to 2021-04-30, so "2020" counts only events that happened in 2020.
SET search_path = foodie_fi;

-- A. Customer journey: first 8 customers, plan by plan
SELECT s.customer_id, p.plan_name, s.start_date,
       s.start_date - LAG(s.start_date) OVER (PARTITION BY s.customer_id ORDER BY s.start_date) AS days_since_previous
FROM subscriptions s JOIN plans p USING (plan_id)
WHERE s.customer_id <= 8
ORDER BY s.customer_id, s.start_date;

-- B1. How many customers has Foodie-Fi ever had?
SELECT COUNT(DISTINCT customer_id) AS customers FROM subscriptions;

-- B2. Monthly distribution of trial plan start dates
SELECT DATE_TRUNC('month', start_date)::date AS month_start, COUNT(*) AS trials
FROM subscriptions WHERE plan_id = 0
GROUP BY 1 ORDER BY 1;

-- B3. Plan events after 2020 (start_date in 2021 or later), by plan
SELECT p.plan_id, p.plan_name, COUNT(*) AS events
FROM subscriptions s JOIN plans p USING (plan_id)
WHERE s.start_date >= DATE '2021-01-01'
GROUP BY p.plan_id, p.plan_name ORDER BY p.plan_id;

-- B4. Customers who churned: count and percentage (1 decimal)
SELECT COUNT(DISTINCT customer_id) AS churned_customers,
       ROUND(100.0 * COUNT(DISTINCT customer_id) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1) AS pct_of_all
FROM subscriptions WHERE plan_id = 4;

-- B5. Customers who churned straight after the free trial (their very next plan is churn): count and whole-number %
WITH ordered AS (
  SELECT customer_id, plan_id,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY start_date) AS rn
  FROM subscriptions
)
SELECT COUNT(*) AS churned_after_trial,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions)) AS pct_of_all
FROM ordered WHERE rn = 2 AND plan_id = 4;

-- B6. Plan each customer moved to right after the trial: count and % (1 decimal)
WITH ordered AS (
  SELECT customer_id, plan_id,
         ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY start_date) AS rn
  FROM subscriptions
)
SELECT p.plan_name, COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_id) FROM subscriptions), 1) AS pct_of_all
FROM ordered o JOIN plans p USING (plan_id)
WHERE o.rn = 2
GROUP BY p.plan_name ORDER BY customers DESC;

-- B7. Plan breakdown at 2020-12-31: each customer's latest plan on or before that date
WITH latest AS (
  SELECT DISTINCT ON (customer_id) customer_id, plan_id
  FROM subscriptions WHERE start_date <= DATE '2020-12-31'
  ORDER BY customer_id, start_date DESC
)
SELECT p.plan_name, COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM latest l JOIN plans p USING (plan_id)
GROUP BY p.plan_name, p.plan_id ORDER BY p.plan_id;

-- B8. Customers who upgraded to the annual plan during 2020
SELECT COUNT(DISTINCT customer_id) AS annual_in_2020
FROM subscriptions WHERE plan_id = 3 AND start_date BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';

-- B9. Average days from joining (trial start) to the annual plan, for customers who took it
WITH joined AS (SELECT customer_id, start_date AS join_date FROM subscriptions WHERE plan_id = 0),
     annual AS (SELECT customer_id, start_date AS annual_date FROM subscriptions WHERE plan_id = 3)
SELECT ROUND(AVG(a.annual_date - j.join_date), 1) AS avg_days_to_annual, COUNT(*) AS customers
FROM joined j JOIN annual a USING (customer_id);

-- B10. Same, in 30-day buckets
WITH joined AS (SELECT customer_id, start_date AS join_date FROM subscriptions WHERE plan_id = 0),
     annual AS (SELECT customer_id, start_date AS annual_date FROM subscriptions WHERE plan_id = 3),
     d AS (SELECT a.annual_date - j.join_date AS days FROM joined j JOIN annual a USING (customer_id))
SELECT (days / 30) * 30 || '-' || (days / 30) * 30 + 29 AS bucket_days, COUNT(*) AS customers, ROUND(AVG(days), 1) AS avg_days
FROM d GROUP BY days / 30 ORDER BY days / 30;

-- B11. Customers who downgraded from pro monthly to basic monthly in 2020
WITH seq AS (
  SELECT customer_id, plan_id, start_date,
         LEAD(plan_id) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_plan,
         LEAD(start_date) OVER (PARTITION BY customer_id ORDER BY start_date) AS next_date
  FROM subscriptions
)
SELECT COUNT(*) AS downgrades_2020
FROM seq WHERE plan_id = 2 AND next_plan = 1 AND next_date BETWEEN DATE '2020-01-01' AND DATE '2020-12-31';


-- C. Challenge: 2020 payments table
-- Rules from the case study: monthly payments fall on the day of month of the plan start_date; a basic -> pro
-- upgrade pays the new price minus what was already paid that calendar month and starts immediately; pro monthly -> pro annual
-- is paid at the end of the current billing period; after churn nothing is paid. Trial is free.
-- Assumptions (stated because the rules leave them open):
--   * "Already paid that month" = a basic payment made in the same calendar month, before the upgrade date.
--   * A basic -> pro annual upgrade follows the same reduction rule as basic -> pro monthly.
--   * Monthly dates are start_date + k months (k = 0, 1, ...), only dates before the next plan starts, and only in 2020.
--   * Downgrades (pro monthly -> basic) never occur in 2020 (B11 = 0), so they are not modelled.
DROP TABLE IF EXISTS payments;
CREATE TABLE payments AS
WITH plan_rows AS (
  SELECT s.customer_id, s.plan_id, p.plan_name, p.price, s.start_date,
         LEAD(s.start_date) OVER w AS next_start,
         LEAD(s.plan_id)    OVER w AS next_plan,
         LAG(s.start_date)  OVER w AS prev_start,
         LAG(s.plan_id)     OVER w AS prev_plan
  FROM subscriptions s JOIN plans p USING (plan_id)
  WINDOW w AS (PARTITION BY s.customer_id ORDER BY s.start_date)
),
monthly AS (   -- basic and pro monthly billing dates inside 2020
  SELECT r.*, (r.start_date + make_interval(months => k))::date AS payment_date, k
  FROM plan_rows r
  CROSS JOIN LATERAL generate_series(0, 12) AS k
  WHERE r.plan_id IN (1, 2)
    AND (r.start_date + make_interval(months => k))::date <= DATE '2020-12-31'
    AND (r.start_date + make_interval(months => k))::date < COALESCE(r.next_start, DATE '2021-01-01')
),
monthly_amt AS (
  SELECT m.customer_id, m.plan_id, m.plan_name, m.payment_date,
         CASE WHEN m.k = 0 AND m.plan_id = 2 AND m.prev_plan = 1
                   AND EXISTS (  -- a basic payment earlier in the same calendar month
                     SELECT 1 FROM generate_series(0, 12) AS j
                     WHERE (m.prev_start + make_interval(months => j))::date < m.start_date
                       AND DATE_TRUNC('month', m.prev_start + make_interval(months => j)) = DATE_TRUNC('month', m.start_date::timestamp))
              THEN m.price - 9.90
              ELSE m.price END AS amount
  FROM monthly m
),
annual AS (    -- pro annual: single payment
  SELECT r.customer_id, r.plan_id, r.plan_name,
         CASE WHEN r.prev_plan = 2
              THEN (SELECT MIN((r.prev_start + make_interval(months => k))::date)
                    FROM generate_series(0, 24) AS k
                    WHERE (r.prev_start + make_interval(months => k))::date >= r.start_date)  -- end of the current billing period
              ELSE r.start_date END AS payment_date,
         CASE WHEN r.prev_plan = 1
                   AND EXISTS (
                     SELECT 1 FROM generate_series(0, 12) AS j
                     WHERE (r.prev_start + make_interval(months => j))::date < r.start_date
                       AND DATE_TRUNC('month', r.prev_start + make_interval(months => j)) = DATE_TRUNC('month', r.start_date::timestamp))
              THEN r.price - 9.90
              ELSE r.price END AS amount
  FROM plan_rows r WHERE r.plan_id = 3
),
all_pay AS (
  SELECT customer_id, plan_id, plan_name, payment_date, amount FROM monthly_amt
  UNION ALL
  SELECT customer_id, plan_id, plan_name, payment_date, amount FROM annual WHERE payment_date <= DATE '2020-12-31'
)
SELECT customer_id, plan_id, plan_name, payment_date, amount,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY payment_date) AS payment_order
FROM all_pay;

-- Checks: sample customers named on the case study page, and totals
SELECT customer_id, plan_name, payment_date, amount, payment_order
FROM payments WHERE customer_id IN (1, 2, 13, 15, 16, 18, 19) ORDER BY customer_id, payment_order;
SELECT COUNT(*) AS payment_rows, COUNT(DISTINCT customer_id) AS paying_customers, SUM(amount) AS total_2020 FROM payments;

-- D. Outside the box (discussion answers; not computed from the data except where noted)
-- D1 Growth rate: monthly net new customers and recurring revenue growth. From this data: trials started per month (B2) and
--    active paying customers at each month end, compared month on month.
-- D2 Metrics to track: trial-to-paid conversion, churn by plan and tenure, monthly recurring revenue, annual-plan share,
--    days from trial to annual upgrade (B9/B10), revenue per customer.
-- D3 Journeys to analyse: trial -> basic -> churn (B5, B6), basic -> pro upgrade timing, the first 90 days after the trial.
-- D4 Exit survey: main reason for leaving, price vs content, what would have kept you, which plan you were on, how long you used it.
-- D5 Levers: win-back offers, annual-plan discounts, content releases timed to renewals; validate with a randomised holdout or
--    A/B test on the offer, measured on churn at 30 and 90 days.
