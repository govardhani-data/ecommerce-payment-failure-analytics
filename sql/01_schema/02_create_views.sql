USE VanyaPaymentsDB;
GO

-- ============================================================
-- vw_checkout_enriched
--
-- Flattens attempt-level facts onto the checkout row so the
-- BI layer sees one fact table and a clean star schema.
--
-- Without this, dim_payment_method and dim_failure_reason each
-- connect to two fact tables, creating ambiguous relationship
-- paths that Power BI cannot resolve.
-- ============================================================

IF OBJECT_ID('vw_checkout_enriched', 'V') IS NOT NULL
    DROP VIEW vw_checkout_enriched;
GO

CREATE VIEW vw_checkout_enriched AS
WITH attempt_summary AS (
    SELECT
        checkout_id,
        COUNT(DISTINCT payment_method_key)              AS methods_used,
        MIN(CASE WHEN failure_reason_key IS NULL
                 THEN attempt_seq END)                  AS succeeded_on_attempt,
        MIN(CASE WHEN attempt_seq = 1
                 THEN payment_method_key END)           AS first_attempt_method_key,
        MAX(CASE WHEN attempt_seq = 1
                  AND failure_reason_key IS NULL
                 THEN 1 ELSE 0 END)                     AS first_attempt_succeeded,
        MIN(CASE WHEN failure_reason_key IS NOT NULL
                 THEN attempt_seq END)                  AS first_failure_attempt_seq
    FROM fact_payment_attempt
    GROUP BY checkout_id
),
first_failure AS (
    SELECT
        a.checkout_id,
        a.failure_reason_key AS first_failure_reason_key
    FROM fact_payment_attempt AS a
    INNER JOIN attempt_summary AS s
        ON  a.checkout_id  = s.checkout_id
        AND a.attempt_seq  = s.first_failure_attempt_seq
)
SELECT
    c.checkout_key,
    c.checkout_id,
    c.customer_key,
    c.created_date_key,
    c.created_datetime,
    c.device_key,
    c.initial_payment_method_key,
    c.cart_value,
    c.item_count,
    c.is_first_time_customer,
    c.stage_reached,
    c.attempt_count,
    c.authorised_datetime,
    c.captured_datetime,
    c.fulfilled_datetime,
    c.final_failure_reason_key,
    c.fulfilment_outcome_key,
    c.is_duplicate_charge,
    c.duplicate_charge_amount,
    c.revenue_captured,

    -- flags derived from the attempt table
    ISNULL(s.methods_used, 0)                           AS methods_used,
    s.succeeded_on_attempt,
    s.first_attempt_method_key,
    ISNULL(s.first_attempt_succeeded, 0)                AS first_attempt_succeeded,
    ff.first_failure_reason_key,

    -- convenience flags for DAX
    CASE WHEN c.authorised_datetime IS NOT NULL
         THEN 1 ELSE 0 END                              AS is_authorised,
    CASE WHEN c.captured_datetime  IS NOT NULL
         THEN 1 ELSE 0 END                              AS is_captured,
    CASE WHEN c.fulfilled_datetime IS NOT NULL
         THEN 1 ELSE 0 END                              AS is_fulfilled,
    CASE WHEN s.methods_used > 1
         THEN 1 ELSE 0 END                              AS switched_method
FROM fact_checkout AS c
LEFT JOIN attempt_summary AS s ON c.checkout_id = s.checkout_id
LEFT JOIN first_failure   AS ff ON c.checkout_id = ff.checkout_id;
GO