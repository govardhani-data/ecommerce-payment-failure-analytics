USE VanyaPaymentsDB;

/* Data quality report. Run after any reload.
   Every row states what was measured and what it should be. */

SELECT 1 AS seq, 'Checkout row count' AS check_name,
       CAST((SELECT COUNT(*) FROM fact_checkout) AS DECIMAL(14,2)) AS actual,
       '200000' AS expected

UNION ALL SELECT 2, 'Payment attempt row count',
       CAST((SELECT COUNT(*) FROM fact_payment_attempt) AS DECIMAL(14,2)), 'approx 189000'

UNION ALL SELECT 3, 'Checkouts with a captured date but zero revenue',
       CAST((SELECT COUNT(*) FROM fact_checkout
             WHERE captured_datetime IS NOT NULL AND revenue_captured = 0) AS DECIMAL(14,2)),
       'approx 4700 - refunded after fulfilment failed'

UNION ALL SELECT 4, 'Checkouts with revenue but no capture (impossible)',
       CAST((SELECT COUNT(*) FROM fact_checkout
             WHERE captured_datetime IS NULL AND revenue_captured > 0) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 5, 'Captured before authorised (impossible)',
       CAST((SELECT COUNT(*) FROM fact_checkout
             WHERE captured_datetime < authorised_datetime) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 6, 'Attempts pointing at a missing checkout',
       CAST((SELECT COUNT(*) FROM fact_payment_attempt a
             LEFT JOIN fact_checkout c ON a.checkout_id = c.checkout_id
             WHERE c.checkout_id IS NULL) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 7, 'Checkouts whose attempts do not start at 1',
       CAST((SELECT COUNT(*) FROM (
                SELECT checkout_id, MIN(attempt_seq) AS lowest
                FROM fact_payment_attempt GROUP BY checkout_id
             ) x WHERE x.lowest <> 1) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 8, 'Successful attempts carrying a failure reason',
       CAST((SELECT COUNT(*) FROM fact_payment_attempt
             WHERE result = 'success' AND failure_reason_key IS NOT NULL) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 9, 'Cash-on-delivery checkouts with payment attempts',
       CAST((SELECT COUNT(*) FROM fact_checkout c
             JOIN dim_payment_method m ON c.initial_payment_method_key = m.payment_method_key
             WHERE m.method_name = 'Cash on Delivery' AND c.attempt_count > 0) AS DECIMAL(14,2)), '0'

UNION ALL SELECT 10, 'Percent of checkouts fulfilled',
       CAST((SELECT 100.0 * SUM(CASE WHEN stage_reached = 'fulfilled' THEN 1 ELSE 0 END)
                    / COUNT(*) FROM fact_checkout) AS DECIMAL(14,2)), 'approx 79'

UNION ALL SELECT 11, 'Revenue retained as percent of cart value',
       CAST((SELECT 100.0 * SUM(revenue_captured) / SUM(cart_value)
             FROM fact_checkout) AS DECIMAL(14,2)), 'approx 76 to 80'

UNION ALL SELECT 12, 'Duplicate charge percent',
       CAST((SELECT 100.0 * SUM(CAST(is_duplicate_charge AS INT)) / COUNT(*)
             FROM fact_checkout) AS DECIMAL(14,2)), 'approx 0.50'

ORDER BY seq;