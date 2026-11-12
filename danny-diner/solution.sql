-- Danny's Diner: solutions in PostgreSQL. Run schema.sql first.
-- Conventions (assumptions stated once, used throughout):
--   * order_date has no time of day, so several items bought on one day are treated as bought together.
--   * A purchase on the join date counts as a MEMBER purchase (order_date >= join_date), matching Q10's "including their join date".
--   * Ties are kept (RANK / DENSE_RANK) rather than hidden by LIMIT 1.
SET search_path = dannys_diner;

-- Q1. Total amount each customer spent
SELECT s.customer_id, SUM(m.price) AS total_spent
FROM sales AS s
JOIN menu  AS m USING (product_id)
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q2. Days each customer visited
SELECT customer_id, COUNT(DISTINCT order_date) AS days_visited
FROM sales
GROUP BY customer_id
ORDER BY customer_id;

-- Q3. First item(s) purchased by each customer (all items on their first day, since there is no time of day)
WITH ranked AS (
  SELECT s.customer_id, m.product_name,
         DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date) AS rnk
  FROM sales AS s
  JOIN menu  AS m USING (product_id)
)
SELECT DISTINCT customer_id, product_name
FROM ranked
WHERE rnk = 1
ORDER BY customer_id, product_name;

-- Q4. Most purchased item on the menu, and how many times it was purchased by all customers
WITH counts AS (
  SELECT m.product_name, COUNT(*) AS times_purchased,
         RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
  FROM sales AS s
  JOIN menu  AS m USING (product_id)
  GROUP BY m.product_name
)
SELECT product_name, times_purchased
FROM counts
WHERE rnk = 1;

-- Q5. Most popular item for each customer (ties are all shown)
WITH counts AS (
  SELECT s.customer_id, m.product_name, COUNT(*) AS times_purchased,
         RANK() OVER (PARTITION BY s.customer_id ORDER BY COUNT(*) DESC) AS rnk
  FROM sales AS s
  JOIN menu  AS m USING (product_id)
  GROUP BY s.customer_id, m.product_name
)
SELECT customer_id, product_name, times_purchased
FROM counts
WHERE rnk = 1
ORDER BY customer_id, product_name;

-- Q6. First item purchased after becoming a member (join date included)
WITH after_join AS (
  SELECT s.customer_id, m.product_name,
         DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date) AS rnk
  FROM sales   AS s
  JOIN members AS mb USING (customer_id)
  JOIN menu    AS m  USING (product_id)
  WHERE s.order_date >= mb.join_date
)
SELECT DISTINCT customer_id, product_name
FROM after_join
WHERE rnk = 1
ORDER BY customer_id, product_name;

-- Q7. Item(s) purchased just before becoming a member
WITH before_join AS (
  SELECT s.customer_id, m.product_name,
         DENSE_RANK() OVER (PARTITION BY s.customer_id ORDER BY s.order_date DESC) AS rnk
  FROM sales   AS s
  JOIN members AS mb USING (customer_id)
  JOIN menu    AS m  USING (product_id)
  WHERE s.order_date < mb.join_date
)
SELECT DISTINCT customer_id, product_name
FROM before_join
WHERE rnk = 1
ORDER BY customer_id, product_name;

-- Q8. Total items and amount spent by each member before becoming a member
SELECT s.customer_id, COUNT(*) AS total_items, SUM(m.price) AS amount_spent
FROM sales   AS s
JOIN members AS mb USING (customer_id)
JOIN menu    AS m  USING (product_id)
WHERE s.order_date < mb.join_date
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q9. Points if $1 = 10 points and sushi earns double (all purchases, members or not)
SELECT s.customer_id,
       SUM(m.price * 10 * CASE WHEN m.product_name = 'sushi' THEN 2 ELSE 1 END) AS points
FROM sales AS s
JOIN menu  AS m USING (product_id)
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Q10. Customers A and B: points at the end of January when the first week after joining
--      (join date plus 6 days) earns 2x on every item, and sushi is 2x otherwise
SELECT s.customer_id,
       SUM(m.price * 10 * CASE
             WHEN s.order_date BETWEEN mb.join_date AND mb.join_date + 6 THEN 2
             WHEN m.product_name = 'sushi' THEN 2
             ELSE 1 END) AS points_end_of_january
FROM sales   AS s
JOIN members AS mb USING (customer_id)
JOIN menu    AS m  USING (product_id)
WHERE s.order_date <= DATE '2021-01-31'
  AND s.customer_id IN ('A', 'B')
GROUP BY s.customer_id
ORDER BY s.customer_id;

-- Bonus 1. Join all the things: every purchase with its price and whether the customer was a member at the time
SELECT s.customer_id, s.order_date, m.product_name, m.price,
       CASE WHEN mb.join_date IS NOT NULL AND s.order_date >= mb.join_date THEN 'Y' ELSE 'N' END AS member
FROM sales   AS s
JOIN menu    AS m  USING (product_id)
LEFT JOIN members AS mb USING (customer_id)
ORDER BY s.customer_id, s.order_date, m.product_name;

-- Bonus 2. Rank all the things: rank member purchases by date; non-member purchases get NULL
WITH joined AS (
  SELECT s.customer_id, s.order_date, m.product_name, m.price,
         CASE WHEN mb.join_date IS NOT NULL AND s.order_date >= mb.join_date THEN 'Y' ELSE 'N' END AS member
  FROM sales   AS s
  JOIN menu    AS m  USING (product_id)
  LEFT JOIN members AS mb USING (customer_id)
)
SELECT *,
       CASE WHEN member = 'Y'
            THEN DENSE_RANK() OVER (PARTITION BY customer_id, member ORDER BY order_date) END AS ranking
FROM joined
ORDER BY customer_id, order_date, product_name;
