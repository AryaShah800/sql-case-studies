# Fresh Segments (Danny Ma's 8 Week SQL Challenge, case study 8)

**Business question:** which audience interests are stable and strong for a digital marketing agency's client, and which come and go?

**Status:** sections A (cleansing), B (interest analysis), C (segment analysis) and D (index analysis) are solved in [`solution.sql`](solution.sql). The open-ended "what would you do" questions are answered as comments beside the evidence query, not computed. Expected output: [`expected_output.txt`](expected_output.txt).

## Data
[`schema.sql`](schema.sql) is the Schema SQL from the official DB Fiddle embedded on https://8weeksqlchallenge.com/case-study-8/ (Danny Ma), extracted by script and unchanged: `interest_metrics` (14,273 rows, 14 months Jul 2018 to Aug 2019), `interest_map` (1,209 interests) and an unused `json_data` table. `month_year` is converted to a date by the script, as the brief asks.

## Assumptions
- Rows with NULL `month_year` (all but one also lack `interest_id`) cannot be placed in time, so they stay in the raw table and are excluded from analysis through a view.
- "Filtered" data = interests present in at least 6 months.
- Average composition = composition / index_value rounded to 2 dp, as the brief defines it.

## Insights (all from `solution.sql` output)
| Q | Result | Reading |
|---|---|---|
| A1-A3 | `month_year` is now a date; 1,194 of 14,273 rows (8.4%) have no month | Excluded from analysis: no month and (but one) no interest |
| A4-A5 | 0 metric ids missing from the map; 7 map ids with no metrics; every map id appears once | The map is a clean lookup, so an inner join is safe |
| A7 | 188 rows have `month_year` before `created_at`, all in the month the interest was created | Valid: the metric month starts before the creation timestamp, not before the interest existed |
| B1 | 480 interests appear in all 14 months | About 40% of interests are fully stable |
| B2-B3 | 90.85% of interests have at least 6 months; dropping the rest removes 400 rows (110 interests) | Cut-off of 6 months |
| B5 | Unique interests per month after filtering: 709 (Jul 2018) to 1,078 (Mar 2019) | Catalogue grows, then dips in mid 2019 |
| C1 | Highest composition: Work Comes First Travelers 21.2 (Dec 2018), Gym Equipment Owners 18.82; lowest: Astrology Enthusiasts 1.88 | |
| C2 | Lowest average ranking: Winter Apparel Shoppers 1.00, Fitness Activity Tracker Users 4.11 | |
| C3-C4 | Most volatile percentile ranking: Techies (sd 30.18, from 86.69 in Jul 2018 to 7.92 in Aug 2019), Entertainment Industry Decision Makers, Oregon Trip Planners | These interests fade quickly, so they are poor long-term targets |
| D1-D2 | Alabama Trip Planners, Luxury Bedding Shoppers and Solar Energy Researchers are in the monthly top 10 in 10 of 14 months | Stable high performers |
| D3 | Average of the top-10 averages: 7.07 (Oct 2018) down to 2.43 (Jun 2019) | The whole top end weakens |
| D4 | Monthly maximum 9.14 (Oct 2018) to 2.73 (Aug 2019); reproduces the sample table on the case page (3-month moving average 7.61 for Sep 2018 down to 2.77 for Aug 2019) | Worth raising with the client |

These describe one teaching dataset, not statistical findings.
