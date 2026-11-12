# SQL Case Studies: Business Problems Solved in PostgreSQL

Worked solutions to Danny Ma's [8 Week SQL Challenge](https://8weeksqlchallenge.com/) case studies. Each folder has the setup SQL (where the dataset is small enough to include), the questions, my `solution.sql`, and a one-line business insight for every answer, taken from the query results.

Techniques used: CTEs, window functions (`RANK`, `DENSE_RANK`, `LAG`, running totals), `CASE`, date functions, joins and aggregation.

| Case study | Topic | Status |
|---|---|---|
| [Danny's Diner](danny-diner/) | Customer behaviour and loyalty points | Done: 10 questions plus 2 bonus |
| [Pizza Runner](pizza-runner/) | Data cleaning, delivery operations, ingredients and pricing | Done: 30 questions across 5 sections |

## Conventions

- PostgreSQL 18. Run `schema.sql` first, then `solution.sql`.
- Assumptions are written at the top of each `solution.sql` and README.
- Ties are kept with `RANK` / `DENSE_RANK` rather than hidden by `LIMIT 1`.
- Every number in an insight comes from a query in the same folder. Where a dataset is tiny, the README says so, and nothing is presented as a statistical finding.

## Credit

The case studies, questions and sample data belong to Danny Ma and are used under his request to link back to the original pages: https://8weeksqlchallenge.com/. All queries, assumptions and insights here are my own.
