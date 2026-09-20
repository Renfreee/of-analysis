{#
    Assigns a stable surrogate key to every source row.

    The export has no usable primary key: psp_reference collides across
    unrelated transactions (different Fans, different amounts) - see
    tests/dq_psp_reference_collisions.sql. We therefore hash the full business
    payload and add an occurrence index, so byte-identical rows still receive
    distinct, deterministic keys and nothing is silently lost before the
    de-duplication logic in the intermediate layer gets to classify it.
#}

with source as (

    select * from {{ source('raw_payments', 'fan_transactions') }}

),

hashed as (

    select
        *,
        md5(
            concat_ws('|',
                coalesce(vendor, ''),
                coalesce(merchant_account, ''),
                coalesce(psp_reference, ''),
                coalesce(scheme_reference, ''),
                coalesce(payment_method, ''),
                coalesce(payment_method_variant, ''),
                coalesce(creation_date_ts, ''),
                coalesce(currency, ''),
                coalesce(amount, ''),
                coalesce(transaction_type, ''),
                coalesce(card_bin, ''),
                coalesce(shopper_ip, ''),
                coalesce(shopper_country, ''),
                coalesce(shopper_email, ''),
                coalesce(issuer_name, ''),
                coalesce(acquirer_response, ''),
                coalesce(authorisation_code, ''),
                coalesce(raw_acquirer_response, ''),
                coalesce(avs_response, ''),
                coalesce(billing_postal_code_zip, '')
            )
        ) as record_hash

    from source

)

select
    md5(record_hash || '|' || cast(row_number() over (
        partition by record_hash order by psp_reference, amount
    ) as varchar)) as transaction_key,
    record_hash,
    row_number() over (
        partition by record_hash order by psp_reference, amount
    ) as record_occurrence,
    *

from hashed
