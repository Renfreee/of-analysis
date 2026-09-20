{#
    Headline authorisation performance by gateway, on analysis-eligible rows
    only (duplicates and status conflicts excluded).
#}

select
    gateway,
    count(*)                                                    as attempts,
    sum(case when is_approved then 1 else 0 end)                as approvals,
    round(100.0 * sum(case when is_approved then 1 else 0 end) / count(*), 2)
                                                                as auth_rate_pct,
    sum(case when gateway_status = 'Declined' then 1 else 0 end) as declines,
    sum(case when gateway_status = 'Failed' then 1 else 0 end)   as failures,
    round(sum(amount_usd), 2)                                       as attempted_value,
    round(sum(case when is_approved then amount_usd else 0 end), 2)  as approved_value,
    round(sum(case when not is_approved then amount_usd else 0 end), 2)
                                                                as declined_value,
    round(sum(case when not is_approved and is_retryable_decline then amount_usd else 0 end), 2)
                                                                as recoverable_declined_value,
    round(avg(amount_usd), 2)                                       as avg_attempt_value

from {{ ref('fct_payments') }}
group by gateway
order by gateway
