# Case Study 1: Danny's Diner

**Source:** [8 Week SQL Challenge, Case Study #1](https://8weeksqlchallenge.com/case-study-1/) by Danny Ma. The questions are quoted from that page; all queries, assumptions and insights are my own.

**Business problem:** a small restaurant wants to know its customers' visiting patterns, spending and favourite menu items, to decide whether to expand its loyalty programme.

**Data:** 3 tables, `sales` (15 rows), `menu` (3 items), `members` (2 customers). Setup in [`schema.sql`](schema.sql), queries in [`solution.sql`](solution.sql). PostgreSQL 18.

**Assumptions** (stated because the data has no time of day):
- Items bought on the same day are treated as bought together.
- A purchase on the join date counts as a member purchase.
- Ties are kept with `RANK` / `DENSE_RANK` instead of being hidden by `LIMIT 1`.

**Limit:** with 15 rows these are descriptions of the sample, not statistical findings.

## Answers and insights

| # | Question | Answer | Business insight |
|---|---|---|---|
| 1 | Total amount each customer spent | A 76, B 74, C 36 | A and B generate about 80% of revenue (150 of 186); C is a small spender. |
| 2 | Days each customer visited | A 4, B 6, C 2 | B visits most but spends less per visit (74 / 6 = 12.33) than A (76 / 4 = 19.00), so A is the higher-value visitor. |
| 3 | First item purchased | A: curry and sushi (same day), B: curry, C: ramen | Curry is the entry dish for two of three customers. |
| 4 | Most purchased item | Ramen, 8 of 15 purchases | Ramen is more than half of all purchases and twice the next item (curry, 4). |
| 5 | Most popular item per customer | A ramen (3), C ramen (3), B tied at 2 each for curry, ramen and sushi | Ramen is the favourite for two of three customers; B shows no preference. |
| 6 | First item after becoming a member | A curry, B sushi | After joining, customers did not go straight to the best seller. |
| 7 | Item just before becoming a member | A curry and sushi, B sushi | Both members were already buying sushi or curry before joining. |
| 8 | Items and spend before becoming a member | A 2 items, 25; B 3 items, 40 | B spent more before joining than A did. |
| 9 | Points (10 per $1, sushi 2x) | A 860, B 940, C 360 | B leads on points despite lower spend, because two of B's six purchases were sushi. |
| 10 | Points for A and B at end of January (2x on everything in the first week after joining) | A 1,370, B 820 | The double-points week paid off for A, who made 4 purchases in it, but little for B, who made 1. |
| Bonus 1 | Join all the things | see `solution.sql` | A flat table of every purchase with a member flag, ready for a dashboard. |
| Bonus 2 | Rank all the things | see `solution.sql` | Member purchases are ranked by date; non-member rows are left NULL. |

**Observation across questions:** C is the only customer who never joined, and bought only ramen (3 orders, 36 spent). With a sample this small, that is a lead worth testing, not a conclusion.

## Checks

- Queries run without error on PostgreSQL 18.4.
- Q9 and Q10 were hand-calculated from the raw rows and match (A: 200 + 150 + 300 + 240 + 480 + 150 = 1,370; B: 500 + 200 + 120 = 820).
- Row counts after loading: 15, 3, 2, matching the page.
