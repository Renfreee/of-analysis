{#
    Authorisation rate by market and gateway. The vendor1/vendor2 split columns
    are what expose routing opportunities: markets where the same demand
    performs materially better on one gateway than the other.
#}

select
    region,
    fan_country,
    count(*)                                                    as attempts,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2)
                                                                as auth_rate_pct,
    round(sum(amount_usd), 2)                                       as attempted_value,
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
                                                                as declined_value,

    sum(case when gateway = 'vendor1' then 1 else 0 end)        as attempts_vendor1,
    round(100.0 * sum(case when gateway = 'vendor1' and is_approved then 1 else 0 end)
          / nullif(sum(case when gateway = 'vendor1' then 1 else 0 end), 0), 2)
                                                                as auth_rate_vendor1,

    sum(case when gateway = 'vendor2' then 1 else 0 end)        as attempts_vendor2,
    round(100.0 * sum(case when gateway = 'vendor2' and is_approved then 1 else 0 end)
          / nullif(sum(case when gateway = 'vendor2' then 1 else 0 end), 0), 2)
                                                                as auth_rate_vendor2,

    sum(case when geo_corridor = 'cross_border' then 1 else 0 end) as cross_border_attempts

from {{ ref('fct_payments') }}
group by region, fan_country
order by attempts desc
