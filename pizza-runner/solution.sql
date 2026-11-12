-- Pizza Runner: solutions in PostgreSQL 14+ (uses string_to_table). Run schema.sql first.
-- Assumptions (stated once, used throughout):
--   * "Delivered" / "successful" = the order has no cancellation (orders 6 and 9 are cancelled).
--   * Questions about orders or customers count each order once; questions about pizzas count each pizza row.
--   * Revenue and delivery metrics use delivered orders only; "ordered" metrics use every order.
--   * Money: Meat Lovers $12, Vegetarian $10 (from Section D).
SET search_path = pizza_runner;

-- =====================================================================
-- 0. Data cleaning layer (the raw tables are left untouched)
--    Problems found: '' and 'null' text and real NULLs all mean "none"; distance and duration carry units
--    ('20km', '23.4 km', '32 minutes', '25mins', '15 minute'); pickup_time is text.
-- =====================================================================
CREATE OR REPLACE VIEW customer_orders_clean AS
SELECT ROW_NUMBER() OVER (ORDER BY order_id, pizza_id, exclusions, extras) AS order_item_id,   -- one id per pizza row
       order_id, customer_id, pizza_id,
       NULLIF(NULLIF(TRIM(exclusions), ''), 'null') AS exclusions,
       NULLIF(NULLIF(TRIM(extras),     ''), 'null') AS extras,
       order_time
FROM customer_orders;

CREATE OR REPLACE VIEW runner_orders_clean AS
SELECT order_id, runner_id,
       NULLIF(pickup_time, 'null')::timestamp AS pickup_time,
       NULLIF(regexp_replace(COALESCE(NULLIF(distance, 'null'), ''), '[^0-9.]', '', 'g'), '')::numeric AS distance_km,
       NULLIF(regexp_replace(COALESCE(NULLIF(duration, 'null'), ''), '[^0-9]',  '', 'g'), '')::int     AS duration_min,
       NULLIF(NULLIF(TRIM(cancellation), ''), 'null') AS cancellation
FROM runner_orders;

CREATE OR REPLACE VIEW delivered_orders AS
SELECT * FROM runner_orders_clean WHERE cancellation IS NULL;

-- One row per order (customer, time, pizza count)
CREATE OR REPLACE VIEW orders AS
SELECT order_id, MIN(customer_id) AS customer_id, MIN(order_time) AS order_time, COUNT(*) AS pizzas
FROM customer_orders_clean
GROUP BY order_id;

-- Exclusions and extras split into one row per topping (pos keeps the order they were written in)
CREATE OR REPLACE VIEW order_item_changes AS
SELECT c.order_item_id, 'exclusion' AS kind, TRIM(t.v)::int AS topping_id, t.n AS pos
FROM customer_orders_clean AS c, LATERAL string_to_table(c.exclusions, ',') WITH ORDINALITY AS t(v, n)
WHERE c.exclusions IS NOT NULL
UNION ALL
SELECT c.order_item_id, 'extra', TRIM(t.v)::int, t.n
FROM customer_orders_clean AS c, LATERAL string_to_table(c.extras, ',') WITH ORDINALITY AS t(v, n)
WHERE c.extras IS NOT NULL;

-- The comma-separated recipe column, split into one row per topping
CREATE OR REPLACE VIEW recipe_toppings AS
SELECT r.pizza_id, TRIM(t.v)::int AS topping_id
FROM pizza_recipes AS r, LATERAL string_to_table(r.toppings, ',') AS t(v);

-- Every ingredient that goes on every ordered pizza: recipe minus exclusions, plus extras (a repeat = double)
CREATE OR REPLACE VIEW order_item_ingredients AS
SELECT c.order_item_id, r.topping_id
FROM customer_orders_clean AS c
JOIN recipe_toppings AS r USING (pizza_id)
WHERE NOT EXISTS (SELECT 1 FROM order_item_changes AS x
                  WHERE x.order_item_id = c.order_item_id AND x.kind = 'exclusion' AND x.topping_id = r.topping_id)
UNION ALL
SELECT order_item_id, topping_id FROM order_item_changes WHERE kind = 'extra';

-- =====================================================================
-- A. Pizza Metrics
-- =====================================================================
-- A1. How many pizzas were ordered?
SELECT COUNT(*) AS pizzas_ordered FROM customer_orders_clean;

-- A2. How many unique customer orders were made?
SELECT COUNT(DISTINCT order_id) AS unique_orders FROM customer_orders_clean;

-- A3. How many successful orders were delivered by each runner?
SELECT runner_id, COUNT(*) AS delivered_orders
FROM delivered_orders
GROUP BY runner_id
ORDER BY runner_id;

-- A4. How many of each type of pizza was delivered?
SELECT n.pizza_name, COUNT(*) AS pizzas_delivered
FROM customer_orders_clean AS c
JOIN delivered_orders      AS d USING (order_id)
JOIN pizza_names           AS n USING (pizza_id)
GROUP BY n.pizza_name
ORDER BY n.pizza_name;

-- A5. How many Vegetarian and Meatlovers were ordered by each customer?
SELECT c.customer_id,
       COUNT(*) FILTER (WHERE n.pizza_name = 'Meatlovers') AS meatlovers,
       COUNT(*) FILTER (WHERE n.pizza_name = 'Vegetarian') AS vegetarian
FROM customer_orders_clean AS c
JOIN pizza_names AS n USING (pizza_id)
GROUP BY c.customer_id
ORDER BY c.customer_id;

-- A6. Maximum number of pizzas delivered in a single order
SELECT MAX(o.pizzas) AS max_pizzas_in_one_delivered_order
FROM orders AS o
JOIN delivered_orders AS d USING (order_id);

-- A7. Per customer: delivered pizzas with at least 1 change vs no changes
SELECT c.customer_id,
       COUNT(*) FILTER (WHERE c.exclusions IS NOT NULL OR c.extras IS NOT NULL) AS with_changes,
       COUNT(*) FILTER (WHERE c.exclusions IS NULL AND c.extras IS NULL)        AS no_changes
FROM customer_orders_clean AS c
JOIN delivered_orders AS d USING (order_id)
GROUP BY c.customer_id
ORDER BY c.customer_id;

-- A8. Delivered pizzas that had both exclusions and extras
SELECT COUNT(*) AS pizzas_with_both
FROM customer_orders_clean AS c
JOIN delivered_orders AS d USING (order_id)
WHERE c.exclusions IS NOT NULL AND c.extras IS NOT NULL;

-- A9. Total volume of pizzas ordered for each hour of the day
SELECT EXTRACT(HOUR FROM order_time)::int AS hour_of_day, COUNT(*) AS pizzas_ordered
FROM customer_orders_clean
GROUP BY 1
ORDER BY 1;

-- A10. Volume of orders for each day of the week (orders, not pizzas)
SELECT TO_CHAR(order_time, 'FMDay') AS day_of_week, COUNT(DISTINCT order_id) AS orders
FROM customer_orders_clean
GROUP BY TO_CHAR(order_time, 'FMDay'), EXTRACT(ISODOW FROM order_time)
ORDER BY EXTRACT(ISODOW FROM order_time);

-- =====================================================================
-- B. Runner and Customer Experience
-- =====================================================================
-- B1. Runners signed up in each 1-week period (week starts 2021-01-01)
SELECT DATE '2021-01-01' + 7 * ((registration_date - DATE '2021-01-01') / 7) AS week_start,
       COUNT(*) AS runners_signed_up
FROM runners
GROUP BY 1
ORDER BY 1;

-- B2. Average minutes for each runner to arrive at HQ to pick up the order (delivered orders, one row per order)
SELECT d.runner_id,
       ROUND(AVG(EXTRACT(EPOCH FROM (d.pickup_time - o.order_time)) / 60), 1) AS avg_minutes_to_pickup
FROM delivered_orders AS d
JOIN orders AS o USING (order_id)
GROUP BY d.runner_id
ORDER BY d.runner_id;

-- B3. Relationship between number of pizzas and preparation time (order to pickup)
SELECT o.pizzas, COUNT(*) AS orders,
       ROUND(AVG(EXTRACT(EPOCH FROM (d.pickup_time - o.order_time)) / 60), 1) AS avg_minutes_to_pickup
FROM delivered_orders AS d
JOIN orders AS o USING (order_id)
GROUP BY o.pizzas
ORDER BY o.pizzas;

SELECT ROUND(CORR(o.pizzas, EXTRACT(EPOCH FROM (d.pickup_time - o.order_time)) / 60)::numeric, 2) AS correlation_pizzas_vs_minutes,
       COUNT(*) AS orders_used
FROM delivered_orders AS d
JOIN orders AS o USING (order_id);

-- B4. Average distance travelled for each customer (delivered orders, one row per order)
SELECT o.customer_id, ROUND(AVG(d.distance_km), 1) AS avg_distance_km
FROM delivered_orders AS d
JOIN orders AS o USING (order_id)
GROUP BY o.customer_id
ORDER BY o.customer_id;

-- B5. Difference between the longest and shortest delivery times (delivery duration, delivered orders)
SELECT MAX(duration_min) AS longest_min, MIN(duration_min) AS shortest_min,
       MAX(duration_min) - MIN(duration_min) AS difference_min
FROM delivered_orders;

-- B6. Average speed (km/h) for each runner for each delivery
SELECT runner_id, order_id, distance_km, duration_min,
       ROUND(distance_km / (duration_min / 60.0), 1) AS speed_kmh
FROM delivered_orders
ORDER BY runner_id, order_id;

-- B7. Successful delivery percentage for each runner
SELECT runner_id,
       COUNT(*) AS assigned_orders,
       COUNT(*) FILTER (WHERE cancellation IS NULL) AS delivered,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancellation IS NULL) / COUNT(*), 0) AS success_pct
FROM runner_orders_clean
GROUP BY runner_id
ORDER BY runner_id;

-- =====================================================================
-- C. Ingredient Optimisation
-- =====================================================================
-- C1. Standard ingredients for each pizza
SELECT n.pizza_name, STRING_AGG(t.topping_name, ', ' ORDER BY t.topping_name) AS standard_ingredients
FROM recipe_toppings AS r
JOIN pizza_names    AS n USING (pizza_id)
JOIN pizza_toppings AS t USING (topping_id)
GROUP BY n.pizza_name
ORDER BY n.pizza_name;

-- C2. Most commonly added extra (all ordered pizzas; ties shown)
WITH counts AS (
  SELECT t.topping_name, COUNT(*) AS times_added, RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
  FROM order_item_changes AS x
  JOIN pizza_toppings AS t USING (topping_id)
  WHERE x.kind = 'extra'
  GROUP BY t.topping_name
)
SELECT topping_name, times_added FROM counts WHERE rnk = 1;

-- C3. Most common exclusion (all ordered pizzas; ties shown)
WITH counts AS (
  SELECT t.topping_name, COUNT(*) AS times_excluded, RANK() OVER (ORDER BY COUNT(*) DESC) AS rnk
  FROM order_item_changes AS x
  JOIN pizza_toppings AS t USING (topping_id)
  WHERE x.kind = 'exclusion'
  GROUP BY t.topping_name
)
SELECT topping_name, times_excluded FROM counts WHERE rnk = 1;

-- C4. An order item description for every record in customer_orders
WITH excl AS (
  SELECT x.order_item_id, STRING_AGG(t.topping_name, ', ' ORDER BY x.pos) AS names
  FROM order_item_changes AS x JOIN pizza_toppings AS t USING (topping_id)
  WHERE x.kind = 'exclusion' GROUP BY x.order_item_id
), extr AS (
  SELECT x.order_item_id, STRING_AGG(t.topping_name, ', ' ORDER BY x.pos) AS names
  FROM order_item_changes AS x JOIN pizza_toppings AS t USING (topping_id)
  WHERE x.kind = 'extra' GROUP BY x.order_item_id
)
SELECT c.order_item_id, c.order_id,
       REPLACE(n.pizza_name, 'Meatlovers', 'Meat Lovers')
         || COALESCE(' - Exclude ' || excl.names, '')
         || COALESCE(' - Extra '   || extr.names, '') AS order_item
FROM customer_orders_clean AS c
JOIN pizza_names AS n USING (pizza_id)
LEFT JOIN excl ON excl.order_item_id = c.order_item_id
LEFT JOIN extr ON extr.order_item_id = c.order_item_id
ORDER BY c.order_item_id;

-- C5. Alphabetical ingredient list per order item, "2x" in front of any ingredient used twice
--     (standard + extra). Excluded ingredients are left out.
WITH per_item AS (
  SELECT order_item_id, topping_id, COUNT(*) AS qty
  FROM order_item_ingredients
  GROUP BY order_item_id, topping_id
)
SELECT c.order_item_id, c.order_id,
       REPLACE(n.pizza_name, 'Meatlovers', 'Meat Lovers') || ': ' ||
       STRING_AGG(CASE WHEN p.qty > 1 THEN p.qty || 'x' ELSE '' END || t.topping_name, ', ' ORDER BY t.topping_name) AS ingredient_list
FROM customer_orders_clean AS c
JOIN pizza_names    AS n USING (pizza_id)
JOIN per_item       AS p ON p.order_item_id = c.order_item_id
JOIN pizza_toppings AS t ON t.topping_id = p.topping_id
GROUP BY c.order_item_id, c.order_id, n.pizza_name
ORDER BY c.order_item_id;

-- C6. Total quantity of each ingredient used in all DELIVERED pizzas, most frequent first
SELECT t.topping_name, COUNT(*) AS total_quantity
FROM order_item_ingredients AS i
JOIN customer_orders_clean  AS c USING (order_item_id)
JOIN delivered_orders       AS d USING (order_id)
JOIN pizza_toppings         AS t USING (topping_id)
GROUP BY t.topping_name
ORDER BY total_quantity DESC, t.topping_name;

-- =====================================================================
-- D. Pricing and Ratings
-- =====================================================================
-- D1. Meat Lovers $12, Vegetarian $10, no charge for changes, no delivery fee: money made so far (delivered pizzas)
SELECT SUM(CASE c.pizza_id WHEN 1 THEN 12 WHEN 2 THEN 10 END) AS revenue
FROM customer_orders_clean AS c
JOIN delivered_orders AS d USING (order_id);

-- D2. Plus $1 for every extra (adding cheese is also $1)
SELECT SUM(CASE c.pizza_id WHEN 1 THEN 12 WHEN 2 THEN 10 END) AS base_revenue,
       COALESCE(SUM(e.n_extras), 0)                            AS extras_charged,
       SUM(CASE c.pizza_id WHEN 1 THEN 12 WHEN 2 THEN 10 END) + COALESCE(SUM(e.n_extras), 0) AS revenue_with_extras
FROM customer_orders_clean AS c
JOIN delivered_orders AS d USING (order_id)
LEFT JOIN (SELECT order_item_id, COUNT(*) AS n_extras FROM order_item_changes WHERE kind = 'extra' GROUP BY order_item_id) AS e
       ON e.order_item_id = c.order_item_id;

-- D3. A ratings table for the new rating system (one rating per successful order, 1 to 5).
--     ILLUSTRATIVE DATA: the exercise asks me to make the ratings up ("insert your own data"). They are NOT real
--     customer feedback, so no business conclusion is drawn from the rating values.
DROP TABLE IF EXISTS runner_ratings;
CREATE TABLE runner_ratings (
  order_id INTEGER PRIMARY KEY,                               -- one rating per order
  rating   SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  rated_at TIMESTAMP NOT NULL DEFAULT now()
);
INSERT INTO runner_ratings (order_id, rating) VALUES
  (1, 5), (2, 4), (3, 5), (4, 3), (5, 4), (7, 5), (8, 2), (10, 5);

-- D4. Everything about each successful delivery in one table
SELECT o.customer_id, d.order_id, d.runner_id, r.rating, o.order_time, d.pickup_time,
       ROUND(EXTRACT(EPOCH FROM (d.pickup_time - o.order_time)) / 60, 1) AS minutes_order_to_pickup,
       d.duration_min AS delivery_duration_min,
       ROUND(d.distance_km / (d.duration_min / 60.0), 1) AS avg_speed_kmh,
       o.pizzas AS total_pizzas
FROM delivered_orders AS d
JOIN orders         AS o USING (order_id)
JOIN runner_ratings AS r USING (order_id)
ORDER BY d.order_id;

-- D5. Fixed prices ($12 / $10), no cost for extras, runner paid $0.30 per km: money left after deliveries
WITH revenue AS (
  SELECT SUM(CASE c.pizza_id WHEN 1 THEN 12 WHEN 2 THEN 10 END) AS revenue
  FROM customer_orders_clean AS c JOIN delivered_orders AS d USING (order_id)
), runner_pay AS (
  SELECT SUM(distance_km) * 0.30 AS pay, SUM(distance_km) AS total_km FROM delivered_orders
)
SELECT revenue.revenue, ROUND(runner_pay.total_km, 1) AS total_km, ROUND(runner_pay.pay, 2) AS runner_pay,
       ROUND(revenue.revenue - runner_pay.pay, 2) AS left_over
FROM revenue, runner_pay;

-- =====================================================================
-- E. Bonus
-- =====================================================================
-- E1. Expanding the range of pizzas: see README. The recipe lives in one comma-separated text column
--     (pizza_recipes.toppings), which cannot be joined, constrained or indexed. A normalised bridge table fixes that:
--       CREATE TABLE pizza_recipe_toppings (pizza_id INT REFERENCES pizza_names, topping_id INT REFERENCES pizza_toppings,
--                                           PRIMARY KEY (pizza_id, topping_id));
--     (the recipe_toppings view above is exactly this table, derived from the text column.)

-- E2. Adding a Supreme pizza with every topping. Done inside a transaction and rolled back, so the data is unchanged.
BEGIN;
INSERT INTO pizza_names   (pizza_id, pizza_name) VALUES (3, 'Supreme');
INSERT INTO pizza_recipes (pizza_id, toppings)
  SELECT 3, STRING_AGG(topping_id::text, ', ' ORDER BY topping_id) FROM pizza_toppings;
SELECT n.pizza_id, n.pizza_name, r.toppings
FROM pizza_names AS n JOIN pizza_recipes AS r USING (pizza_id)
ORDER BY n.pizza_id;
ROLLBACK;
