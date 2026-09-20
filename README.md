# Fan Payments: Data Analyst Case Study

Analysis of 10,000 Fan payment transactions from two gateways (July 2026): a data integrity audit (Task 1) and an authorisation-rate analysis (Task 2).

Built as a dbt project on DuckDB, so the whole pipeline runs locally from the original CSV. `dbt build` reproduces every number in the executive summary.

## Deliverables

| | |
|---|---|
| **Executive summary** (5 slides + 1 appendix slide, 16:9) | `docs/executive_summary.pdf` (source: `docs/executive_summary.html`) |
| **Data cleaning log** (Task 1) | [`docs/data_cleaning_log.md`](docs/data_cleaning_log.md) |
| **Cleaning and modelling code** | `models/`, `seeds/`, `macros/` |
| **Analysis queries** (Task 2) | `analyses/`: `06` and `07` produce the numbers on summary pages 2 and 3 |
| **Analysis results** | `analyses/outputs/*.csv`, one per query. Refresh with `python analyses/export_outputs.py` |
| **Data quality tests** | `tests/` and `models/**/*.yml` |
| **Metric definitions** | `models/semantic/` |
| **Column definitions** | [`models/_column_definitions.md`](models/_column_definitions.md). dbt docs blocks, written once and referenced from the sources, the staging models and the marts. `dbt docs generate && dbt docs serve` renders them |

## Viewing it

The executive summary is a PDF, so it opens anywhere. GitHub shows `.html` files
as source rather than as pages, so to read the HTML version of the summary,
clone the repo and open `docs/executive_summary.html`, or enable GitHub Pages
(Settings → Pages → deploy from `main`, folder `/docs`), which serves the
deliverables from `https://renfreee.github.io/of-analysis/`.

## Running it

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install dbt-duckdb

export DBT_PROFILES_DIR=.
dbt build
```

Expected result: `PASS=63 WARN=4 ERROR=0`.

The four warnings are intentional. They are known data defects (missing timestamps, reused payment references, one status conflict, duplicate charges), kept at warn level so the build stays green while the defects stay visible. A new *failure* means the source data has changed.

Then query the results directly:

```bash
duckdb casestudy.duckdb
```
```sql
select * from main_marts.fct_payments;
select * from main_marts.agg_gateway_performance;
select * from main_marts.agg_data_quality_summary;
```

## How it fits together

```
data/raw/Casestudy_Sept2026.csv
        │
        ▼
staging/       base_payments__keyed          surrogate key (psp_reference is not unique)
               stg_payments__vendor1         each gateway mapped onto the same columns,
               stg_payments__vendor2         gateway-specific defects handled explicitly
        │
        ▼
intermediate/  int_payments__unioned         both gateways in one table
               int_payments__enriched        decline/AVS mappings, USD amounts, payment type
               int_payments__quality_flags   22 row-level data quality flags
        │
        ▼
marts/         fct_payment_attempts          every attempt (10,000): reconciles to the provider
               fct_payments                  the analysis base (8,632): query this one
               fct_payment_data_quality      the same rows with the 22 defect flags
               agg_gateway_performance       ─┐
               agg_decline_analysis           ├─ the numbers behind the summary
               agg_regional_performance      ─┘
               agg_data_quality_summary      the Task 1 issue register
```

**Cleaning labels rows, it never deletes them.** Finance needs the full attempt log to reconcile, so all 10,000 rows reach `fct_payment_attempts`. It carries only the two flags analysis filters on (`is_payment`, `is_analysis_eligible`), and `fct_payments` applies those filters so analysts never have to. The 22 individual defect flags sit in `fct_payment_data_quality`, joined on `transaction_key`. `tests/assert_payments_reconcile.sql` fails the build if the three tables stop adding up. Analysis filters to 8,632 real payments. The 1,366 $0 card-verification checks are kept but reported separately. `tests/assert_row_count_conserved.sql` fails the build if any row is lost.

**Messy values are mapped in `seeds/`, not buried in CASE statements.** The gateways report the same decline in several spellings (`Insufficient funds`, `INSUFF FUNDS`, `Not sufficient funds`). `seeds/decline_reason_map.csv` maps all 77 raw codes to one list of reasons, each with a category and a recommended action. A test fails the build if a new code appears that the map doesn't cover.

## Notes on method

- **Authorisation rate** = approvals / attempts on real payments. Technical failures count as attempts: the Fan still didn't pay.
- **$0 card checks are not payments.** Counting them made Gateway 2 look cheaper and more successful than it is.
- **BRL is converted at a proxy rate of 5.50 per USD.** The file has no FX rate. It affects 87 rows (0.9%) and doesn't change any conclusion. It's set once as a dbt variable in `dbt_project.yml`.
- **Payments are grouped like for like across gateways** (`payment_group`): fan-initiated (including first subscription charges), subscription rebill, other merchant-initiated. The two gateways label these differently; the assumptions are commented in `int_payments__enriched` and listed in the summary appendix.
- **The gateway comparison is like-for-like.** `analyses/07` compares the gateways on the traffic both carry: US card, fan-initiated, mainstream bank, full address match. It's observational, so it's framed as something to A/B test.
- **The `00000` correction.** Gateway 2 uses `00000` as a placeholder authorisation code. Taken at face value it creates 47 "approved but declined" conflicts. Treated as blank, only **one** is real.
