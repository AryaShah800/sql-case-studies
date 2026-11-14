# Foodie-Fi (Danny Ma's 8 Week SQL Challenge, case study 3)

**Business question:** how do subscribers move through Foodie-Fi's plans, and where do they churn?

**Status:** sections A, B (11 questions) and C (2020 payments table) are solved and run. Section D (outside the box) is answered as discussion text in `solution.sql`, not computed.

## Data
`schema.sql` was exported by the repo owner from the official case study's DB Fiddle. Checked after loading into PostgreSQL 18: 5 plans, 2,650 subscription rows, 1,000 customers, start dates 2020-01-01 to 2021-04-30. Source and rights: https://8weeksqlchallenge.com/case-study-3/ (Danny Ma).

## How to run
`psql -f schema.sql` then `psql -f solution.sql` (PostgreSQL 18). Assumptions are at the top of `solution.sql`.

## Insights (all from `solution.sql` output)
| Q | Result | Reading |
|---|---|---|
| B1 | 1,000 customers | |
| B2 | 68 to 94 trials a month in 2020 (lowest Feb, highest Mar) | Sign-ups are steady, with no strong seasonality |
| B3 | 2021 events: 8 basic, 60 pro monthly, 63 pro annual, 71 churn | Churn is the most common event in 2021 |
| B4 | 307 customers churned (30.7%) | Nearly one in three customers eventually leaves |
| B5 | 92 churned straight after the trial (9%) | Most churn happens after paying for a plan, not at the trial |
| B6 | Next plan after trial: basic monthly 54.6%, pro monthly 32.5%, churn 9.2%, pro annual 3.7% | Most customers start on the cheapest paid plan |
| B7 | At 2020-12-31: churn 23.6%, pro monthly 32.6%, pro annual 19.5%, basic monthly 22.4%, trial 1.9% | Pro monthly is the largest live plan by year end |
| B8 | 195 customers upgraded to annual in 2020 | |
| B9 | 258 customers reached the annual plan, on average 104.6 days after joining | The upgrade comes about three months in, after trying a monthly plan (B6: only 3.7% start on annual) |
| B10 | 48 of 258 upgrade within 30 days; most of the rest upgrade within 210 days; few after 210 | |
| B11 | 0 downgrades from pro monthly to basic monthly in 2020 | Customers who leave pro do so by churning, not by downgrading |

| C | 2020 payments table: 4,446 payments, 891 paying customers, 101,881.60 total | The example customers (1, 2, 13, 15, 16, 18, 19) reproduce the official sample output exactly (24 rows). The rest rests on my reading of the rules, stated in `solution.sql` |
| D | Discussion answers only | |

These describe a teaching dataset, not statistical findings.
