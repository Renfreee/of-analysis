-- Pipeline invariant: cleansing must label rows, never lose them.
-- Fails if the fact table and the raw export disagree on row count.

with source_count as (
    select count(*) as n from {{ source('raw_payments', 'fan_transactions') }}
),
fact_count as (
    select count(*) as n from {{ ref('fct_payment_attempts') }}
)
select
    s.n as source_rows,
    f.n as fact_rows
from source_count s
cross join fact_count f
where s.n <> f.n
