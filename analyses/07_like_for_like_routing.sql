/*
    Task 2 - Can we re-route traffic to improve approval? (summary page 3)

    The providers serve different fans (only vendor2 takes Latin America and
    most of the rest of the world), so the comparison is limited to traffic
    both could carry, holding everything else equal:

        US billing card, fan-initiated, mainstream bank, full address match

    Two comparisons on that segment:
      1. vendor1 vs vendor2                       -> quick win 1: route to vendor1
      2. vendor2's merchant_E vs merchant_C       -> quick win 2: fix merchant_C

    Sizing = the gap in value approval rate x the lower side's attempted value.
    Observational, so treat it as an upper bound to confirm with an A/B test.
*/

with like_for_like as (

    select * from {{ ref('fct_payments') }}
    where payment_group = 'fan-initiated'
      and billing_country = 'US'
      and issuer_segment = 'mainstream'
      and avs_outcome = 'full_match'

),

by_gateway as (

    select
        '1 provider'                                                as comparison,
        gateway                                                     as side,
        *
    from like_for_like

),

by_merchant as (

    select
        '2 vendor2 merchant account'                                as comparison,
        merchant_account                                            as side,
        *
    from like_for_like
    where gateway = 'vendor2'
      and merchant_account in ('merchant_C', 'merchant_E')

)

select
    comparison,
    side,
    count(*)                                                        as payments,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 1)
                                                                    as auth_rate_pct,
    round(sum(amount_usd), 0)                                       as attempted_value_usd,
    round(100.0 * sum(case when is_approved then amount_usd else 0 end) / sum(amount_usd), 1)
                                                                    as value_approval_pct
from (
    select * from by_gateway
    union all by name
    select * from by_merchant
)
group by comparison, side
order by comparison, side
