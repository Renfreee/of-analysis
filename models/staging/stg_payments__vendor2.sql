{#
    Vendor 2 export normalised onto the shared transaction contract.

    Vendor-2-specific handling:
      * authorisation_code is a genuine approval token here, so it is retained.
        A small number of declined rows nevertheless carry one - surfaced as a
        status conflict downstream rather than silently corrected.
      * payment_method is the generic literal 'CC'; the card scheme is only
        recoverable from payment_method_variant, which is missing on roughly a
        third of rows. Those resolve to 'Unknown' rather than being guessed.
      * avs_response uses single-letter network codes while vendor 1 uses
        prose. Both are mapped onto one standard in the intermediate layer.
      * three_d_directory_response carries an authentication *outcome* here,
        not the Yes/No enrolment flag vendor 1 puts in the same column.
#}

with source as (

    select * from {{ ref('base_payments__keyed') }}
    where vendor = 'vendor2'

),

renamed as (

    select
        transaction_key,
        record_hash,
        record_occurrence,

        -- gateway / merchant
        vendor                                                  as gateway,
        {{ blank_to_null('merchant_account') }}                 as merchant_account,
        {{ blank_to_null('psp_reference') }}                    as psp_reference,
        cast(null as varchar)                                   as scheme_reference,
        false                                                   as has_precision_lost_scheme_ref,

        -- timing: no date component survives in the export
        {{ blank_to_null('creation_date_ts') }}                 as creation_clock_raw,
        {{ parse_partial_clock('creation_date_ts') }}           as creation_seconds_into_hour,
        cast(null as timestamp)                                 as created_at,
        false                                                   as has_resolvable_timestamp,
        coalesce({{ blank_to_null('creation_date_time_zone') }}, 'UNSPECIFIED') as source_timezone,

        -- money
        {{ blank_to_null('currency') }}                         as currency,
        try_cast(amount as decimal(18, 2))                      as amount,

        -- instrument
        {{ blank_to_null('payment_method') }}                   as payment_method_raw,
        {{ blank_to_null('payment_method_variant') }}           as card_product,
        {{ normalise_card_scheme('payment_method', 'payment_method_variant') }} as card_scheme,
        case when try_cast(card_bin as bigint) > 0 then {{ blank_to_null('card_bin') }} end
                                                                as card_bin,
        case when try_cast(card_bin as bigint) > 0 then false else true end
                                                                as has_invalid_card_bin,
        {{ blank_to_null('card_last_4') }}                      as card_last_4_raw,
        false                                                   as has_usable_card_last_4,

        -- initiator: C / M taxonomy, mapping documented as an open assumption
        {{ blank_to_null('transaction_type') }}                 as transaction_type_raw,
        case
            when trim(coalesce(transaction_type, '')) = 'C' then 'CIT_ASSUMED'
            when trim(coalesce(transaction_type, '')) = 'M' then 'MIT_ASSUMED'
            else 'UNKNOWN'
        end                                                     as transaction_initiator,

        -- fan / geography
        cast(null as varchar)                                   as fan_reference,
        false                                                   as has_placeholder_fan_reference,
        {{ blank_to_null('shopper_email') }}                    as fan_email_token,
        {{ blank_to_null('shopper_country') }}                  as fan_country,
        {{ blank_to_null('shopper_ip') }}                       as fan_ip,
        {{ blank_to_null('billing_country') }}                  as billing_country,
        {{ blank_to_null('issuer_country') }}                   as issuer_country,
        {{ blank_to_null('issuer_name') }}                      as issuer_name,
        {{ blank_to_null('issuer_bin') }}                       as issuer_bin,

        -- outcome
        {{ blank_to_null('acquirer_response') }}                as gateway_status,
        case when acquirer_response = 'Approved' then true else false end as is_approved,

        -- '00000'/'000000' are placeholder tokens, not authorisations: they
        -- appear on approvals, declines and failures alike. Treated as absent
        -- so they neither evidence an approval nor fake a status conflict.
        case
            when {{ blank_to_null('authorisation_code') }} in ('00000', '000000') then null
            else {{ blank_to_null('authorisation_code') }}
        end                                                     as authorisation_code,
        case
            when {{ blank_to_null('authorisation_code') }} in ('00000', '000000') then true
            else false
        end                                                     as has_sentinel_auth_code,

        {{ blank_to_null('raw_acquirer_response') }}            as decline_reason_raw,

        -- verification signals
        {{ blank_to_null('avs_response') }}                     as avs_response_raw,
        {{ blank_to_null('cvc2_response') }}                    as cvc2_response_raw,
        cast(null as varchar)                                   as three_ds_enrolment_raw,
        {{ blank_to_null('three_d_directory_response') }}       as three_ds_outcome_raw,

        false                                                   as has_auth_code_contamination

    from source

)

select * from renamed
