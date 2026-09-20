/*
    Task 2d - What the verification signals are worth.

    Address verification is the strongest single lever visible in this dataset:
    attempts the issuer could not verify authorise roughly half as often as
    attempts that matched.

    Direction of causation is not settled by this data. Unverifiable billing
    data plausibly *causes* declines, but it also correlates with prepaid cards,
    cross-border traffic and weaker checkout data capture, all of which decline
    more anyway. The recommendation is therefore framed as a test, and the
    segment columns below exist so the confound can be inspected rather than
    assumed away.
*/

with eligible as (

    select * from {{ ref('fct_payments') }}

)

select
    coalesce(avs_outcome, 'no_avs_returned')                    as avs_outcome,
    count(*)                                                    as attempts,
    round(100.0 * count(*) / sum(count(*)) over (), 1)          as pct_of_volume,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2)
                                                                as auth_rate_pct,
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
                                                                as declined_value,

    -- confound checks
    round(100.0 * sum(case when geo_corridor = 'cross_border' then 1 else 0 end) / count(*), 1)
                                                                as pct_cross_border,
    round(100.0 * sum(case when gateway = 'vendor2' then 1 else 0 end) / count(*), 1)
                                                                as pct_vendor2,
    round(avg(amount_usd), 2)                                       as avg_attempt_value

from eligible
group by coalesce(avs_outcome, 'no_avs_returned')
order by attempts desc
