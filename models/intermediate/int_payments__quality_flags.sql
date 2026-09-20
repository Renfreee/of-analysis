{#
    Row-level data quality flags - the machine-readable version of the Task 1
    audit. Every anomaly is flagged, never deleted: Finance needs the full
    attempt log for reconciliation, so cleansing here means "labelled and
    excludable", not "silently dropped".

    Note on duplicate detection: the industry-standard test is same card + same
    amount + same merchant *within a short time window*. The time-window leg is
    impossible on this export because no row carries a date - see
    dq_missing_timestamp. The rules below are therefore deliberately
    conservative and will under-report true duplicates.
#}

with payments as (

    select * from {{ ref('int_payments__enriched') }}

),

reference_collisions as (

    select
        psp_reference
    from payments
    group by psp_reference
    having count(distinct coalesce(fan_email_token, '~')) > 1

),

-- A duplicate charge is money taken twice: more than one APPROVAL for the same
-- Fan, card BIN, amount and gateway. A decline followed by a retry is normal
-- behaviour and is not flagged. $0 card-verification checks are excluded.
repeat_charges as (

    select
        gateway,
        fan_email_token,
        card_bin,
        amount,
        sum(case when is_approved then 1 else 0 end) as approval_count
    from payments
    where fan_email_token is not null
      and amount > 0
    group by gateway, fan_email_token, card_bin, amount
    having sum(case when is_approved then 1 else 0 end) > 1

),

issuer_name_variants as (

    select issuer_name_std
    from payments
    where issuer_name_std is not null
    group by issuer_name_std
    having count(distinct issuer_name) > 1

),

-- one IP seen across many countries is a server or proxy, not a Fan's device
shared_ips as (

    select fan_ip
    from payments
    where fan_ip is not null
    group by fan_ip
    having count(distinct fan_country) > 5

),

-- no timestamp survives, so "first" approval is arbitrary but deterministic
ranked as (

    select
        *,
        row_number() over (
            partition by gateway, fan_email_token, card_bin, amount, is_approved
            order by transaction_key
        ) as approval_rank_in_group
    from payments

),

flagged as (

    select
        p.*,

        -- 1. Timestamps: the export preserves only MM:SS, no date or hour
        true                                                    as dq_missing_timestamp,

        -- 2. psp_reference reused across unrelated Fans - breaks the natural key
        case when c.psp_reference is not null then true else false end
                                                                as dq_psp_reference_collision,

        -- 3. Byte-identical repeated row
        case when p.record_occurrence > 1 then true else false end
                                                                as dq_exact_duplicate_row,

        -- 4. Approval belonging to a group approved more than once
        case when r.approval_count is not null and p.is_approved then true else false end
                                                                as dq_suspected_duplicate_charge,
        -- ...and the redundant copies within that group (all but the first)
        case
            when r.approval_count is not null and p.is_approved
             and p.approval_rank_in_group > 1 then true else false
        end                                                     as dq_duplicate_charge_extra,

        -- 5. Outcome column disagrees with the reason column
        case
            when p.is_approved and p.decline_reason_std is not null
                 and p.decline_reason_std <> 'not_a_decline_contamination' then true
            when not p.is_approved and p.authorisation_code is not null then true
            else false
        end                                                     as dq_status_reason_conflict,

        -- 6. Decline text parked in the authorisation_code column (vendor 1)
        p.has_auth_code_contamination                           as dq_auth_code_contamination,

        -- 6b. Placeholder token supplied in place of a real authorisation code
        p.has_sentinel_auth_code                                as dq_sentinel_auth_code,

        -- 7. Approved with no retrievable authorisation token
        case
            when p.is_approved and p.authorisation_code is null then true else false
        end                                                     as dq_approved_without_auth_code,

        -- 8. Card scheme unattributable (vendor 2 sends generic 'CC')
        case when p.card_scheme = 'Unknown' then true else false end
                                                                as dq_missing_card_scheme,

        -- 9. CIT/MIT initiator unknown - blocks network-token and retry strategy
        case when p.transaction_initiator = 'UNKNOWN' then true else false end
                                                                as dq_missing_initiator,

        -- 10. No address verification result returned
        case when p.avs_response_raw is null then true else false end
                                                                as dq_missing_avs,

        -- 11. Declined with no reason captured at all
        case
            when not p.is_approved and p.decline_reason_raw is null then true else false
        end                                                     as dq_decline_without_reason,

        -- 12. Settled outside the reporting currency with no FX rate supplied
        case when not p.is_reporting_currency then true else false end
                                                                as dq_non_reporting_currency,

        -- 13. No stable Fan identifier (vendor 2 omits shopper_reference entirely)
        case when p.fan_reference is null then true else false end
                                                                as dq_missing_fan_reference,

        -- 14. Issuer country absent - blocks cross-border corridor analysis
        case when p.issuer_country is null then true else false end
                                                                as dq_missing_issuer_country,

        -- 15. $0 card-verification check with no field labelling it as such
        case when p.transaction_purpose = 'card_verification' then true else false end
                                                                as dq_unlabelled_card_verification,

        -- 16. Issuer spelled more than one way (case / punctuation) across rows
        case when v.issuer_name_std is not null then true else false end
                                                                as dq_issuer_name_variant,

        -- 17. Placeholder '5' in place of a Fan reference (vendor 1)
        p.has_placeholder_fan_reference                         as dq_placeholder_fan_reference,

        -- 18. Network transaction ID truncated by scientific notation
        p.has_precision_lost_scheme_ref                         as dq_scheme_ref_precision_lost,

        -- 19. Shopper IP is a shared server/proxy address, not the Fan's
        case when s.fan_ip is not null then true else false end as dq_shared_server_ip,

        -- 20. Card BIN is 0, -1 or otherwise invalid
        p.has_invalid_card_bin                                  as dq_invalid_card_bin

    from ranked p
    left join shared_ips s
        on p.fan_ip = s.fan_ip
    left join issuer_name_variants v
        on p.issuer_name_std = v.issuer_name_std
    left join reference_collisions c
        on p.psp_reference = c.psp_reference
    left join repeat_charges r
        on p.gateway = r.gateway
       and p.fan_email_token = r.fan_email_token
       and coalesce(p.card_bin, '~') = coalesce(r.card_bin, '~')
       and p.amount = r.amount

),

scored as (

    select
        *,

        -- issues that make a row unsafe to count in commercial analysis
        case
            when dq_exact_duplicate_row
              or dq_duplicate_charge_extra
              or dq_status_reason_conflict
            then false else true
        end                                                     as is_analysis_eligible,

        -- commercial payment metrics use this; verification checks are reported separately
        case when transaction_purpose = 'payment' then true else false end
                                                                as is_payment,

        (cast(dq_psp_reference_collision as integer)
         + cast(dq_exact_duplicate_row as integer)
         + cast(dq_suspected_duplicate_charge as integer)
         + cast(dq_status_reason_conflict as integer)
         + cast(dq_auth_code_contamination as integer)
         + cast(dq_sentinel_auth_code as integer)
         + cast(dq_approved_without_auth_code as integer)
         + cast(dq_missing_card_scheme as integer)
         + cast(dq_missing_initiator as integer)
         + cast(dq_missing_avs as integer)
         + cast(dq_decline_without_reason as integer)
         + cast(dq_non_reporting_currency as integer)
         + cast(dq_missing_fan_reference as integer)
         + cast(dq_missing_issuer_country as integer)
         + cast(dq_unlabelled_card_verification as integer)
         + cast(dq_issuer_name_variant as integer)
         + cast(dq_placeholder_fan_reference as integer)
         + cast(dq_scheme_ref_precision_lost as integer)
         + cast(dq_shared_server_ip as integer)
         + cast(dq_invalid_card_bin as integer))                as dq_issue_count

    from flagged

)

select * from scored
