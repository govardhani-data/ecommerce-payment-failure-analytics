USE VanyaPaymentsDB;

-- ============================================================
-- Q2 - Which failure reasons cost the most money?
-- ============================================================

-- Validation: does fact_checkout.final_failure_reason_key actually
-- match the reason on the last failed attempt for that checkout?
-- If this returns anything other than 0 mismatches, the column is
-- wrong and cannot be used.

WITH last_failed_seq AS (
    SELECT
        checkout_id,
        MAX(attempt_seq) AS last_seq
    FROM fact_payment_attempt
    WHERE failure_reason_key IS NOT NULL
    GROUP BY checkout_id
),
last_failed_reason AS (
    SELECT
        a.checkout_id,
        a.failure_reason_key
    FROM fact_payment_attempt AS a
    INNER JOIN last_failed_seq AS s
        ON  a.checkout_id = s.checkout_id
        AND a.attempt_seq = s.last_seq
)
SELECT
    COUNT(*)                                            AS checkouts_checked,
    SUM(CASE WHEN c.final_failure_reason_key = r.failure_reason_key
             THEN 1 ELSE 0 END)                         AS matches,
    SUM(CASE WHEN c.final_failure_reason_key <> r.failure_reason_key
             THEN 1 ELSE 0 END)                         AS mismatches,
    SUM(CASE WHEN c.final_failure_reason_key IS NULL
             THEN 1 ELSE 0 END)                         AS unexpected_nulls
FROM fact_checkout       AS c
INNER JOIN last_failed_reason AS r
    ON c.checkout_id = r.checkout_id;

    -- ============================================================
-- Failure reasons ranked two ways: by how often they happen,
-- and by how much revenue they actually cost.
-- ============================================================

WITH failed_attempts AS (
    -- How often each reason appeared, across every attempt.
    SELECT
        failure_reason_key,
        COUNT(*) AS failed_attempts
    FROM fact_payment_attempt
    WHERE failure_reason_key IS NOT NULL
    GROUP BY failure_reason_key
),
lost_checkouts AS (
    -- Only checkouts that never got authorised - real lost money.
    -- Attributed to the LAST failure reason.
    SELECT
        final_failure_reason_key AS failure_reason_key,
        COUNT(*)                 AS checkouts_lost,
        SUM(cart_value)          AS value_lost
    FROM fact_checkout
    WHERE authorised_datetime    IS NULL
      AND final_failure_reason_key IS NOT NULL
    GROUP BY final_failure_reason_key
)
SELECT
    d.failure_reason,
    d.failure_class,
    d.retryable_flag,
    ISNULL(fa.failed_attempts, 0)                       AS failed_attempts,
    ISNULL(lc.checkouts_lost,  0)                       AS checkouts_lost,
    ISNULL(lc.value_lost,      0)                       AS value_lost,
    CASE WHEN ISNULL(lc.checkouts_lost, 0) = 0 THEN NULL
         ELSE CAST(lc.value_lost / lc.checkouts_lost AS DECIMAL(10,2))
    END                                                 AS avg_lost_basket,
    CAST(100.0 * ISNULL(lc.value_lost, 0)
         / SUM(ISNULL(lc.value_lost, 0)) OVER ()
         AS DECIMAL(5,2))                               AS pct_of_value_lost,
    RANK() OVER (ORDER BY ISNULL(fa.failed_attempts, 0) DESC) AS rank_by_count,
    RANK() OVER (ORDER BY ISNULL(lc.value_lost,      0) DESC) AS rank_by_value
FROM dim_failure_reason AS d
LEFT JOIN failed_attempts AS fa ON d.failure_reason_key = fa.failure_reason_key
LEFT JOIN lost_checkouts  AS lc ON d.failure_reason_key = lc.failure_reason_key
ORDER BY value_lost DESC;

-- Must equal the Attempted-to-Authorised loss from Q1:
-- 24,000 checkouts and Rs 40,923,725.00
SELECT
    COUNT(*)        AS total_checkouts_lost_at_payment,
    SUM(cart_value) AS total_value_lost_at_payment
FROM fact_checkout
WHERE authorised_datetime IS NULL;

-- ============================================================
-- Q2b - Lost revenue grouped three ways.
-- Each block must sum to Rs 40,923,725.00
-- ============================================================

-- By failure class
SELECT
    d.failure_class,
    COUNT(*)                                        AS checkouts_lost,
    SUM(c.cart_value)                               AS value_lost,
    CAST(100.0 * SUM(c.cart_value)
         / SUM(SUM(c.cart_value)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_value_lost
FROM fact_checkout AS c
INNER JOIN dim_failure_reason AS d
    ON c.final_failure_reason_key = d.failure_reason_key
WHERE c.authorised_datetime IS NULL
GROUP BY d.failure_class
ORDER BY value_lost DESC;

-- By whether a retry could ever have worked
SELECT
    d.retryable_flag,
    COUNT(*)                                        AS checkouts_lost,
    SUM(c.cart_value)                               AS value_lost,
    CAST(100.0 * SUM(c.cart_value)
         / SUM(SUM(c.cart_value)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_value_lost
FROM fact_checkout AS c
INNER JOIN dim_failure_reason AS d
    ON c.final_failure_reason_key = d.failure_reason_key
WHERE c.authorised_datetime IS NULL
GROUP BY d.retryable_flag
ORDER BY value_lost DESC;

-- By failure category (the operational grouping)
SELECT
    d.failure_category,
    COUNT(*)                                        AS checkouts_lost,
    SUM(c.cart_value)                               AS value_lost,
    CAST(100.0 * SUM(c.cart_value)
         / SUM(SUM(c.cart_value)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_value_lost
FROM fact_checkout AS c
INNER JOIN dim_failure_reason AS d
    ON c.final_failure_reason_key = d.failure_reason_key
WHERE c.authorised_datetime IS NULL
GROUP BY d.failure_category
ORDER BY value_lost DESC;