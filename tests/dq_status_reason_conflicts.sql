{{ config(severity = 'warn') }}

-- DQ-05 (high). The outcome column contradicts the reason / authorisation
-- columns: either an approval carrying a decline reason, or a decline carrying
-- an authorisation code. These rows are excluded from commercial analysis via
-- is_analysis_eligible until the source of truth is agreed with the gateways.

select
    f.transaction_key,
    f.gateway,
    f.gateway_status,
    f.authorisation_code,
    f.decline_reason_raw,
    f.decline_reason_std
from {{ ref('fct_payment_attempts') }} f
join {{ ref('fct_payment_data_quality') }} q using (transaction_key)
where q.dq_status_reason_conflict
