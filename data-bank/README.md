# Data Bank (Danny Ma's 8 Week SQL Challenge, case study 4)

**Business question:** how are customers spread across nodes, how do their balances move, and how much cloud storage would each allocation rule need?

**Status:** sections A, B, C and D are solved and run on PostgreSQL 18. The "Extension Request" (headline insights and a one-page slide) is covered only by the insights below; no slide was made.

## Data
`schema.sql` is the Schema SQL from the official DB Fiddle embedded on https://8weeksqlchallenge.com/case-study-4/ (Danny Ma), extracted by script. Checked after loading: 5 regions, 3,500 `customer_nodes` rows, 5,868 `customer_transactions` rows, 500 customers, transaction dates 2020-01-01 to 2020-04-28.

Not committed: `schema.sql` is git-ignored because the 428 KB dataset belongs to Danny Ma. To reproduce, open the case study page, click "Edit on DB Fiddle" and copy the Schema SQL panel into `data-bank/schema.sql`.

## How to run
`psql -f schema.sql` then `psql -f solution.sql`. Assumptions (floored allocations, `9999-12-31` end dates, sign of transactions) are at the top of `solution.sql`.

## Insights (from `solution.sql` output; teaching dataset, not statistical findings)
| Q | Result | Reading |
|---|---|---|
| A1-A2 | 5 node ids; every region uses all 5 | Nodes are shared labels, not region-specific branches |
| A3 | Customers per region: Australia 110, America 105, Africa 102, Asia 95, Europe 88 | Fairly even spread |
| A4-A5 | Average 14.6 days between reallocations; median 15, 80th percentile 23 to 24, 95th percentile 28 in every region | Reallocation timing looks the same everywhere |
| B1 | Deposits 2,671 (1,359,168), purchases 1,617 (806,537), withdrawals 1,580 (793,003) | Outflows (1,599,540) exceed deposits by 240,372 over the period |
| B2 | 5.34 deposits per customer on average, totalling 2,718.34 (508.86 per deposit) | |
| B3 | Customers with 2+ deposits and a purchase or withdrawal: Jan 168, Feb 181, Mar 192, Apr 70 | April is partial (data ends 2020-04-28) |
| B4-B5 | 37.0% of customers have at least one month with a closing balance more than 5% higher than the month before; 31.2% of such customer-months | |
| C | Average per-customer minimum / average / maximum running balance: -1,235 / -86 / 1,213 | Many customers go negative, so allocation rules matter |
| C | Monthly data required (Feb / Mar / Apr): Option 1 (previous month-end) 235,595 / 261,508 / 260,971; Option 2 (previous 30-day average) 232,596 / 244,605 / 257,327; Option 3 (peak in month) 410,126 / 399,620 / 314,374 | The real-time option needs far more storage than the other two |
| D | 6% simple daily interest adds about 682 to 1,366 a month; data required with interest (Jan to Apr): 236,277 / 262,755 / 262,337 / 266,145 | Interest is small next to balances |

Option definitions and flooring negatives at zero are my assumptions, stated in `solution.sql`; other readings of the options give different totals.
