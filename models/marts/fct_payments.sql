{#
    Grain: one row per real payment attempt that is safe to count.

    The analysis base: fct_payment_attempts filtered to payments only ($0 card
    verification checks removed) and to rows without an unresolved data quality
    problem (duplicate charges and status conflicts removed). Analysts query
    this table, so nobody has to remember the filters.

    Reconciles to the full log:
        fct_payment_attempts (10,000)
          = fct_payments (8,632)
          + card verification checks (1,366)
          + rows excluded by is_analysis_eligible (2)
#}

{{ config(materialized = 'view') }}

select * exclude (is_payment, is_analysis_eligible)
from {{ ref('fct_payment_attempts') }}
where is_analysis_eligible
  and is_payment
