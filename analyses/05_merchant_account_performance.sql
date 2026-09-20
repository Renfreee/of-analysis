/*
    Task 2e - Approval rate by merchant account.

    Each gateway routes a payment to one of OnlyFans' merchant accounts by the
    card's billing country (US, North America, UK / international, rest of
    world, Brazil in BRL). Account names are only unique within a gateway:
    merchant_A is a different account on each, so the key is gateway + account.

    Split by payment type, because renewals approve far lower than fan-present
    payments and the accounts carry different mixes.

    Finding: on fan-present payments, vendor2's two North America accounts
    carry the same traffic but approve at different rates (merchant_E ~80%,
    merchant_C ~71%). With traffic held equal, account configuration is the
    likely cause, so it is the first thing to check before moving volume
    between gateways.
*/

with eligible as (

    select * from {{ ref('fct_payments') }}
    where payment_group in ('fan-initiated', 'subscription rebill', 'other merchant-initiated')

),

-- the region each account serves, from its most common billing countries
account_region as (

    select
        gateway,
        merchant_account,
        string_agg(billing_country, ', ' order by attempts desc)    as top_billing_countries
    from (
        select
            gateway,
            merchant_account,
            billing_country,
            count(*)                                                as attempts,
            row_number() over (
                partition by gateway, merchant_account
                order by count(*) desc
            )                                                       as country_rank
        from eligible
        where billing_country is not null
        group by gateway, merchant_account, billing_country
    )
    where country_rank <= 3
    group by gateway, merchant_account

)

select
    e.gateway,
    e.merchant_account,
    r.top_billing_countries,
    e.payment_group,
    count(*)                                                        as attempts,
    round(100.0 * sum(case when e.is_approved then 1 else 0 end) / count(*), 1)
                                                                    as auth_rate_pct,
    round(sum(case when not e.is_approved then e.amount_usd else 0 end), 0)
                                                                    as declined_value_usd
from eligible e
left join account_region r
    on  e.gateway = r.gateway
    and e.merchant_account = r.merchant_account
group by e.gateway, e.merchant_account, r.top_billing_countries, e.payment_group
order by e.payment_group, e.gateway, e.merchant_account
