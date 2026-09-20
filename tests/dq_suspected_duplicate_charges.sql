{{ config(severity = 'warn') }}

-- DQ-06 (high). The same Fan, card BIN, amount and gateway APPROVED more than
-- once: money taken twice. A decline followed by a retry is normal behaviour
-- and is deliberately not counted. $0 card-verification checks are excluded.
-- Still conservative: without timestamps (DQ-01) a legitimate repeat purchase
-- of the same item cannot be told apart from a double-submit.

select
    gateway,
    fan_email_token,
    card_bin,
    amount,
    sum(case when is_approved then 1 else 0 end)  as approvals,
    count(*)                                      as attempts,
    round(sum(case when is_approved then amount_usd else 0 end), 2) as approved_usd
from {{ ref('fct_payment_attempts') }}
where fan_email_token is not null
  and amount > 0
group by gateway, fan_email_token, card_bin, amount
having sum(case when is_approved then 1 else 0 end) > 1
