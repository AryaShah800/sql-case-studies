# Balanced Tree Clothing Co. (Danny Ma's 8 Week SQL Challenge, case study 7)

**Business question:** what do sales, transactions and products look like for a clothing retailer, and can the monthly report be produced by one reusable script?

**Status:** high level sales, transaction analysis, product analysis, the reporting challenge and the bonus are solved in [`solution.sql`](solution.sql). Expected output: [`expected_output.txt`](expected_output.txt).

## Data
[`schema.sql`](schema.sql) is the Schema SQL from the official DB Fiddle embedded on https://8weeksqlchallenge.com/case-study-7/ (Danny Ma), extracted by script and unchanged: `product_hierarchy` (18 rows), `product_prices` (12), `product_details` (12), `sales` (15,095 lines, 2,500 transactions, 2021-01-01 to 2021-03-30).

## Assumptions
- `discount` is a percentage of the line price; revenue before discount = qty x price; discount amount = qty x price x discount / 100.
- Top selling = most units; transaction-level metrics first collapse sales lines to one row per `txn_id`.
- Reporting challenge: `monthly_report(date)` and `monthly_category_report(date)` are SQL functions; the same call runs January, then February.

## Insights (all from `solution.sql` output)
| Q | Result | Reading |
|---|---|---|
| High level | 45,216 units, revenue 1,289,453 before discount, discount 156,229.14 | Discounts give away 12.1% of pre-discount revenue |
| T1-T2 | 2,500 transactions, 6.04 distinct products each | Baskets are wide: about half of the 12 products appear in a typical basket |
| T3 | Revenue per transaction: p25 375.75, median 509.50, p75 647 | A typical basket is around 500 |
| T4 | Average discount 62.49 per transaction | |
| T5-T6 | Members 60.2% of transactions; average revenue 516.27 (member) vs 515.04 (non-member) | Members are more frequent but do not spend more per basket |
| P1 | Top revenue: Blue Polo Shirt 217,683; Grey Fashion Jacket 209,304; White Tee 152,000 | |
| P2 / P4 | Units per segment are almost equal (11.2k to 11.4k) but revenue ranges from Jeans 208,350 to Shirt 406,143. Mens 714,120 vs Womens 575,333 | Price, not volume, drives the revenue gap |
| P3 / P5 | Most units: Grey Fashion Jacket 3,876 (Jacket, Womens), Navy Oversized Jeans 3,856, Blue Polo 3,819 (Shirt, Mens), Navy Solid Socks 3,792 | |
| P6 | The top product in each segment holds 44% to 58% of that segment's revenue | Each segment leans on one hero product |
| P7-P8 | Shirt 56.87% of Mens; Jacket 63.79% of Womens; Mens 55.38% of revenue, Womens 44.62% | |
| P9 | Penetration is 49.68% to 51.24% for every product (Navy Solid Socks highest) | No product is a niche item; each is in about half of baskets |
| P10 | Most common 3-product combo: White Tee, Grey Fashion Jacket, Teal Button Up in 352 transactions (next: 349, 347) | The top three combos are nearly tied, so no strong bundle signal |
| Report | January: 828 transactions, revenue 420,672; February: 812 transactions, revenue 421,554 (+0.2%) | The same function ran both months with no change; revenue stayed flat while transactions fell |
| Bonus | One recursive CTE rebuilds `product_details`: 12 rows, 0 differences from the shipped table | |

These describe one teaching dataset, not statistical findings.
