{#
    Grain: one row per authorisation attempt, keyed to fct_payment_attempts.

    The data quality side of the fact table: every defect flag found in the
    export, kept out of the analyst-facing model so that table stays readable.
    Join on transaction_key when triaging issues with engineering or the
    providers; agg_data_quality_summary is the aggregated version.
#}

select
    transaction_key,
    gateway,
    merchant_account,
    psp_reference,

    dq_missing_timestamp,
    dq_psp_reference_collision,
    dq_exact_duplicate_row,
    dq_suspected_duplicate_charge,
    dq_duplicate_charge_extra,
    dq_status_reason_conflict,
    dq_auth_code_contamination,
    dq_sentinel_auth_code,
    dq_approved_without_auth_code,
    dq_missing_card_scheme,
    dq_missing_initiator,
    dq_missing_avs,
    dq_decline_without_reason,
    dq_non_reporting_currency,
    dq_missing_fan_reference,
    dq_missing_issuer_country,
    dq_unlabelled_card_verification,
    dq_issuer_name_variant,
    dq_placeholder_fan_reference,
    dq_scheme_ref_precision_lost,
    dq_shared_server_ip,
    dq_invalid_card_bin,
    dq_issue_count,

    is_payment,
    is_analysis_eligible

from {{ ref('int_payments__quality_flags') }}
