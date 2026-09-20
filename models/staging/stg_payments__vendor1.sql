{#
    Vendor 1 export normalised onto the shared transaction contract.

    Vendor-1-specific handling:
      * authorisation_code does not contain an authorisation code. For every
        declined row it repeats the decline reason text, and for every approved
        row it is empty - the real approval token sits in
        message_authentication_code, fully masked as '******'. We therefore
        null out the auth code and raise a contamination flag rather than
        publishing a field that means something different per gateway.
      * creation_date_time_zone is never populated; set to UNSPECIFIED rather than assuming UTC.
      * three_d_directory_response is a Yes/No *enrolment* flag here, whereas on
        vendor 2 the same column carries an authentication *outcome*. The two
        are surfaced separately and never unioned into one dimension.
#}

with source as (

    select * from {{ ref('base_payments__keyed') }}
    where vendor = 'vendor1'

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
        {{ blank_to_null('scheme_reference') }}                 as scheme_reference,
        -- numeric network IDs arrive in spreadsheet scientific notation
        -- (7.64917E+14): trailing digits are gone and the ID is unusable
        case when scheme_reference like '%E+%' then true else false end
                                                                as has_precision_lost_scheme_ref,

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

        -- initiator: vendor 1 tags only merchant-initiated transactions
        {{ blank_to_null('transaction_type') }}                 as transaction_type_raw,
        case
            when trim(coalesce(transaction_type, '')) = 'MIT' then 'MIT'
            else 'UNKNOWN'
        end                                                     as transaction_initiator,

        -- fan / geography
        -- '5' is a placeholder, not a Fan: it covers 1,167 unrelated Fans
        case when trim(shopper_reference) = '5' then null
             else {{ blank_to_null('shopper_reference') }} end  as fan_reference,
        case when trim(shopper_reference) = '5' then true else false end
                                                                as has_placeholder_fan_reference,
        {{ blank_to_null('shopper_email') }}                    as fan_email_token,
        case when upper(trim(shopper_country)) = 'N/A' then null
             else {{ blank_to_null('shopper_country') }} end    as fan_country,
        {{ blank_to_null('shopper_ip') }}                       as fan_ip,
        {{ blank_to_null('billing_country') }}                  as billing_country,
        {{ blank_to_null('issuer_country') }}                   as issuer_country,
        {{ blank_to_null('issuer_name') }}                      as issuer_name,
        cast(null as varchar)                                   as issuer_bin,

        -- outcome
        {{ blank_to_null('acquirer_response') }}                as gateway_status,
        case when acquirer_response = 'Approved' then true else false end as is_approved,
        cast(null as varchar)                                   as authorisation_code,
        false                                                   as has_sentinel_auth_code,
        coalesce(
            {{ blank_to_null('raw_acquirer_response') }},
            {{ blank_to_null('authorisation_code') }}
        )                                                       as decline_reason_raw,

        -- verification signals
        {{ blank_to_null('avs_response') }}                     as avs_response_raw,
        {{ blank_to_null('cvc2_response') }}                    as cvc2_response_raw,
        {{ blank_to_null('three_d_directory_response') }}       as three_ds_enrolment_raw,
        {{ blank_to_null('three_d_authentication_response') }}  as three_ds_outcome_raw,

        -- vendor-1 contamination flag: decline text parked in the auth code column
        case
            when acquirer_response <> 'Approved'
             and {{ blank_to_null('authorisation_code') }} is not null
            then true else false
        end                                                     as has_auth_code_contamination

    from source

)

select * from renamed
