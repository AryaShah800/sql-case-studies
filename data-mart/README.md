# Data Mart (Danny Ma's 8 Week SQL Challenge, case study 5)

**Business question:** Data Mart switched to sustainable packaging on 2020-06-15. What happened to sales around that date, and which customer groups were hit hardest?

**Status:** sections 1 (cleansing), 2 (exploration), 3 (before and after) and the bonus (4) are solved in [`solution.sql`](solution.sql). The recommendations part of the bonus is only the reading below, not a computed answer. Expected output: [`expected_output.txt`](expected_output.txt).

## Data
[`schema.sql`](schema.sql) is the Schema SQL from the official DB Fiddle embedded on https://8weeksqlchallenge.com/case-study-5/ (Danny Ma), extracted by script and unchanged. One table, `weekly_sales`, 17,117 rows, weekly dates stored as text `D/M/YY`. Source and rights: Danny Ma, see the root README.

## Assumptions
- `week_number` = (day of year - 1) / 7 + 1, as the brief defines it. 2020-06-15 is week 24.
- Text `'null'` in `segment` becomes `unknown` (also in `age_band` and `demographic`).
- Ratios come from totals (sales divided by transactions), never as an average of per-row averages.
- "N weeks before/after" = the N weekly rows before 2020-06-15 and the N from it onward.

## Insights (all from `solution.sql` output)
| Q | Result | Reading |
|---|---|---|
| 1 | `clean_weekly_sales`: 17,117 rows in, 17,117 out, 0 NULLs left | Cleaning keeps every row |
| 2.1 | Every `week_date` is a Monday | Weeks start on Monday |
| 2.2 | Weeks 1-11 and 37-52 never appear | The data covers weeks 12-36 only (late March to early September), so no full-year comparison is possible |
| 2.3 | Transactions 346.4M (2018), 365.6M (2019), 375.8M (2020) | Volume grows 5.5% then 2.8% a year |
| 2.5 | Retail 1,081.9M transactions, Shopify 5.9M | Shopify is about 0.5% of transactions |
| 2.6 | Shopify share of sales rises from 2.08% (Mar 2018) to 3.49% (Aug 2020) | Online is small but grows steadily |
| 2.7 | Unknown demographic falls from 41.63% (2018) to 38.55% (2020); Families 31.99% to 32.73% | Four in ten sales have no demographic, which limits segment analysis |
| 2.8 | Retail: unknown/unknown 40.52%; among known groups Retirees Families 16.73% and Retirees Couples 16.07% | Retirees are the biggest identified buyers |
| 2.9 | 2020 average transaction: Retail 36.56, Shopify 179.03 (averaging the row averages would say 40.64 and 174.87) | `avg_transaction` cannot be averaged; Shopify baskets are about 5x larger |
| 3.1 | 4 weeks: 2,345,878,357 before, 2,318,994,169 after, -1.15% | Sales dipped slightly right after the change |
| 3.2 | 12 weeks: 7,126,273,147 before, 6,973,947,753 after, -2.14% | The dip is slightly larger over 12 weeks |
| 3.3 | Same weeks (12-23 vs 24-35): 2018 +10.54%, 2019 -0.30%, 2020 -2.14% | 2018 grew strongly across these weeks, 2019 was flat, 2020 is the weakest; with one event and three years this is suggestive, not proof |
| 4 | Worst 12-week change: age_band unknown -3.34%, region ASIA -3.26%, customer type Guest -3.00%, platform Retail -2.43%. Growth: Shopify +7.18%, Europe +4.73%, New customers +1.01% | Losses concentrate in unidentified Guest shoppers and in Asia; Shopify and new customers grew |

These describe one teaching dataset, not statistical findings.
