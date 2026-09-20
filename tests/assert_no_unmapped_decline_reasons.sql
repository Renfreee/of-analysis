-- Pipeline invariant: every decline reason emitted by either gateway must map
-- onto the standard taxonomy. A new vendor code appearing in a future export
-- fails this test rather than quietly landing in an unclassified bucket.

select
    gateway,
    decline_reason_raw,
    count(*) as unmapped_rows
from {{ ref('fct_payment_attempts') }}
where decline_reason_raw is not null
  and decline_reason_std is null
group by gateway, decline_reason_raw
