{% macro normalise_card_scheme(payment_method, payment_method_variant) %}
    case
        when upper(coalesce({{ payment_method }}, '')) like '%VISA%'
          or upper(coalesce({{ payment_method_variant }}, '')) like '%VISA%' then 'Visa'
        when upper(coalesce({{ payment_method }}, '')) like '%MASTER%'
          or upper(coalesce({{ payment_method_variant }}, '')) like '%MASTER%' then 'Mastercard'
        when upper(coalesce({{ payment_method }}, '')) = 'PIX' then 'PIX'
        else 'Unknown'
    end
{% endmacro %}


{% macro blank_to_null(column_name) %}
    nullif(trim(coalesce({{ column_name }}, '')), '')
{% endmacro %}


{#
    The source export carries no date component (see stg models); every
    creation_date_ts is an "MM:SS.s" fragment. This returns the seconds-past-
    the-minute offset that IS recoverable, so downstream models can at least
    detect near-simultaneous retries within the same minute.
#}
{% macro parse_partial_clock(column_name) %}
    case
        when regexp_matches({{ column_name }}, '^[0-9]{1,2}:[0-9]{2}(\.[0-9]+)?$')
        then cast(split_part({{ column_name }}, ':', 1) as integer) * 60
           + cast(cast(split_part({{ column_name }}, ':', 2) as double) as integer)
    end
{% endmacro %}
