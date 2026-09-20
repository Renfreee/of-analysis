{{ config(severity = 'warn') }}

-- DQ-02 (critical). The gateway reference is not a primary key: the same
-- psp_reference is issued to transactions belonging to different Fans with
-- different amounts. Warn-level by design - this is a documented defect in the
-- supplied export, and the test exists to quantify it and to detect any change
-- in its scale on a future load.

select
    psp_reference,
    count(*)                                as colliding_rows,
    count(distinct fan_email_token)         as distinct_fans,
    count(distinct amount)                  as distinct_amounts,
    string_agg(distinct gateway, ', ')      as gateways
from {{ ref('fct_payment_attempts') }}
group by psp_reference
having count(distinct coalesce(fan_email_token, '~')) > 1
