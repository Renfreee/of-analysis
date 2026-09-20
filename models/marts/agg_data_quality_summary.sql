{#
    The Task 1 issue register, generated from the data rather than hand-written:
    one row per defect class, with the blast radius and the owning team.

    Severity reflects impact on the single-source-of-truth goal:
      critical - blocks reconciliation or core analysis outright
      high     - materially distorts commercial metrics
      medium   - limits a specific analysis or optimisation lever
#}

with attempts as (

    select * from {{ ref('int_payments__quality_flags') }}

),

total as (

    select count(*) as total_rows from attempts

),

issues as (

    select 'DQ-01' as issue_code,
           'No date component on any timestamp' as issue,
           'critical' as severity,
           'Data Engineering' as owner,
           'Every creation_date_ts is an MM:SS fragment. Date and hour are absent, so no trend, cohort, retry-window or settlement-period analysis is possible.' as impact,
           sum(case when dq_missing_timestamp then 1 else 0 end) as rows_affected
    from attempts

    union all
    select 'DQ-02',
           'psp_reference reused across unrelated Fans',
           'critical',
           'Data Engineering',
           'The gateway reference is not unique: the same value appears on transactions with different Fans and amounts, so it cannot serve as a join or reconciliation key.',
           sum(case when dq_psp_reference_collision then 1 else 0 end)
    from attempts

    union all
    select 'DQ-03',
           'Decline reason written into the authorisation_code column',
           'high',
           'Data Engineering',
           'On vendor1 the authorisation_code field repeats the decline text and is empty on approvals, so the column means something different per gateway.',
           sum(case when dq_auth_code_contamination then 1 else 0 end)
    from attempts

    union all
    select 'DQ-04',
           'Approved transactions with no authorisation code',
           'high',
           'Data Engineering',
           'Approvals cannot be evidenced or matched to settlement without a retrievable authorisation token.',
           sum(case when dq_approved_without_auth_code then 1 else 0 end)
    from attempts

    union all
    select 'DQ-16',
           'Placeholder value supplied as authorisation code',
           'high',
           'Data Engineering',
           'vendor2 returns 00000 / 000000 in the authorisation_code field on approvals, declines and failures alike. Taken at face value these fabricate both approval evidence and status conflicts.',
           sum(case when dq_sentinel_auth_code then 1 else 0 end)
    from attempts

    union all
    select 'DQ-05',
           'Outcome conflicts with reason or auth code',
           'high',
           'Payments Ops',
           'Rows where the status column and the reason/authorisation columns disagree; excluded from commercial analysis.',
           sum(case when dq_status_reason_conflict then 1 else 0 end)
    from attempts

    union all
    select 'DQ-06',
           'Suspected duplicate charges',
           'high',
           'Payments Ops',
           'Same Fan, card BIN, amount and gateway APPROVED more than once. Declines followed by retries are not counted. Conservative: without timestamps a double-submit cannot be told apart from a genuine repeat purchase.',
           sum(case when dq_suspected_duplicate_charge then 1 else 0 end)
    from attempts

    union all
    select 'DQ-07',
           'Card scheme unattributable',
           'high',
           'Data Engineering',
           'vendor2 sends the generic literal CC as payment_method; scheme is only recoverable from a variant field that is frequently empty. Scheme-level routing analysis is impossible for these rows.',
           sum(case when dq_missing_card_scheme then 1 else 0 end)
    from attempts

    union all
    select 'DQ-08',
           'CIT/MIT initiator missing or ambiguous',
           'high',
           'Data Engineering',
           'The two gateways use incompatible taxonomies (blank/MIT vs C/M) and neither is documented, blocking network-token and retry strategy by initiator type.',
           sum(case when dq_missing_initiator then 1 else 0 end)
    from attempts

    union all
    select 'DQ-09',
           'No stable Fan identifier',
           'critical',
           'Data Engineering',
           'vendor2 omits shopper_reference entirely, so a Fan cannot be followed across gateways and lifetime or retry behaviour cannot be measured.',
           sum(case when dq_missing_fan_reference then 1 else 0 end)
    from attempts

    union all
    select 'DQ-10',
           'Address verification result missing',
           'medium',
           'Payments Ops',
           'AVS is absent on these rows. Missing AVS correlates with the lowest observed authorisation rates in this dataset.',
           sum(case when dq_missing_avs then 1 else 0 end)
    from attempts

    union all
    select 'DQ-11',
           'Issuer country missing',
           'medium',
           'Data Engineering',
           'Without issuer country the domestic versus cross-border corridor cannot be determined, which is a primary authorisation-rate driver.',
           sum(case when dq_missing_issuer_country then 1 else 0 end)
    from attempts

    union all
    select 'DQ-12',
           'Declined with no reason captured',
           'medium',
           'Data Engineering',
           'Declines with an empty reason field cannot be categorised or recovered.',
           sum(case when dq_decline_without_reason then 1 else 0 end)
    from attempts

    union all
    select 'DQ-13',
           'Non-reporting currency with no FX rate',
           'medium',
           'Finance',
           'BRL transactions carry no FX rate or settlement-currency amount. Converted to USD at a PROXY rate (dbt var fx_brl_per_usd) so totals are comparable; replace with a sourced July 2026 rate before reconciling.',
           sum(case when dq_non_reporting_currency then 1 else 0 end)
    from attempts

    union all
    select 'DQ-14',
           'Card last 4 fully masked',
           'medium',
           'Data Engineering',
           'Both gateways mask the field entirely (**** / ****************), so card-level duplicate and retry detection is not possible.',
           sum(case when not has_usable_card_last_4 then 1 else 0 end)
    from attempts

    union all
    select 'DQ-17',
           '$0 card-verification checks mixed into the payment log',
           'high',
           'Data Engineering',
           'vendor2 sends zero-amount verification checks in the same feed as purchases, with no field marking them. Left in, they add easy approvals and flatter vendor2''s authorisation rate by about 3 points.',
           sum(case when dq_unlabelled_card_verification then 1 else 0 end)
    from attempts

    union all
    select 'DQ-18',
           'Issuer names spelled inconsistently',
           'medium',
           'Data Engineering',
           'The same issuer appears in different casing and punctuation across gateways (SUTTON BANK / Sutton Bank), splitting issuer-level analysis. Normalised in issuer_name_std; word-level variants (NA vs National Association) remain.',
           sum(case when dq_issuer_name_variant then 1 else 0 end)
    from attempts

    union all
    select 'DQ-19',
           'Placeholder value in place of a Fan reference',
           'high',
           'Data Engineering',
           'vendor1 sends shopper_reference = 5 for 1,167 unrelated Fans, all merchant-initiated. The field looks populated but is not an identifier, and the segment it marks authorises at roughly a third of the rate of the rest of vendor1.',
           sum(case when dq_placeholder_fan_reference then 1 else 0 end)
    from attempts

    union all
    select 'DQ-20',
           'Network transaction ID truncated to scientific notation',
           'high',
           'Data Engineering',
           'Numeric scheme_reference values arrive as 7.64917E+14: trailing digits are lost, so the ID cannot link a merchant-initiated charge back to its original authorisation. Same spreadsheet-export cause as DQ-01.',
           sum(case when dq_scheme_ref_precision_lost then 1 else 0 end)
    from attempts

    union all
    select 'DQ-21',
           'Shopper IP is a shared server address',
           'medium',
           'Data Engineering',
           'On vendor2, 95% of rows carry one of three IPs, each seen across 70+ countries. These are server or proxy addresses, so IP cannot be used for fraud or geolocation on this gateway.',
           sum(case when dq_shared_server_ip then 1 else 0 end)
    from attempts

    union all
    select 'DQ-22',
           'Invalid card BIN',
           'medium',
           'Data Engineering',
           'Card BIN supplied as 0, -1 or 000000. Nulled in the clean layer.',
           sum(case when dq_invalid_card_bin then 1 else 0 end)
    from attempts

    union all
    select 'DQ-15',
           'Permanently empty columns',
           'medium',
           'Data Engineering',
           'payment_account_reference, risk_scoring, issuer_city and billing_house_number_name are empty on every row across both gateways. risk_scoring in particular blocks any risk-based routing.',
           (select count(*) from attempts)

)

select
    i.issue_code,
    i.issue,
    i.severity,
    i.owner,
    i.impact,
    i.rows_affected,
    t.total_rows,
    round(100.0 * i.rows_affected / nullif(t.total_rows, 0), 1) as pct_of_rows
from issues i
cross join total t
where i.rows_affected > 0
order by
    case i.severity when 'critical' then 1 when 'high' then 2 else 3 end,
    i.rows_affected desc
