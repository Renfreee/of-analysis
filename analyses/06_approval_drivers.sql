/*
    Task 2 - The biggest drivers of lower approval (summary page 2).

    One row per driver segment, on real payments only. Address check and
    payment size are shown for fan-initiated payments, because rebills approve
    far lower everywhere and would otherwise dominate every split.

    Payment groups are the like-for-like groups built in int_payments__enriched
    (assumptions documented there and in the summary appendix).
*/

with payments as (

    select * from {{ ref('fct_payments') }}
    where payment_group <> 'unknown'

),

segmented as (

    select
        *,
        case
            when payment_group = 'fan-initiated' then 'fan-initiated'
            else 'merchant-initiated'
        end                                                         as initiator_group,
        case
            when avs_outcome in ('full_match', 'zip_only_match')    then '1 full or ZIP match'
            when avs_outcome in ('no_match', 'address_only_match')  then '2 partial or no match'
            else '3 not verified or none returned'
        end                                                         as address_check,
        case
            when amount_usd < 25   then '1 under $25'
            when amount_usd < 100  then '2 $25-$100'
            else '3 $100+'
        end                                                         as payment_size
    from payments

),

drivers as (

    select '1 payment type' as driver, payment_group as segment, is_approved, amount_usd
    from segmented

    union all
    select '2 address check (fan-initiated)', address_check, is_approved, amount_usd
    from segmented where initiator_group = 'fan-initiated'

    union all
    select '3 bank type', initiator_group || ' / ' || issuer_segment, is_approved, amount_usd
    from segmented where issuer_segment <> 'unknown'

    union all
    select '4 payment size (fan-initiated)', payment_size, is_approved, amount_usd
    from segmented where initiator_group = 'fan-initiated'

    union all
    select '5 provider / merchant account', gateway || ' / ' || merchant_account, is_approved, amount_usd
    from segmented

)

select
    driver,
    segment,
    count(*)                                                        as payments,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 1)
                                                                    as auth_rate_pct,
    round(sum(case when not is_approved then amount_usd else 0 end), 0)
                                                                    as declined_value_usd
from drivers
group by driver, segment
order by driver, segment
