{{ config(severity = 'warn') }}

-- DQ-01 (critical). Every creation_date_ts in the export is an "MM:SS.s"
-- fragment with no date or hour component - the signature of a datetime column
-- formatted for display (Excel "mm:ss") before export rather than serialised as
-- a timestamp. Nothing downstream can reconstruct the true transaction time,
-- so all trend, cohort, retry-window and settlement-period analysis is blocked.

select
    gateway,
    count(*)                                as rows_without_timestamp,
    min(creation_clock_raw)                 as min_clock_fragment,
    max(creation_clock_raw)                 as max_clock_fragment
from {{ ref('fct_payment_attempts') }}
where not has_resolvable_timestamp
group by gateway
