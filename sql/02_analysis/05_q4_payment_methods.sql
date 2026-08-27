USE VanyaPaymentsDB;

-- ============================================================
-- Q4 - Which payment method performs best?
--
-- Measured end to end, from checkout submitted through to
-- fulfilled revenue. Payment success alone is not a fair
-- comparison because Cash on Delivery makes no payment
-- attempt and therefore cannot fail at that step.
-- ============================================================


-- ---------- Q4a: first-attempt success rate ----------
-- Only attempt 1, so retries do not distort the comparison.
-- Cash on Delivery does not appear: it makes no attempts.

SELECT
    m.method_name,
    COUNT(*)                                        AS first_attempts,
    SUM(CASE WHEN a.failure_reason_key IS NULL
             THEN 1 ELSE 0 END)                     AS succeeded,
    CAST(100.0 * SUM(CASE WHEN a.failure_reason_key IS NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                           AS success_rate_pct,
    CAST(AVG(a.attempt_amount) AS DECIMAL(10,2))    AS avg_attempt_value
FROM fact_payment_attempt AS a
INNER JOIN dim_payment_method AS m
    ON a.payment_method_key = m.payment_method_key
WHERE a.attempt_seq = 1
GROUP BY m.method_name
ORDER BY success_rate_pct DESC;


-- ---------- Q4b: end-to-end, by the method chosen first ----------
-- The fair comparison. Follows every checkout from submission
-- through to money in the bank.

SELECT
    m.method_name,
    m.method_type,
    COUNT(*)                                            AS checkouts,
    CAST(AVG(c.cart_value) AS DECIMAL(10,2))            AS avg_cart_value,
    SUM(c.cart_value)                                   AS cart_value_started,

    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
             THEN 1 ELSE 0 END)                         AS authorised,
    SUM(CASE WHEN c.captured_datetime  IS NOT NULL
             THEN 1 ELSE 0 END)                         AS captured,
    SUM(CASE WHEN c.fulfilled_datetime IS NOT NULL
             THEN 1 ELSE 0 END)                         AS fulfilled,

    CAST(100.0 * SUM(CASE WHEN c.fulfilled_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                               AS pct_fulfilled,

    SUM(c.revenue_captured)                             AS revenue_kept,
    CAST(100.0 * SUM(c.revenue_captured) / SUM(c.cart_value)
         AS DECIMAL(5,2))                               AS pct_value_kept,
    SUM(c.cart_value) - SUM(c.revenue_captured)         AS value_lost
FROM fact_checkout AS c
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
GROUP BY m.method_name, m.method_type
ORDER BY value_lost DESC;


-- ---------- Q4c: where each method loses its money ----------
-- Splits each method's losses into the three funnel steps
-- from Q1, so you can see whether a method fails at payment,
-- at capture, or at delivery.

SELECT
    m.method_name,
    COUNT(*)                                            AS checkouts,

    SUM(CASE WHEN c.authorised_datetime IS NULL
             THEN c.cart_value ELSE 0 END)              AS lost_at_payment,

    SUM(CASE WHEN c.authorised_datetime IS NOT NULL
              AND c.captured_datetime  IS NULL
             THEN c.cart_value ELSE 0 END)              AS lost_at_capture,

    SUM(CASE WHEN c.captured_datetime  IS NOT NULL
              AND c.fulfilled_datetime IS NULL
             THEN c.cart_value ELSE 0 END)              AS lost_at_fulfilment,

    SUM(c.cart_value) - SUM(c.revenue_captured)         AS total_lost
FROM fact_checkout AS c
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
GROUP BY m.method_name
ORDER BY total_lost DESC;

-- ---------- Q4d: does the best method change by segment? ----------
-- If every segment has the same winner, one routing rule works
-- everywhere. If they differ, routing has to be segment-aware.

-- By city tier
SELECT
    cust.city_tier,
    m.method_name,
    COUNT(*)                                            AS checkouts,
    CAST(AVG(c.cart_value) AS DECIMAL(10,2))            AS avg_cart_value,
    CAST(100.0 * SUM(CASE WHEN c.fulfilled_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                               AS pct_fulfilled,
    CAST(100.0 * SUM(c.revenue_captured) / SUM(c.cart_value)
         AS DECIMAL(5,2))                               AS pct_value_kept,
    SUM(c.cart_value) - SUM(c.revenue_captured)         AS value_lost
FROM fact_checkout AS c
INNER JOIN dim_customer       AS cust ON c.customer_key = cust.customer_key
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
GROUP BY cust.city_tier, m.method_name
ORDER BY cust.city_tier, value_lost DESC;


-- By device type
SELECT
    d.device_type,
    m.method_name,
    COUNT(*)                                            AS checkouts,
    CAST(AVG(c.cart_value) AS DECIMAL(10,2))            AS avg_cart_value,
    CAST(100.0 * SUM(CASE WHEN c.fulfilled_datetime IS NOT NULL
                          THEN 1 ELSE 0 END) / COUNT(*)
         AS DECIMAL(5,2))                               AS pct_fulfilled,
    CAST(100.0 * SUM(c.revenue_captured) / SUM(c.cart_value)
         AS DECIMAL(5,2))                               AS pct_value_kept,
    SUM(c.cart_value) - SUM(c.revenue_captured)         AS value_lost
FROM fact_checkout AS c
INNER JOIN dim_device         AS d ON c.device_key = d.device_key
INNER JOIN dim_payment_method AS m
    ON c.initial_payment_method_key = m.payment_method_key
GROUP BY d.device_type, m.method_name
ORDER BY d.device_type, value_lost DESC;