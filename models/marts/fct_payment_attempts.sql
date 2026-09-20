{#
    Grain: one row per authorisation attempt, across both gateways.

    The analyst-facing table: every source row survives and carries a stable
    key, plus the two flags analysis filters on - is_payment (a $0 card check
    is not a payment) and is_analysis_eligible (duplicates and unresolved
    conflicts excluded).

    The 22 individual data quality flags live in fct_payment_data_quality,
    joined on transaction_key, so this table stays readable.
#}

select
    transaction_key,
    gateway,
    merchant_account,
    psp_reference,
    scheme_reference,

    creation_clock_raw,
    creation_seconds_into_hour,
    created_at,
    has_resolvable_timestamp,
    source_timezone,

    currency,
    amount,
    amount_usd,
    fx_basis,
    is_reporting_currency,
    amount_band,
    creator_share_usd,
    reporting_date,
    transaction_purpose,
    revenue_stream,
    payment_group,
    is_payment,

    payment_method_raw,
    card_scheme,
    card_product,
    card_product_std,
    card_bin,
    has_usable_card_last_4,

    transaction_type_raw,
    transaction_initiator,
    initiator_inferred,
    mit_stage,
    three_ds_status,
    issuer_segment,

    fan_reference,
    fan_email_token,
    fan_ip,
    fan_country,
    billing_country,
    issuer_country,
    issuer_name,
    issuer_name_std,
    issuer_bin,
    region,
    geo_corridor,

    gateway_status,
    is_approved,
    authorisation_code,
    decline_reason_raw,
    decline_reason_std,
    decline_category,
    is_retryable_decline,
    recovery_lever,
    business_action,

    avs_response_raw,
    avs_code_std,
    avs_outcome,
    cvc2_response_raw,
    three_ds_enrolment_raw,
    three_ds_outcome_raw,

    is_analysis_eligible

from {{ ref('int_payments__quality_flags') }}
