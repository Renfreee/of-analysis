/*
    Task 2b - Decline / error code analysis on the normalised taxonomy.

    The point of the seed-driven mapping: vendor1's "Insufficient funds",
    vendor2's "INSUFF FUNDS" and vendor2's "Not sufficient funds" are one
    business reason reported three ways. Aggregated raw, the largest single
    recovery opportunity in the book looks like three unrelated mid-size
    problems and is never prioritised.
*/

with eligible_declines as (

    select * from {{ ref('fct_payments') }}
    where not is_approved

),

-- What the decline mix looks like BEFORE normalisation
raw_view as (
    select
        'raw (as supplied)' as view_type,
        decline_reason_raw  as reason,
        count(*)            as declines
    from eligible_declines
    where decline_reason_raw is not null
    group by decline_reason_raw
),

-- ...and AFTER
normalised_view as (
    select
        'normalised'                                    as view_type,
        coalesce(decline_reason_std, 'reason_not_captured') as reason,
        count(*)                                        as declines
    from eligible_declines
    group by coalesce(decline_reason_std, 'reason_not_captured')
)

select
    view_type,
    reason,
    declines,
    round(100.0 * declines / sum(declines) over (partition by view_type), 2) as pct_of_declines,
    row_number() over (partition by view_type order by declines desc) as rank_in_view
from (
    select * from raw_view
    union all
    select * from normalised_view
)
qualify rank_in_view <= 10
order by view_type, declines desc
