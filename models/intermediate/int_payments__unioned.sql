{#
    Single source of truth: both gateway exports on one contract.

    Both staging models are built to an identical column list and unioned by
    column name, so a column added on one side shows up as nulls on the other
    rather than silently landing in the wrong column.
#}

select * from {{ ref('stg_payments__vendor1') }}

union all by name

select * from {{ ref('stg_payments__vendor2') }}
