{#
    Attaches the cross-gateway reference taxonomies and derives the analytical
    dimensions used by the marts. Left joins throughout: an unmapped value must
    show up as a null the tests can catch, never be dropped from the row count.
#}

with payments as (

    select * from {{ ref('int_payments__unioned') }}

),

decline_map as (

    select * from {{ ref('decline_reason_map') }}

),

avs_map as (

    select * from {{ ref('avs_response_map') }}

),

issuer_map as (

    select * from {{ ref('issuer_segment_map') }}

),

joined as (

    select
        p.*,

        -- normalised decline taxonomy (both gateways onto one vocabulary)
        d.decline_reason_std,
        d.decline_category,
        d.is_retryable                                          as is_retryable_decline,
        d.recovery_lever,
        d.business_action,

        -- normalised address verification result
        a.avs_code_std,
        a.avs_outcome

    from payments p
    left join decline_map d
        on p.decline_reason_raw = d.raw_acquirer_response
    left join avs_map a
        on p.avs_response_raw = a.avs_response_raw

),

converted as (

    select
        *,

        -- BRL converted at a proxy rate (dbt var fx_brl_per_usd); see dbt_project.yml
        case
            when currency = 'USD' then amount
            when currency = 'BRL' then round(amount / {{ var('fx_brl_per_usd') }}, 2)
        end                                                     as amount_usd,
        case
            when currency = 'USD' then 'native'
            when currency = 'BRL' then 'proxy_rate'
        end                                                     as fx_basis,

        -- $0 attempts are card-verification checks, not purchases; the export
        -- carries no field that labels them, so amount is the only signal
        case when amount = 0 then 'card_verification' else 'payment' end
                                                                as transaction_purpose,

        nullif(trim(regexp_replace(upper(issuer_name), '[^A-Z0-9]+', ' ', 'g')), '')
                                                                as issuer_name_std,
        nullif(upper(trim(card_product)), '')                   as card_product_std

    from joined

),

{#
    Analytical segments. Inferred, not supplied - the evidence is documented in
    docs/data_cleaning_log.md (Assumptions):
      * vendor1 blank transaction_type behaves as customer-initiated (3DS
        present, ~$37 average, ~90% approval); vendor1 'MIT' is merchant-initiated.
      * vendor2 'C' mirrors vendor1 CIT on value and approval; 'M' mirrors
        vendor1's rebill segment (~$19.50 average, ~31% approval).
      * vendor1 MIT splits into initial (3DS "Initial Merchant Initiated
        Transaction"), subsequent rebills (placeholder shopper_reference '5'),
        and other. vendor2 gives no way to split its MIT.
#}
segmented as (

    select
        c.*,

        case
            when c.gateway = 'vendor1' and c.transaction_type_raw = 'MIT' then 'MIT'
            when c.gateway = 'vendor1' then 'CIT'
            when c.transaction_type_raw = 'C' then 'CIT'
            when c.transaction_type_raw = 'M' then 'MIT'
            else 'unknown'
        end                                                     as initiator_inferred,

        case
            when c.gateway = 'vendor1' and c.has_placeholder_fan_reference then 'subsequent (rebill)'
            when c.gateway = 'vendor1' and c.three_ds_outcome_raw = 'Initial Merchant Initiated Transaction' then 'initial'
            when c.gateway = 'vendor1' and c.transaction_type_raw = 'MIT' then 'other MIT'
            when c.gateway = 'vendor2' and c.transaction_type_raw = 'M' then 'stage unknown'
        end                                                     as mit_stage,

        case
            when c.gateway = 'vendor1' and c.three_ds_enrolment_raw = 'Yes' then '3DS attempted'
            when c.gateway = 'vendor1' then 'no 3DS'
            when c.three_ds_outcome_raw is null then 'no 3DS'
            when c.three_ds_outcome_raw in ('Full Authentication', 'Frictionless Authentication')
                then lower(c.three_ds_outcome_raw)
            else '3DS error'
        end                                                     as three_ds_status,

        coalesce(i.issuer_segment,
                 case when c.issuer_name_std is null then 'unknown' else 'mainstream' end)
                                                                as issuer_segment

    from converted c
    left join issuer_map i
        on c.issuer_name_std = i.issuer_name_std

),

derived as (

    select
        *,

        -- cross-border is one of the strongest authorisation-rate drivers
        case
            when issuer_country is null or fan_country is null then 'unknown'
            when issuer_country = fan_country then 'domestic'
            else 'cross_border'
        end                                                     as geo_corridor,

        case
            when fan_country in ('US') then 'North America (US)'
            when fan_country in ('CA', 'MX') then 'North America (other)'
            when fan_country in ('GB', 'IE') then 'UK & Ireland'
            when fan_country in ('DE','FR','IT','ES','NL','BE','AT','PT','SE','NO','DK','FI','PL','CH','CZ','GR','RO','HU') then 'Europe (ex-UK)'
            when fan_country in ('BR','AR','CL','CO','PE','UY','VE','EC','BO','PY') then 'LATAM'
            when fan_country in ('AU','NZ') then 'ANZ'
            when fan_country is null then 'Unknown'
            else 'Rest of world'
        end                                                     as region,

        case
            when amount_usd is null then 'unknown'
            when amount_usd = 0 then '00 zero (verification)'
            when amount_usd < 10 then '01 under 10'
            when amount_usd < 25 then '02 10-25'
            when amount_usd < 50 then '03 25-50'
            when amount_usd < 100 then '04 50-100'
            else '05 100+'
        end                                                     as amount_band,

        case when currency = 'USD' then true else false end     as is_reporting_currency,

        -- Fan-present purchases are tips, pay-per-view and new subscriptions;
        -- merchant-initiated charges are subscription billing.
        case
            when transaction_purpose = 'card_verification' then 'card verification'
            when initiator_inferred = 'CIT' then 'fan-present purchase'
            when mit_stage = 'initial' then 'subscription start'
            when mit_stage in ('subscription renewal', 'subsequent (rebill)', 'stage unknown') then 'subscription renewal'
            when initiator_inferred = 'MIT' then 'other merchant-initiated'
            else 'unknown'
        end                                                     as revenue_stream,

        -- Like-for-like groups for comparing the two gateways. Assumptions:
        --   * Gateway 1 tags a subscription's first charge as merchant-initiated
        --     ("Initial Merchant Initiated Transaction"), but the fan is present
        --     (3DS, ~81% approval). Gateway 2 labels the same event 'C'. So first
        --     charges are grouped with fan-initiated payments.
        --   * Gateway 1 rebills = merchant-initiated with the placeholder fan
        --     reference '5'. Gateway 2 'M' is assumed to be rebills: it can't be
        --     split, but matches Gateway 1 rebills on price and approval.
        --   * Gateway 1's remaining merchant-initiated charges have no Gateway 2
        --     equivalent we can identify, so they stay separate.
        case
            when transaction_purpose = 'card_verification' then 'card verification'
            when initiator_inferred = 'CIT' or mit_stage = 'initial' then 'fan-initiated'
            when mit_stage in ('subsequent (rebill)', 'stage unknown') then 'subscription rebill'
            when initiator_inferred = 'MIT' then 'other merchant-initiated'
            else 'unknown'
        end                                                     as payment_group,

        round(amount_usd * {{ var('creator_share') }}, 2)       as creator_share_usd,
        cast('{{ var("reporting_period_start") }}' as date)     as reporting_date

    from segmented

)

select * from derived
