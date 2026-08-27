USE VanyaPaymentsDB;

-- ============================================================
-- Q3 - How much failed-payment revenue is recoverable?
--
-- Scope: the 35,667 checkouts that had at least one failed
-- payment attempt.
--
-- Definition note: a customer counts as having switched method
-- if MORE THAN ONE payment method appears across their attempts.
-- An earlier version compared first method against last method,
-- which wrongly labelled Card > UPI > Card as "same method".
-- ============================================================


-- ---------- Q3a: headline recovery ----------

WITH failed_checkouts AS (
    SELECT DISTINCT checkout_id
    FROM fact_payment_attempt
    WHERE failure_reason_key IS NOT NULL
)
SELECT
    CASE WHEN c.authorised_datetime IS NOT NULL
         THEN 'Recovered' ELSE 'Lost' END          AS outcome,
    COUNT(*)                                        AS checkouts,
    SUM(c.cart_value)                               AS cart_value,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_checkouts,
    CAST(100.0 * SUM(c.cart_value) / SUM(SUM(c.cart_value)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_value
FROM fact_checkout AS c
INNER JOIN failed_checkouts AS f ON c.checkout_id = f.checkout_id
GROUP BY CASE WHEN c.authorised_datetime IS NOT NULL
              THEN 'Recovered' ELSE 'Lost' END;


-- ---------- Q3b: which attempt succeeded ----------
-- Online methods only. Cash on Delivery makes no payment
-- attempt, so it does not appear here.

SELECT
    attempt_seq                                     AS which_try,
    COUNT(*)                                        AS successes,
    SUM(attempt_amount)                             AS value,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER ()
         AS DECIMAL(5,2))                           AS pct_of_successes
FROM fact_payment_attempt
WHERE failure_reason_key IS NULL
GROUP BY attempt_seq
ORDER BY attempt_seq;


-- ---------- Q3b (check): why Q3b does not total 176,000 ----------
-- 141,870 online successes + 34,130 Cash on Delivery = 176,000.

SELECT
    m.method_name,
    m.method_type,
    COUNT(*) AS checkouts
FROM fact_checkout AS c
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
WHERE c.authorised_datetime IS NOT NULL
GROUP BY m.method_name, m.method_type
ORDER BY checkouts DESC;


-- ---------- Q3c: switching method vs staying ----------

WITH method_variety AS (
    SELECT
        checkout_id,
        COUNT(DISTINCT payment_method_key) AS methods_used
    FROM fact_payment_attempt
    GROUP BY checkout_id
)
SELECT
    CASE WHEN v.methods_used > 1
         THEN 'Used another method'
         ELSE 'Stayed on one method' END             AS retry_path,
    COUNT(*)                                         AS checkouts,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN 1 ELSE 0 END)                      AS recovered,
    CAST(100.0 * SUM(CASE WHEN c.authorised_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                            AS recovery_rate_pct,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN c.cart_value ELSE 0 END)           AS value_recovered
FROM fact_checkout AS c
INNER JOIN method_variety AS v ON c.checkout_id = v.checkout_id
WHERE c.attempt_count > 1
GROUP BY CASE WHEN v.methods_used > 1
              THEN 'Used another method'
              ELSE 'Stayed on one method' END;


-- ---------- Q3d: recovery rate by first failure reason ----------

WITH first_failure AS (
    SELECT checkout_id, failure_reason_key
    FROM (
        SELECT
            checkout_id,
            failure_reason_key,
            ROW_NUMBER() OVER (PARTITION BY checkout_id
                               ORDER BY attempt_seq) AS n
        FROM fact_payment_attempt
        WHERE failure_reason_key IS NOT NULL
    ) AS x
    WHERE n = 1
)
SELECT
    d.failure_reason,
    d.failure_category,
    d.retryable_flag,
    COUNT(*)                                         AS checkouts,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN 1 ELSE 0 END)                      AS recovered,
    CAST(100.0 * SUM(CASE WHEN c.authorised_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                            AS recovery_rate_pct,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN c.cart_value ELSE 0 END)           AS value_recovered
FROM first_failure AS ff
INNER JOIN fact_checkout      AS c ON ff.checkout_id       = c.checkout_id
INNER JOIN dim_failure_reason AS d ON ff.failure_reason_key = d.failure_reason_key
GROUP BY d.failure_reason, d.failure_category, d.retryable_flag
ORDER BY recovery_rate_pct DESC;


-- ---------- Q3e: retry path split by failure class ----------
-- The main finding: switching recovers ~75% whatever the
-- failure class. Staying on one method depends heavily on it.

WITH method_variety AS (
    SELECT
        checkout_id,
        COUNT(DISTINCT payment_method_key) AS methods_used
    FROM fact_payment_attempt
    GROUP BY checkout_id
),
first_failure AS (
    SELECT checkout_id, failure_reason_key
    FROM (
        SELECT
            checkout_id,
            failure_reason_key,
            ROW_NUMBER() OVER (PARTITION BY checkout_id
                               ORDER BY attempt_seq) AS n
        FROM fact_payment_attempt
        WHERE failure_reason_key IS NOT NULL
    ) AS x
    WHERE n = 1
)
SELECT
    d.failure_class,
    CASE WHEN v.methods_used > 1
         THEN 'Used another method'
         ELSE 'Stayed on one method' END             AS retry_path,
    COUNT(*)                                         AS checkouts,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN 1 ELSE 0 END)                      AS recovered,
    CAST(100.0 * SUM(CASE WHEN c.authorised_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                            AS recovery_rate_pct,
    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN c.cart_value ELSE 0 END)           AS value_recovered
FROM first_failure        AS ff
INNER JOIN method_variety AS v ON ff.checkout_id = v.checkout_id
INNER JOIN fact_checkout  AS c ON ff.checkout_id = c.checkout_id
INNER JOIN dim_failure_reason AS d
    ON ff.failure_reason_key = d.failure_reason_key
WHERE c.attempt_count > 1
GROUP BY d.failure_class,
         CASE WHEN v.methods_used > 1
              THEN 'Used another method'
              ELSE 'Stayed on one method' END
ORDER BY d.failure_class, retry_path;