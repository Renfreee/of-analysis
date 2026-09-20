/*
    Task 2c - Is the gateway gap real, or just a difference in traffic mix?

    vendor1 authorises at 72.7% and vendor2 at 61.1%, but the two gateways do
    not carry comparable traffic: vendor2 handles all of the Mexico, Brazil and
    Argentina volume, which authorises structurally lower everywhere.

    The honest test is like-for-like. This query holds market constant and
    re-weights vendor2's own country mix at vendor1's country-level rates, so
    the answer is not contaminated by where each gateway's traffic comes from.

    See 07_like_for_like_routing.sql for the stricter comparison used in the
    summary (US card, fan-initiated, mainstream bank, full address match).

    Caveat carried into the recommendation: this is observational, not a
    controlled test. Issuer mix, 3DS configuration, MID setup and risk rules all
    differ between the gateways and none can be isolated in this export. The
    output sizes a hypothesis worth A/B testing, not a guaranteed uplift.
*/

with eligible as (

    select * from {{ ref('fct_payments') }}

),

by_country_gateway as (

    select
        fan_country,
        gateway,
        count(*)                                                as attempts,
        1.0 * sum(case when is_approved then 1 else 0 end) / count(*) as auth_rate,
        1.0 * sum(amount_usd) / count(*)                            as avg_value
    from eligible
    group by fan_country, gateway

),

paired as (

    select
        fan_country,
        max(case when gateway = 'vendor1' then attempts end)    as vendor1_attempts,
        max(case when gateway = 'vendor1' then auth_rate end)   as vendor1_auth_rate,
        max(case when gateway = 'vendor2' then attempts end)    as vendor2_attempts,
        max(case when gateway = 'vendor2' then auth_rate end)   as vendor2_auth_rate,
        max(case when gateway = 'vendor2' then avg_value end)   as vendor2_avg_value
    from by_country_gateway
    group by fan_country

)

-- Per-market comparison where both gateways carry a usable sample
select
    'like_for_like_market' as analysis,
    fan_country,
    vendor1_attempts,
    round(100.0 * vendor1_auth_rate, 2)                         as vendor1_auth_rate_pct,
    vendor2_attempts,
    round(100.0 * vendor2_auth_rate, 2)                         as vendor2_auth_rate_pct,
    round(100.0 * (vendor1_auth_rate - vendor2_auth_rate), 2)   as gap_pp,
    null                                                        as incremental_approvals
from paired
where vendor1_attempts >= 30
  and vendor2_attempts >= 30

union all

-- Portfolio effect: vendor2's volume, held at its own country mix, priced at
-- vendor1's rates. greatest() means a market is only counted where vendor1 is
-- actually better, so any market where vendor2 is better is not counted as a gain.
select
    'mix_adjusted_total',
    'all markets',
    null,
    -- vendor1 benchmark: what vendor2's own country mix would authorise at
    -- vendor1's per-market rates
    round(100.0 * sum(vendor2_attempts * greatest(coalesce(vendor1_auth_rate, vendor2_auth_rate), vendor2_auth_rate))
          / sum(vendor2_attempts), 2),
    sum(vendor2_attempts),
    round(100.0 * sum(vendor2_attempts * vendor2_auth_rate) / sum(vendor2_attempts), 2),
    round(100.0 * sum(vendor2_attempts * (greatest(coalesce(vendor1_auth_rate, vendor2_auth_rate), vendor2_auth_rate) - vendor2_auth_rate))
          / sum(vendor2_attempts), 2),
    round(sum(vendor2_attempts * (greatest(coalesce(vendor1_auth_rate, vendor2_auth_rate), vendor2_auth_rate) - vendor2_auth_rate)), 0)
from paired
where vendor2_attempts is not null

order by analysis, vendor1_attempts desc nulls last
