/*
    Task 2a - Overall authorisation and success rates.

    Run:  dbt compile --select analyses/01_authorisation_rate_overview.sql
    or paste directly into DuckDB against casestudy.duckdb.

    "Authorisation rate" here is approvals / attempts on analysis-eligible rows
    (duplicates and status conflicts excluded). Failures are counted in the
    denominator: from the Fan's point of view a technical failure is a payment
    that did not go through.
*/

with eligible as (

    select * from {{ ref('fct_payments') }}

)

-- Headline
select
    'total' as breakdown,
    'all'   as segment,
    count(*) as attempts,
    sum(case when is_approved then 1 else 0 end) as approvals,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2) as auth_rate_pct,
    round(sum(amount_usd), 2) as attempted_value,
    round(sum(case when not is_approved then amount_usd else 0 end), 2) as declined_value
from eligible

union all

-- By gateway
select 'gateway', gateway, count(*),
    sum(case when is_approved then 1 else 0 end),
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2),
    round(sum(amount_usd), 2),
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
from eligible group by gateway

union all

-- By region
select 'region', region, count(*),
    sum(case when is_approved then 1 else 0 end),
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2),
    round(sum(amount_usd), 2),
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
from eligible group by region

union all

-- By corridor: domestic vs cross-border is a primary authorisation driver
select 'corridor', geo_corridor, count(*),
    sum(case when is_approved then 1 else 0 end),
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2),
    round(sum(amount_usd), 2),
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
from eligible group by geo_corridor

union all

-- By card scheme (Unknown = vendor2's generic 'CC' with no variant, DQ-07)
select 'card_scheme', card_scheme, count(*),
    sum(case when is_approved then 1 else 0 end),
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2),
    round(sum(amount_usd), 2),
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
from eligible group by card_scheme

order by breakdown, attempts desc
