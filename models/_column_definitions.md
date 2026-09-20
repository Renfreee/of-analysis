{#
    Column definitions, written once and referenced everywhere.

    A column that keeps its meaning as it flows from source to staging to mart
    carries the same definition at every layer: the block is written here and
    pulled in with {{ doc('col__name') }}. A column that is calculated gets its
    own block, which states what it is derived from and which assumption it
    rests on, so a reader never has to open the SQL to find out what a value
    means or how far to trust it.

    Naming: col__<column name>. Blocks are global to the project, so the prefix
    keeps them from colliding with model or macro names.
#}

{# ---------------------------------------------------------------- keys #}

{% docs col__transaction_key %}
Surrogate key: one row per authorisation attempt, stable across runs.

The export has no usable primary key, so this is built in
`base_payments__keyed` by hashing the full business payload and adding an
occurrence index. Byte-identical rows therefore still receive distinct keys
and nothing is silently dropped before the de-duplication logic can classify
it.
{% enddocs %}

{% docs col__record_hash %}
MD5 of the row's business payload, used to build `transaction_key` and to
identify byte-identical duplicates.
{% enddocs %}

{% docs col__record_occurrence %}
Occurrence index within a `record_hash` group: 1 for the first copy of an
identical payload, 2 for the second, and so on. Keeps duplicates addressable
instead of collapsing them.
{% enddocs %}

{% docs col__psp_reference %}
Gateway-assigned payment reference.

**Not unique in this export.** 55 references are shared by unrelated
transactions with different Fans and different amounts (111 rows). See the
`dq_psp_reference_collisions` test. De-duplicating on it would delete real
payments, so `transaction_key` is used as the key instead.
{% enddocs %}

{% docs col__scheme_reference %}
Card-scheme network reference for the transaction.
{% enddocs %}

{% docs col__has_precision_lost_scheme_ref %}
True where `scheme_reference` arrived in spreadsheet scientific notation
(`7.64917E+14`). The trailing digits are gone, so the identifier cannot be
recovered and must not be used to join.
{% enddocs %}

{# ------------------------------------------------------ gateway, merchant #}

{% docs col__gateway %}
The payment provider that processed the attempt: `vendor1` or `vendor2`.

The two providers use different field meanings and different vocabularies for
the same events, so nearly every comparison in this project is made within or
across this column deliberately, never by accident.
{% enddocs %}

{% docs col__merchant_account %}
The merchant account the attempt was routed to, within the gateway. Accounts
are selected by the card's billing country. Names repeat across providers
(`merchant_A` exists on both) but refer to different accounts, so always read
it with `gateway`.
{% enddocs %}

{# --------------------------------------------------------------- money #}

{% docs col__amount %}
Transaction amount in the original currency, as supplied.

Use `amount_usd` for any total: this column mixes USD and BRL.
{% enddocs %}

{% docs col__currency %}
ISO currency of the attempt as supplied. USD on all but 87 rows, which are BRL.
{% enddocs %}

{% docs col__amount_usd %}
**Calculated.** Amount converted to a single reporting currency so values can
be summed.

USD rows pass through unchanged. BRL rows are divided by the `fx_brl_per_usd`
var in `dbt_project.yml`, which is a **proxy rate, not Finance's rate**, and it
affects 87 rows. Check `fx_basis` before quoting a converted total.
{% enddocs %}

{% docs col__fx_basis %}
**Calculated.** How `amount_usd` was arrived at: `native` where the attempt was
already USD, `proxy_rate` where a BRL amount was converted at an assumed rate.
Lets any total be split into the part that is exact and the part that rests on
an assumption.
{% enddocs %}

{% docs col__is_reporting_currency %}
**Calculated.** True where the attempt was made in the reporting currency (USD)
and so needed no conversion.
{% enddocs %}

{% docs col__amount_band %}
**Calculated.** Payment size bucket on `amount_usd`: under 10, 10–25, 25–50,
50–100, 100+, plus a band for $0 verification checks. Used to test whether
approval falls as ticket size rises.
{% enddocs %}

{% docs col__creator_share_usd %}
**Calculated.** The creator's share of the attempt, at the published 80/20
split (`creator_share` var). On a declined row this is the earnings the
creator did not receive, which is how the cost of declines is stated in the
executive summary.
{% enddocs %}

{# -------------------------------------------------------------- timing #}

{% docs col__creation_clock_raw %}
The timestamp exactly as the export supplied it.

**No date survives in this file.** The export went through a spreadsheet and
only a partial clock value remains, so this is kept verbatim as evidence of
the defect rather than parsed into something that looks trustworthy.
{% enddocs %}

{% docs col__creation_seconds_into_hour %}
**Calculated.** The minutes and seconds recoverable from `creation_clock_raw`,
expressed as seconds into an unknown hour. Enough to detect ordering within an
hour; not enough for trend, payday or retry-timing analysis.
{% enddocs %}

{% docs col__created_at %}
When the attempt was created. **Always null in this export** (see
`creation_clock_raw`); the column exists so the contract is ready for a source
that supplies a real timestamp.
{% enddocs %}

{% docs col__has_resolvable_timestamp %}
True where the row carries a timestamp that can be resolved to a point in time.
False for every row in this export, which is what blocks all time-based
analysis.
{% enddocs %}

{% docs col__source_timezone %}
Timezone as supplied, or `UNSPECIFIED` where the gateway sent none. Vendor 1
never populates it, and it is not assumed to be UTC.
{% enddocs %}

{% docs col__reporting_date %}
**Calculated.** The reporting month from the brief (2026-07-01), stamped on
every row so the semantic layer has a time grain to aggregate over. It is a
label for the period, **not** the time the payment happened.
{% enddocs %}

{# ---------------------------------------------------------- instrument #}

{% docs col__payment_method_raw %}
Payment method as supplied. Vendor 1 names the scheme; vendor 2 sends the
generic literal `CC`, which is why `card_scheme` has to be recovered from the
card product.
{% enddocs %}

{% docs col__card_product %}
Issuer's card product name as supplied, e.g. `VISA CLASSIC`. Missing on roughly
a third of vendor 2 rows.
{% enddocs %}

{% docs col__card_product_std %}
**Calculated.** `card_product` upper-cased and trimmed, with blanks nulled.

Deliberately **not** used to derive debit, credit or prepaid: 36% of vendor 2
rows have no product name, so a funding type derived here would be wrong for a
third of the traffic without saying so.
{% enddocs %}

{% docs col__card_scheme %}
**Calculated.** Card network (Visa, Mastercard, PIX, Unknown), normalised
across gateways by the `normalise_card_scheme` macro.

Vendor 2 sends `CC` as the method, so its scheme is recovered from the card
product where present. 1,982 rows stay `Unknown` rather than being guessed.
{% enddocs %}

{% docs col__card_bin %}
Issuing bank identification number: the leading digits of the card, which
identify the issuer. Non-numeric values are nulled and flagged by
`has_invalid_card_bin`.
{% enddocs %}

{% docs col__has_invalid_card_bin %}
True where `card_bin` was not a usable number in the source and has been
nulled.
{% enddocs %}

{% docs col__card_last_4_raw %}
Last four card digits as supplied. Masked or truncated throughout this export,
so it cannot identify a card. See `has_usable_card_last_4`.
{% enddocs %}

{% docs col__has_usable_card_last_4 %}
True where the last four digits are genuinely present. False for every row
here, which is part of why a Fan cannot be followed across attempts.
{% enddocs %}

{# --------------------------------------------------------- initiator #}

{% docs col__transaction_type_raw %}
Initiator code exactly as the gateway sent it, kept unmapped.

The two providers use undocumented and incompatible taxonomies: vendor 1 tags
only merchant-initiated rows (`MIT`, blank otherwise), vendor 2 uses `C` and
`M`. Read `initiator_inferred` for the resolved value.
{% enddocs %}

{% docs col__transaction_initiator %}
**Calculated, per gateway.** The initiator as far as a single gateway's own
codes can state it: `MIT`, or `UNKNOWN` where that gateway does not say.
Resolved across both providers in `initiator_inferred`.
{% enddocs %}

{% docs col__initiator_inferred %}
**Calculated.** Who initiated the payment, on one vocabulary across both
gateways: `CIT` (the Fan is present) or `MIT` (merchant-initiated, no Fan).

Vendor 1 tags only merchant-initiated rows, so an untagged row is read as
Fan-present; vendor 2's `C` and `M` map to CIT and MIT. This lifts initiator
coverage from 70.2% to 99.9% of rows, and **rests on an assumption** about
vendor 2's codes that the provider has not confirmed.

This is the single most important split in the analysis: Fan-present payments
and subscription rebills authorise at completely different rates, so any
approval figure quoted without it is misleading.
{% enddocs %}

{% docs col__mit_stage %}
**Calculated.** Where a merchant-initiated charge sits in a subscription's
life: `initial` (the first charge, which sets up later ones),
`subsequent (rebill)`, `other MIT`, or `stage unknown`.

Vendor 1 distinguishes these; vendor 2 does not, so all of its `M` rows are
`stage unknown`. The `initial` rows are labelled merchant-initiated by vendor 1
but the Fan is in fact present (3-D Secure, ~81% approval), which is why they
are grouped with Fan-initiated payments in `payment_group`.
{% enddocs %}

{# ------------------------------------------------------- fan, geography #}

{% docs col__fan_reference %}
The gateway's reference for the Fan, where one is usable.

Vendor 1's placeholder value `5` is nulled here: it is shared by 1,167
unrelated Fans, so treating it as an identifier would merge them into one
person. Vendor 2 sends no Fan reference at all. **There is no working Fan
identifier in this export**, which is why retries, recovery and per-creator
loss cannot be measured.
{% enddocs %}

{% docs col__has_placeholder_fan_reference %}
True where the source supplied the shared placeholder instead of a real Fan
reference.
{% enddocs %}

{% docs col__fan_email_token %}
Tokenised Fan email as supplied. Not reversible and not usable as an
identifier across gateways.
{% enddocs %}

{% docs col__fan_country %}
Country of the Fan as supplied, with `N/A` nulled.
{% enddocs %}

{% docs col__fan_ip %}
Fan IP address as supplied.
{% enddocs %}

{% docs col__billing_country %}
Billing country of the card, as supplied. Drives which merchant account the
payment is routed to.
{% enddocs %}

{% docs col__issuer_country %}
Country of the issuing bank, as supplied.
{% enddocs %}

{% docs col__issuer_name %}
Issuing bank name exactly as supplied, in 1,217 spellings that differ by case
and punctuation.
{% enddocs %}

{% docs col__issuer_name_std %}
**Calculated.** `issuer_name` upper-cased with punctuation reduced to spaces,
which collapses 1,217 spellings to 1,074 banks and makes issuer-level
comparison possible.
{% enddocs %}

{% docs col__issuer_bin %}
Issuer BIN as supplied by the gateway. Vendor 1 never populates it.
{% enddocs %}

{% docs col__issuer_segment %}
**Calculated.** Whether the card comes from a `fintech` sponsor bank, a
`mainstream` bank, or an `unknown` issuer, joined from the
`issuer_segment_map` seed.

**Rests on outside knowledge, not on the data**: the eight sponsor banks
(Sutton, Bancorp, Stride, Green Dot, Pathward and so on) are tagged from
industry knowledge because the export carries no funding type. Issuers with no
name resolve to `unknown`, which is 28% of vendor 2.
{% enddocs %}

{% docs col__region %}
**Calculated.** Fan's market, grouped for reporting: `US`, `UK`, `EU`, `LATAM`,
`ANZ`, `Rest of world`, or `Unknown` where no Fan country was supplied.
{% enddocs %}

{% docs col__geo_corridor %}
**Calculated.** Whether the issuing country matches the Fan's country:
`domestic`, `cross_border`, or `unknown` where either side is missing.
Cross-border traffic authorises lower, so it is held equal in every
like-for-like comparison.
{% enddocs %}

{# -------------------------------------------------------------- outcome #}

{% docs col__gateway_status %}
The authorisation outcome as the gateway reported it: `Approved`, `Declined`
or `Failed`.
{% enddocs %}

{% docs col__is_approved %}
True where the attempt was authorised. The numerator of the authorisation
rate.
{% enddocs %}

{% docs col__authorisation_code %}
The bank's approval token for an authorised payment.

**Gateway-dependent, and null for vendor 1 by design.** Vendor 1 does not put
an authorisation code in this column: on declined rows it repeats the decline
text and on approved rows it is empty, with the real token masked elsewhere.
Rather than publish a field that means two different things, vendor 1 is
nulled and flagged by `has_auth_code_contamination`.
{% enddocs %}

{% docs col__has_sentinel_auth_code %}
True where the gateway sent a placeholder authorisation code (vendor 2's
`00000`) rather than a real one. Treating the sentinel as a genuine code
produced 47 phantom status conflicts; reading it as blank leaves 1 real one.
{% enddocs %}

{% docs col__has_auth_code_contamination %}
True where decline text was found in the authorisation code column (vendor 1).
Evidence for the engineering ask, kept as a flag rather than quietly cleaned
away.
{% enddocs %}

{% docs col__decline_reason_raw %}
The decline reason exactly as the gateway worded it, across 77 different
spellings between the two providers.
{% enddocs %}

{% docs col__decline_reason_std %}
**Calculated.** The decline reason on one vocabulary across both gateways,
joined from the `decline_reason_map` seed: 77 source spellings mapped to 35
standard reasons.
{% enddocs %}

{% docs col__decline_category %}
**Calculated.** The family a decline belongs to: insufficient funds, generic
issuer decline, fraud block, issuer policy, card data problem, authentication,
velocity, technical error or merchant configuration. Joined from the
`decline_reason_map` seed.

Vendor 1 reports specific reasons while vendor 2 returns mostly generic "do not
honour", so a difference between providers here partly reflects **labelling,
not behaviour**.
{% enddocs %}

{% docs col__is_retryable_decline %}
**Calculated.** Whether a retry is worth attempting, from the
`decline_reason_map` seed. Insufficient funds is retryable at a better time;
lost or stolen and revoked authorisations never are, and retrying them costs
fees and breaches card-scheme rules.
{% enddocs %}

{# ------------------------------------------------- verification signals #}

{% docs col__avs_response_raw %}
Address verification result as supplied. Vendor 1 sends prose, vendor 2 sends
single-letter network codes; both are mapped in `avs_outcome`.
{% enddocs %}

{% docs col__avs_outcome %}
**Calculated.** Address check result on one standard across both gateways,
joined from the `avs_response_map` seed: full or ZIP match, partial or no
match, or not verified.

Weak address data is one of the clearest drivers of decline in this dataset,
which is what makes the mapping worth doing.
{% enddocs %}

{% docs col__cvc2_response_raw %}
Card security code check result as supplied.
{% enddocs %}

{% docs col__three_ds_enrolment_raw %}
Vendor 1's Yes/No 3-D Secure **enrolment** flag: whether the card was enrolled,
not whether authentication happened.
{% enddocs %}

{% docs col__three_ds_outcome_raw %}
Vendor 2's 3-D Secure **outcome**: what authentication actually returned.

The two gateways put different meanings in the same source column, so they are
surfaced separately and never unioned into one dimension.
{% enddocs %}

{% docs col__three_ds_status %}
**Calculated.** Resolved 3-D Secure status: `no 3DS`, `full authentication`,
`frictionless authentication`, or `3DS error`. Built only from the outcome
field, so an enrolment flag is never read as if it were an authentication
result.
{% enddocs %}

{# ------------------------------------------------------- classification #}

{% docs col__transaction_purpose %}
**Calculated.** Whether the row is a real `payment` or a `card_verification`
check.

$0 attempts are card checks, not purchases. The export carries no field that
says so, so the amount is the only signal available. There are 1,366 of them,
all on vendor 2, and leaving them in the payment population drags that
gateway's average payment from $31.46 down to $23.76.
{% enddocs %}

{% docs col__revenue_stream %}
**Calculated.** What the charge is commercially: `fan-present purchase` (tips,
pay-per-view, new subscriptions), `subscription start`, `subscription
renewal`, `other merchant-initiated`, or `card verification`.

The business-facing view of `initiator_inferred` and `mit_stage`: renewals and
Fan-present purchases authorise at very different rates, so the headline
authorisation rate should always be read alongside this column.
{% enddocs %}

{% docs col__payment_group %}
**Calculated.** Like-for-like groups for comparing the two gateways:
`fan-initiated`, `subscription rebill`, `other merchant-initiated`, `card
verification`, `unknown`.

First subscription charges are grouped with `fan-initiated` even though vendor
1 labels them merchant-initiated, because the Fan is present (3-D Secure,
~81% approval) and vendor 2 classes the same event as Fan-initiated. Without
this the two providers cannot be compared on equal traffic. The assumptions
are set out in `int_payments__enriched`.
{% enddocs %}

{% docs col__is_payment %}
**Calculated.** True for real payments, false for $0 card verification checks.
Excluding these is the first filter of the analysis base.
{% enddocs %}

{% docs col__is_analysis_eligible %}
**Calculated.** False where the row is a duplicate charge or carries an
unresolved status conflict, and so must not be counted in commercial metrics.

Nothing is deleted: the row stays in `fct_payment_attempts` so Finance can
still reconcile to the provider's own reports, and `fct_payments` applies the
filter so analysts do not have to remember it.
{% enddocs %}

{% docs col__dq_issue_count %}
**Calculated.** How many data quality flags the row raised. Used to triage the
export with engineering, not for commercial analysis.
{% enddocs %}
