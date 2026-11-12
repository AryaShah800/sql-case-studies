# Case Study 2: Pizza Runner

**Source:** [8 Week SQL Challenge, Case Study #2](https://8weeksqlchallenge.com/case-study-2/) by Danny Ma. The questions follow that page; all queries, assumptions and insights are my own.

**Business problem:** a pizza delivery startup wants to understand its pizza demand, its runners' performance, ingredient usage and basic profitability.

**Data:** 6 tables with 14 order lines, 10 runner orders and 4 runners, so these are descriptions of a tiny sample, not statistical findings. Setup in [`schema.sql`](schema.sql), all 30 queries in [`solution.sql`](solution.sql). PostgreSQL 18.

## The data was dirty, so I cleaned it first

| Problem | Where | Fix |
|---|---|---|
| Missing values written three ways: `''`, text `'null'`, real `NULL` | `exclusions`, `extras`, `cancellation` | one `NULLIF` rule, in a view |
| Units inside numbers: `20km`, `23.4 km`, `32 minutes`, `25mins`, `15 minute` | `distance`, `duration` | regex strips non-digits, cast to numeric |
| Timestamps stored as text, with `'null'` | `pickup_time` | cast to `timestamp` |
| Comma-separated lists in one column | `exclusions`, `extras`, `pizza_recipes.toppings` | `string_to_table ... WITH ORDINALITY` into one row per topping |
| Identical duplicate rows (order 4) | `customer_orders` | kept: they are separate pizzas, given an `order_item_id` |

The raw tables are untouched. Cleaning lives in views at the top of `solution.sql`.

**Assumptions:** delivered means no cancellation (orders 6 and 9 are cancelled); order and customer questions count each order once; revenue and delivery metrics use delivered orders only; ties are kept.

## A. Pizza metrics

| # | Answer | Business insight |
|---|---|---|
| 1 | 14 pizzas ordered | |
| 2 | 10 unique orders | Orders average 1.4 pizzas. |
| 3 | Runner 1: 4, runner 2: 3, runner 3: 1 delivered | Runner 1 carries half of the deliveries (4 of 8). |
| 4 | 9 Meatlovers, 3 Vegetarian delivered | Meat Lovers is 75% of delivered pizzas. |
| 5 | Meatlovers/Vegetarian per customer: 101: 2/1, 102: 2/1, 103: 3/1, 104: 3/0, 105: 0/1 | 104 only orders Meat Lovers and 105 only Vegetarian, so both menu items have loyal buyers. |
| 6 | 3 pizzas in the largest delivered order | Capacity planning should allow for 3-pizza orders. |
| 7 | With changes / none: 101: 0/2, 102: 0/3, 103: 3/0, 104: 2/1, 105: 1/0 | Customer 103 changes every pizza, while 101 and 102 never do: customisation is customer-specific. |
| 8 | 1 delivered pizza had both exclusions and extras | Combined changes are rare. |
| 9 | Peak hours: 13, 18, 21 and 23 (3 pizzas each) | Demand clusters around lunch, early evening and late night. |
| 10 | Wednesday 5 orders, Thursday 2, Saturday 2, Friday 1 | Wednesday is the busiest day, but the data covers only 11 days. |

## B. Runner and customer experience

| # | Answer | Business insight |
|---|---|---|
| 1 | Sign-ups by week: 1 Jan: 2, 8 Jan: 1, 15 Jan: 1 | Recruitment is steady at about 1 to 2 per week. |
| 2 | Avg minutes from order to pickup: runner 1 14.3, runner 2 20.0, runner 3 10.5 | This includes kitchen preparation, not only the runner's travel, so it is not purely a runner measure. |
| 3 | 1 pizza: 12.4 min, 2: 18.4, 3: 29.3; correlation 0.84 across 8 orders | More pizzas means a longer wait, so large orders need prep-time quotes. The sample is only 8 orders. |
| 4 | Avg distance: 101: 20.0 km, 102: 18.4, 103: 23.4, 104: 10.0, 105: 25.0 | Delivery distances span 10 to 25 km, so distance is a major driver of delivery time and runner cost (see D5). |
| 5 | Longest 40 min, shortest 10 min, difference 30 min | Delivery time varies by a factor of four. |
| 6 | Speeds range from 35.1 to 93.6 km/h; runner 2 rises from 35.1 to 60.0 to 93.6 | 93.6 km/h (23.4 km in 15 minutes) is implausible for a courier, so distance or duration probably contains data-entry errors that should be checked before runners are compared. |
| 7 | Success: runner 1 100%, runner 2 75%, runner 3 50% | Each runner has only 2 to 4 orders, so these percentages are too noisy to rank runners on. |

## C. Ingredient optimisation

| # | Answer | Business insight |
|---|---|---|
| 1 | Meat Lovers: BBQ Sauce, Bacon, Beef, Cheese, Chicken, Mushrooms, Pepperoni, Salami. Vegetarian: Cheese, Mushrooms, Onions, Peppers, Tomato Sauce, Tomatoes | Cheese and Mushrooms are on both pizzas. |
| 2 | Bacon is the most common extra (4 times) | Bacon is the clearest upsell candidate. |
| 3 | Cheese is the most common exclusion (4 times) | Cheese is excluded as often as bacon is added, so a no-cheese option is worth offering. |
| 4 | Order item descriptions for all 14 rows, for example "Meat Lovers - Exclude Cheese - Extra Bacon, Chicken" | Readable strings are ready for kitchen tickets. |
| 5 | Ingredient lists with `2x` for doubled toppings, for example order 9: "BBQ Sauce, 2xBacon, Beef, 2xChicken, Mushrooms, Pepperoni, Salami" | The same expansion drives stock use. |
| 6 | Delivered-pizza ingredient use: Bacon 12, Mushrooms 11, Cheese 10, then Beef, Chicken, Pepperoni and Salami 9 each | Bacon is the most-used ingredient, mainly because it is on every Meat Lovers plus 3 extras. |

## D. Pricing and ratings

| # | Answer | Business insight |
|---|---|---|
| 1 | $138 from delivered pizzas (9 x $12 + 3 x $10) | Cancelled orders earn nothing. |
| 2 | $4 of extras, so $142 | Extras add about 3% to revenue. |
| 3 | `runner_ratings` table: one rating per order, `CHECK (rating BETWEEN 1 AND 5)`, primary key on `order_id` | **The ratings are made up**, as the exercise instructs, so I draw no conclusions from their values. |
| 4 | One table joining customer, runner, rating, times, speed and pizza count for each successful delivery | This is the base table for a runner scorecard. |
| 5 | $138 revenue, 145.2 km at $0.30 = $43.56 runner pay, **$94.44 left over** | Runner pay takes about 32% of revenue, so delivery distance is the main margin lever. |

## E. Bonus

1. **Expanding the menu.** Recipes are stored as a comma-separated text column, which cannot be joined, constrained or indexed. A bridge table `pizza_recipe_toppings (pizza_id, topping_id)` with foreign keys fixes that. The `recipe_toppings` view in `solution.sql` already produces that shape.
2. **Adding a Supreme pizza** takes two inserts (`pizza_names` and `pizza_recipes`). I run it inside a transaction and roll it back, so the data is unchanged.

## Checks

- Row counts after loading match the published fiddle: 4, 14, 10, 2, 2, 12.
- All 30 queries run on PostgreSQL 18.4 without error.
- Hand-checked: delivered pizzas (9 + 3), revenue ($138), extras ($4), distance (145.2 km), runner pay ($43.56), and the day-of-week mapping.
