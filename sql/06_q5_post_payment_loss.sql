USE VanyaPaymentsDB;

-- ============================================================
-- Q5 - Money lost after the customer has already paid.
--
-- Denominator note: duplicate charges can only occur on
-- checkouts that were actually captured. The correct
-- denominator is captured checkouts (162,775), not all
-- checkouts (200,000).
-- ============================================================


-- ---------- Q5a: duplicate charges, headline ----------

SELECT
    COUNT(*)                                            AS captured_checkouts,
    SUM(CAST(c.is_duplicate_charge AS INT))             AS duplicate_charges,
    CAST(100.0 * SUM(CAST(c.is_duplicate_charge AS INT))
         / COUNT(*) AS DECIMAL(6,3))                    AS duplicate_rate_pct,
    SUM(c.duplicate_charge_amount)                      AS duplicate_value,
    CAST(AVG(CASE WHEN c.is_duplicate_charge = 1
                  THEN c.duplicate_charge_amount END)
         AS DECIMAL(10,2))                              AS avg_duplicate_amount,
    CAST(AVG(CASE WHEN c.is_duplicate_charge = 1
                  THEN c.cart_value END)
         AS DECIMAL(10,2))                              AS avg_cart_when_duplicated,
    CAST(AVG(c.cart_value) AS DECIMAL(10,2))            AS avg_cart_overall
FROM fact_checkout AS c
WHERE c.captured_datetime IS NOT NULL;


-- ---------- Q5b: duplicates by payment method ----------
-- Is one method more likely to double-charge?

SELECT
    m.method_name,
    COUNT(*)                                            AS captured_checkouts,
    SUM(CAST(c.is_duplicate_charge AS INT))             AS duplicate_charges,
    CAST(100.0 * SUM(CAST(c.is_duplicate_charge AS INT))
         / COUNT(*) AS DECIMAL(6,3))                    AS duplicate_rate_pct,
    SUM(c.duplicate_charge_amount)                      AS duplicate_value
FROM fact_checkout AS c
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
WHERE c.captured_datetime IS NOT NULL
GROUP BY m.method_name
ORDER BY duplicate_rate_pct DESC;


-- ---------- Q5c: duplicates by number of attempts ----------
-- A customer who retried three times is more exposed to being
-- charged twice. Does the data show that?

SELECT
    c.attempt_count,
    COUNT(*)                                            AS captured_checkouts,
    SUM(CAST(c.is_duplicate_charge AS INT))             AS duplicate_charges,
    CAST(100.0 * SUM(CAST(c.is_duplicate_charge AS INT))
         / COUNT(*) AS DECIMAL(6,3))                    AS duplicate_rate_pct,
    SUM(c.duplicate_charge_amount)                      AS duplicate_value
FROM fact_checkout AS c
WHERE c.captured_datetime IS NOT NULL
GROUP BY c.attempt_count
ORDER BY c.attempt_count;

-- ---------- Q5d: where post-payment money goes ----------
-- Every checkout that was authorised, split by what happened
-- to it next. This covers both funnel steps after
-- authorisation, so it is the full post-payment picture.

SELECT
    f.outcome_category,
    f.outcome_name,
    COUNT(*)                                            AS checkouts,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                               AS pct_of_authorised,
    SUM(c.cart_value)                                   AS cart_value,
    SUM(c.cart_value) - SUM(c.revenue_captured)         AS value_lost,
    CAST(AVG(c.cart_value) AS DECIMAL(10,2))            AS avg_cart_value
FROM fact_checkout AS c
INNER JOIN dim_fulfilment_outcome AS f
    ON c.fulfilment_outcome_key = f.fulfilment_outcome_key
WHERE c.authorised_datetime IS NOT NULL
GROUP BY f.outcome_category, f.outcome_name
ORDER BY value_lost DESC;


-- ---------- Q5e: same thing, grouped ----------

SELECT
    f.outcome_category,
    COUNT(*)                                            AS checkouts,
    SUM(c.cart_value) - SUM(c.revenue_captured)         AS value_lost,
    CAST(100.0 * (SUM(c.cart_value) - SUM(c.revenue_captured))
         / SUM(SUM(c.cart_value) - SUM(c.revenue_captured)) OVER ()
         AS DECIMAL(5,2))                               AS pct_of_post_payment_loss
FROM fact_checkout AS c
INNER JOIN dim_fulfilment_outcome AS f
    ON c.fulfilment_outcome_key = f.fulfilment_outcome_key
WHERE c.authorised_datetime IS NOT NULL
GROUP BY f.outcome_category
ORDER BY value_lost DESC;