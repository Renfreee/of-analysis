-- Pipeline invariant: the analysis base plus what it excludes must add back up
-- to the full attempt log, so Finance and analysts can never disagree on volume.

with counts as (

    select
        (select count(*) from {{ ref('fct_payment_attempts') }})            as attempts,
        (select count(*) from {{ ref('fct_payments') }})                    as payments,
        (select count(*) from {{ ref('fct_payment_attempts') }}
          where not is_payment)                                             as card_checks,
        (select count(*) from {{ ref('fct_payment_attempts') }}
          where is_payment and not is_analysis_eligible)                    as excluded

)

select *
from counts
where attempts <> payments + card_checks + excluded
