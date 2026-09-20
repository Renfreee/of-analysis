{#
    Decline mix on the normalised taxonomy, so vendor1's "Insufficient funds",
    vendor2's "INSUFF FUNDS" and "Not sufficient funds" aggregate as one reason
    instead of three. Sized by both count and value, and split by whether the
    decline is recoverable through a retry or routing lever.
#}

with declines as (

    select * from {{ ref('fct_payments') }}
    where not is_approved

)

select
    -- declines the gateway returned with no reason at all (DQ-12) stay visible
    -- as their own bucket rather than collapsing into a null row
    coalesce(decline_category, 'data_quality_anomaly')           as decline_category,
    coalesce(decline_reason_std, 'reason_not_captured')          as decline_reason_std,
    coalesce(is_retryable_decline, false)                        as is_retryable_decline,
    coalesce(recovery_lever, 'Pipeline fix - capture decline reason') as recovery_lever,
    count(*)                                                    as declines,
    round(100.0 * count(*) / sum(count(*)) over (), 2)          as pct_of_all_declines,
    round(sum(amount_usd), 2)                                       as declined_value,
    sum(case when gateway = 'vendor1' then 1 else 0 end)        as declines_vendor1,
    sum(case when gateway = 'vendor2' then 1 else 0 end)        as declines_vendor2,
    count(distinct fan_email_token)                             as distinct_fans

from declines
group by 1, 2, 3, 4
order by declines desc
