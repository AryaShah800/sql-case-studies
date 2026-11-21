-- Balanced Tree Clothing Co. (Danny Ma's 8 Week SQL Challenge, case study 7) - PostgreSQL
-- Run schema.sql first. Scope: high level sales, transactions, products, reporting challenge, bonus.
-- Assumptions:
--   * sales.discount is a percentage of the line price (17 = 17%); revenue before discount = qty * price.
--   * discount amount = qty * price * discount / 100 (kept as numeric, not rounded, until display).
--   * Revenue questions use revenue BEFORE discount unless stated, as the brief words them.
--   * "Top selling" = highest quantity sold; ties would be kept by RANK (none occur in this data).
--   * Transaction-level numbers first aggregate sales lines to one row per txn_id.
SET search_path = balanced_tree;

-- ===== High level sales analysis =====
-- H1-H3 total quantity, revenue before discount, discount amount
SELECT SUM(qty) AS total_qty,
       SUM(qty * price) AS revenue_before_discount,
       ROUND(SUM(qty * price * discount / 100.0), 2) AS total_discount
FROM sales;

-- ===== Transaction analysis =====
-- T1 unique transactions
SELECT COUNT(DISTINCT txn_id) AS unique_txns FROM sales;

-- T2 average unique products per transaction
SELECT ROUND(AVG(products), 2) AS avg_unique_products
FROM (SELECT txn_id, COUNT(DISTINCT prod_id) AS products FROM sales GROUP BY txn_id) t;

-- T3 25th/50th/75th percentile of revenue per transaction (before discount)
SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) AS p25,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) AS p50,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) AS p75
FROM (SELECT txn_id, SUM(qty * price) AS revenue FROM sales GROUP BY txn_id) t;

-- T4 average discount value per transaction
SELECT ROUND(AVG(discount_value), 2) AS avg_discount_per_txn
FROM (SELECT txn_id, SUM(qty * price * discount / 100.0) AS discount_value FROM sales GROUP BY txn_id) t;

-- T5 member vs non-member share of transactions (member is constant within a transaction)
SELECT CASE WHEN member THEN 'member' ELSE 'non-member' END AS customer,
       COUNT(DISTINCT txn_id) AS txns,
       ROUND(100.0 * COUNT(DISTINCT txn_id) / SUM(COUNT(DISTINCT txn_id)) OVER (), 2) AS pct_txns
FROM sales GROUP BY member ORDER BY member DESC;

-- T6 average revenue per transaction, members vs non-members
SELECT CASE WHEN member THEN 'member' ELSE 'non-member' END AS customer,
       ROUND(AVG(revenue), 2) AS avg_revenue_per_txn
FROM (SELECT txn_id, member, SUM(qty * price) AS revenue FROM sales GROUP BY txn_id, member) t
GROUP BY member ORDER BY member DESC;

-- ===== Product analysis =====
-- P1 top 3 products by revenue before discount
SELECT d.product_name, SUM(s.qty * s.price) AS revenue
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.product_name ORDER BY revenue DESC LIMIT 3;

-- P2 quantity, revenue, discount per segment
SELECT d.segment_name, SUM(s.qty) AS qty, SUM(s.qty * s.price) AS revenue,
       ROUND(SUM(s.qty * s.price * s.discount / 100.0), 2) AS discount
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.segment_name ORDER BY d.segment_name;

-- P3 top selling product (by quantity) per segment
SELECT segment_name, product_name, qty FROM (
    SELECT d.segment_name, d.product_name, SUM(s.qty) AS qty,
           RANK() OVER (PARTITION BY d.segment_name ORDER BY SUM(s.qty) DESC) AS rnk
    FROM sales s JOIN product_details d ON d.product_id = s.prod_id
    GROUP BY d.segment_name, d.product_name) r
WHERE rnk = 1 ORDER BY segment_name;

-- P4 quantity, revenue, discount per category
SELECT d.category_name, SUM(s.qty) AS qty, SUM(s.qty * s.price) AS revenue,
       ROUND(SUM(s.qty * s.price * s.discount / 100.0), 2) AS discount
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.category_name ORDER BY d.category_name;

-- P5 top selling product (by quantity) per category
SELECT category_name, product_name, qty FROM (
    SELECT d.category_name, d.product_name, SUM(s.qty) AS qty,
           RANK() OVER (PARTITION BY d.category_name ORDER BY SUM(s.qty) DESC) AS rnk
    FROM sales s JOIN product_details d ON d.product_id = s.prod_id
    GROUP BY d.category_name, d.product_name) r
WHERE rnk = 1 ORDER BY category_name;

-- P6 revenue split by product within each segment
SELECT d.segment_name, d.product_name, SUM(s.qty * s.price) AS revenue,
       ROUND(100.0 * SUM(s.qty * s.price) / SUM(SUM(s.qty * s.price)) OVER (PARTITION BY d.segment_name), 2) AS pct_of_segment
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.segment_name, d.product_name ORDER BY d.segment_name, revenue DESC;

-- P7 revenue split by segment within each category
SELECT d.category_name, d.segment_name, SUM(s.qty * s.price) AS revenue,
       ROUND(100.0 * SUM(s.qty * s.price) / SUM(SUM(s.qty * s.price)) OVER (PARTITION BY d.category_name), 2) AS pct_of_category
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.category_name, d.segment_name ORDER BY d.category_name, revenue DESC;

-- P8 revenue split by category
SELECT d.category_name, SUM(s.qty * s.price) AS revenue,
       ROUND(100.0 * SUM(s.qty * s.price) / SUM(SUM(s.qty * s.price)) OVER (), 2) AS pct_of_total
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
GROUP BY d.category_name ORDER BY d.category_name;

-- P9 transaction penetration per product (txns containing the product / all txns)
SELECT d.product_name,
       COUNT(DISTINCT s.txn_id) AS txns_with_product,
       ROUND(100.0 * COUNT(DISTINCT s.txn_id) / (SELECT COUNT(DISTINCT txn_id) FROM sales), 2) AS penetration_pct
FROM sales s JOIN product_details d ON d.product_id = s.prod_id
WHERE s.qty >= 1
GROUP BY d.product_name ORDER BY penetration_pct DESC, d.product_name;

-- P10 most common combination of 3 different products in one transaction.
-- Ordering the ids (a < b < c) counts each combination once.
SELECT da.product_name AS product_1, db.product_name AS product_2, dc.product_name AS product_3,
       COUNT(*) AS txns
FROM sales a
JOIN sales b ON b.txn_id = a.txn_id AND b.prod_id > a.prod_id
JOIN sales c ON c.txn_id = a.txn_id AND c.prod_id > b.prod_id
JOIN product_details da ON da.product_id = a.prod_id
JOIN product_details db ON db.product_id = b.prod_id
JOIN product_details dc ON dc.product_id = c.prod_id
GROUP BY da.product_name, db.product_name, dc.product_name
ORDER BY txns DESC, product_1, product_2, product_3 LIMIT 3;

-- ===== Reporting challenge =====
-- One function runs the monthly report for any month; the CFO calls it with a date. Output is metric/value rows
-- tagged with the question they answer. Run for January, then February, with no other change.
CREATE OR REPLACE FUNCTION monthly_report(p_month date)
RETURNS TABLE (question text, metric text, value numeric)
LANGUAGE sql STABLE AS $$
    WITH m AS (
        SELECT * FROM balanced_tree.sales
        WHERE start_txn_time >= date_trunc('month', p_month)
          AND start_txn_time <  date_trunc('month', p_month) + INTERVAL '1 month'
    ),
    t AS (
        SELECT txn_id, bool_or(member) AS member, COUNT(DISTINCT prod_id) AS products,
               SUM(qty * price) AS revenue, SUM(qty * price * discount / 100.0) AS discount
        FROM m GROUP BY txn_id
    )
    SELECT 'H1', 'total quantity', SUM(qty)::numeric FROM m
    UNION ALL SELECT 'H2', 'revenue before discount', SUM(qty * price)::numeric FROM m
    UNION ALL SELECT 'H3', 'total discount', ROUND(SUM(qty * price * discount / 100.0), 2) FROM m
    UNION ALL SELECT 'T1', 'unique transactions', COUNT(*)::numeric FROM t
    UNION ALL SELECT 'T2', 'avg unique products per txn', ROUND(AVG(products), 2) FROM t
    UNION ALL SELECT 'T3', 'p25 revenue per txn', PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue)::numeric FROM t
    UNION ALL SELECT 'T3', 'p50 revenue per txn', PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue)::numeric FROM t
    UNION ALL SELECT 'T3', 'p75 revenue per txn', PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue)::numeric FROM t
    UNION ALL SELECT 'T4', 'avg discount per txn', ROUND(AVG(discount), 2) FROM t
    UNION ALL SELECT 'T5', 'member txn share %', ROUND(100.0 * COUNT(*) FILTER (WHERE member) / COUNT(*), 2) FROM t
    UNION ALL SELECT 'T6', 'avg revenue per member txn', ROUND(AVG(revenue) FILTER (WHERE member), 2) FROM t
    UNION ALL SELECT 'T6', 'avg revenue per non-member txn', ROUND(AVG(revenue) FILTER (WHERE NOT member), 2) FROM t
$$;

SELECT * FROM monthly_report(DATE '2021-01-01');
SELECT * FROM monthly_report(DATE '2021-02-01');

-- Product-level monthly report: revenue and share by category for a month (P-section questions follow the same shape)
CREATE OR REPLACE FUNCTION monthly_category_report(p_month date)
RETURNS TABLE (category_name text, qty bigint, revenue bigint, discount numeric, pct_of_revenue numeric)
LANGUAGE sql STABLE AS $$
    SELECT d.category_name::text, SUM(s.qty), SUM(s.qty * s.price)::bigint,
           ROUND(SUM(s.qty * s.price * s.discount / 100.0), 2),
           ROUND(100.0 * SUM(s.qty * s.price) / SUM(SUM(s.qty * s.price)) OVER (), 2)
    FROM balanced_tree.sales s JOIN balanced_tree.product_details d ON d.product_id = s.prod_id
    WHERE s.start_txn_time >= date_trunc('month', p_month)
      AND s.start_txn_time <  date_trunc('month', p_month) + INTERVAL '1 month'
    GROUP BY d.category_name ORDER BY d.category_name
$$;

SELECT * FROM monthly_category_report(DATE '2021-01-01');
SELECT * FROM monthly_category_report(DATE '2021-02-01');

-- ===== Bonus: rebuild product_details from product_hierarchy + product_prices in one query =====
-- Recursive CTE walks Style -> Segment -> Category; the result is compared to the shipped table.
WITH RECURSIVE tree AS (
    SELECT id, parent_id, level_text, level_name, id AS style_id
    FROM product_hierarchy WHERE level_name = 'Style'
    UNION ALL
    SELECT h.id, h.parent_id, h.level_text, h.level_name, t.style_id
    FROM tree t JOIN product_hierarchy h ON h.id = t.parent_id
),
rebuilt AS (
    SELECT pp.product_id, pp.price,
           CONCAT_WS(' ', st.level_text, sg.level_text, '-', ca.level_text) AS product_name,
           ca.id AS category_id, sg.id AS segment_id, st.id AS style_id,
           ca.level_text AS category_name, sg.level_text AS segment_name, st.level_text AS style_name
    FROM product_prices pp
    JOIN tree st ON st.style_id = pp.id AND st.level_name = 'Style'
    JOIN tree sg ON sg.style_id = pp.id AND sg.level_name = 'Segment'
    JOIN tree ca ON ca.style_id = pp.id AND ca.level_name = 'Category'
)
SELECT (SELECT COUNT(*) FROM rebuilt) AS rebuilt_rows,
       (SELECT COUNT(*) FROM (SELECT * FROM rebuilt EXCEPT SELECT * FROM product_details) x) AS only_in_rebuilt,
       (SELECT COUNT(*) FROM (SELECT * FROM product_details EXCEPT SELECT * FROM rebuilt) x) AS only_in_shipped;
