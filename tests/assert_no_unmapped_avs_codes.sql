-- Pipeline invariant: both the prose (vendor1) and single-letter (vendor2)
-- address-verification vocabularies must resolve to the standard code set.

select
    gateway,
    avs_response_raw,
    count(*) as unmapped_rows
from {{ ref('fct_payment_attempts') }}
where avs_response_raw is not null
  and avs_code_std is null
group by gateway, avs_response_raw
