USE VanyaPaymentsDB;

/* Q1 - Where does revenue leak across the checkout-to-revenue funnel?

   Note on cash on delivery: COD checkouts never make a payment attempt, so
   for funnel purposes an order-confirmed COD checkout counts as having
   passed the "payment attempted" stage. Without that, the funnel would
   appear to lose 17% of volume at a stage COD does not participate in. */

WITH checkout_stages AS (
    SELECT
        c.cart_value,
        c.revenue_captured,
        CASE WHEN c.attempt_count > 0 OR m.method_name = 'Cash on Delivery'
             THEN 1 ELSE 0 END                                    AS reached_attempted,
        CASE WHEN c.authorised_datetime IS NOT NULL THEN 1 ELSE 0 END AS reached_authorised,
        CASE WHEN c.captured_datetime  IS NOT NULL THEN 1 ELSE 0 END AS reached_captured,
        CASE WHEN c.fulfilled_datetime IS NOT NULL THEN 1 ELSE 0 END AS reached_fulfilled
    FROM fact_checkout c
    JOIN dim_payment_method m
         ON c.initial_payment_method_key = m.payment_method_key
)

SELECT 1 AS stage_no, 'Checkout started' AS stage,
       COUNT(*) AS checkouts,
       CAST(SUM(cart_value) AS DECIMAL(16,2)) AS cart_value
FROM checkout_stages

UNION ALL
SELECT 2, 'Payment attempted',
       SUM(reached_attempted),
       CAST(SUM(CASE WHEN reached_attempted = 1 THEN cart_value ELSE 0 END) AS DECIMAL(16,2))
FROM checkout_stages

UNION ALL
SELECT 3, 'Authorised',
       SUM(reached_authorised),
       CAST(SUM(CASE WHEN reached_authorised = 1 THEN cart_value ELSE 0 END) AS DECIMAL(16,2))
FROM checkout_stages

UNION ALL
SELECT 4, 'Captured',
       SUM(reached_captured),
       CAST(SUM(CASE WHEN reached_captured = 1 THEN cart_value ELSE 0 END) AS DECIMAL(16,2))
FROM checkout_stages

UNION ALL
SELECT 5, 'Fulfilled',
       SUM(reached_fulfilled),
       CAST(SUM(CASE WHEN reached_fulfilled = 1 THEN cart_value ELSE 0 END) AS DECIMAL(16,2))
FROM checkout_stages

UNION ALL
SELECT 6, 'Revenue retained',
       SUM(reached_fulfilled),
       CAST(SUM(revenue_captured) AS DECIMAL(16,2))
FROM checkout_stages

ORDER BY stage_no;
------------------------------------------------------------------




USE VanyaPaymentsDB;

WITH checkout_stages AS (
    SELECT
        c.cart_value,
        CASE WHEN c.attempt_count > 0 OR m.method_name = 'Cash on Delivery'
             THEN 1 ELSE 0 END                                    AS reached_attempted,
        CASE WHEN c.authorised_datetime IS NOT NULL THEN 1 ELSE 0 END AS reached_authorised,
        CASE WHEN c.captured_datetime  IS NOT NULL THEN 1 ELSE 0 END AS reached_captured,
        CASE WHEN c.fulfilled_datetime IS NOT NULL THEN 1 ELSE 0 END AS reached_fulfilled
    FROM fact_checkout c
    JOIN dim_payment_method m
         ON c.initial_payment_method_key = m.payment_method_key
),

totals AS (
    SELECT
        COUNT(*)                                                          AS n_started,
        SUM(reached_attempted)                                            AS n_attempted,
        SUM(reached_authorised)                                           AS n_authorised,
        SUM(reached_captured)                                             AS n_captured,
        SUM(reached_fulfilled)                                            AS n_fulfilled,
        SUM(cart_value)                                                   AS v_started,
        SUM(CASE WHEN reached_attempted  = 1 THEN cart_value ELSE 0 END)  AS v_attempted,
        SUM(CASE WHEN reached_authorised = 1 THEN cart_value ELSE 0 END)  AS v_authorised,
        SUM(CASE WHEN reached_captured   = 1 THEN cart_value ELSE 0 END)  AS v_captured,
        SUM(CASE WHEN reached_fulfilled  = 1 THEN cart_value ELSE 0 END)  AS v_fulfilled
    FROM checkout_stages
)

SELECT 1 AS seq, 'Started -> Attempted' AS step,
       n_started - n_attempted AS checkouts_lost,
       CAST(100.0 * (n_started - n_attempted) / n_started AS DECIMAL(5,2)) AS pct_lost,
       CAST(v_started - v_attempted AS DECIMAL(16,2)) AS value_lost
FROM totals

UNION ALL
SELECT 2, 'Attempted -> Authorised',
       n_attempted - n_authorised,
       CAST(100.0 * (n_attempted - n_authorised) / n_attempted AS DECIMAL(5,2)),
       CAST(v_attempted - v_authorised AS DECIMAL(16,2))
FROM totals

UNION ALL
SELECT 3, 'Authorised -> Captured',
       n_authorised - n_captured,
       CAST(100.0 * (n_authorised - n_captured) / n_authorised AS DECIMAL(5,2)),
       CAST(v_authorised - v_captured AS DECIMAL(16,2))
FROM totals

UNION ALL
SELECT 4, 'Captured -> Fulfilled',
       n_captured - n_fulfilled,
       CAST(100.0 * (n_captured - n_fulfilled) / n_captured AS DECIMAL(5,2)),
       CAST(v_captured - v_fulfilled AS DECIMAL(16,2))
FROM totals

ORDER BY seq;