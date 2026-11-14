# SQL Case Studies: Business Problems Solved in PostgreSQL

**Business question:** how do you turn a plain-English business problem into correct, readable SQL, and what does each answer tell the business?

Worked solutions to Danny Ma's [8 Week SQL Challenge](https://8weeksqlchallenge.com/) case studies. Each folder has the setup SQL (where the dataset is small enough to include), the questions, my `solution.sql`, and a one-line business insight for every answer, taken from the query results.

Techniques used: CTEs, window functions (`RANK`, `DENSE_RANK`, `ROW_NUMBER`), `CASE`, date functions, joins and aggregation.

| Case study | Topic | Status |
|---|---|---|
| [Danny's Diner](danny-diner/) | Customer behaviour and loyalty points | Done: 10 questions plus 2 bonus |
| [Pizza Runner](pizza-runner/) | Data cleaning, delivery operations, ingredients and pricing | Done: 30 questions across 5 sections |
| [Foodie-Fi](foodie-fi/) | Subscription plans, churn and upgrades | Done: sections A, B, C (payments); D as discussion |
| [Data Bank](data-bank/) | Nodes, transactions and data allocation | Done: sections A to D; slide not made |

## Data
Small schemas from the case study pages are included where the data is small enough to share (Danny's Diner, Pizza Runner). Foodie-Fi (`foodie-fi/schema.sql`, 2,650 rows) was exported from the official fiddle and is solved. Data Bank (428 KB of rows) is solved locally, but its `schema.sql` is git-ignored: the dataset is Danny Ma's, so get it from the official fiddle (see `data-bank/README.md`). The Pizza Runner ratings table is made up by the exercise's own design.

## Approach
Read the question, state assumptions at the top of `solution.sql`, write the query, check the result by hand on the small data, then write one business insight from the output.

## Key findings
Each case study README lists its insights, one per question (see the table above). They describe tiny teaching datasets and are not statistical findings.

## Dashboard
None. This repo is SQL only.

## Reproduce
Create a PostgreSQL 18 database, run `<case-study>/schema.sql`, then `<case-study>/solution.sql`.

## Conventions

- PostgreSQL 18. Run `schema.sql` first, then `solution.sql`.
- Assumptions are written at the top of each `solution.sql` and README.
- Ties are kept with `RANK` / `DENSE_RANK` rather than hidden by `LIMIT 1`.
- Every number in an insight comes from a query in the same folder. Where a dataset is tiny, the README says so, and nothing is presented as a statistical finding.

## Credit

The case studies, questions and sample data belong to Danny Ma and are used under his request to link back to the original pages: https://8weeksqlchallenge.com/. All queries, assumptions and insights here are my own.
