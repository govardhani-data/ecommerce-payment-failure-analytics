/* ===========================================================================
   01_create_tables.sql
   Vanya Beauty payment analysis - full schema.
   Safe to re-run: everything is dropped first, in reverse dependency order.
   =========================================================================== */
--1. Clearing the Decks First

USE VanyaPaymentsDB;
GO

DROP TABLE IF EXISTS fact_payment_attempt;
DROP TABLE IF EXISTS fact_checkout;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_payment_method;
DROP TABLE IF EXISTS dim_failure_reason;
DROP TABLE IF EXISTS dim_gateway;
DROP TABLE IF EXISTS dim_bank;
DROP TABLE IF EXISTS dim_device;
DROP TABLE IF EXISTS dim_fulfilment_outcome;
GO

--Creating 8 LOOKUP(Dimension) Tables

CREATE TABLE dim_date (
    date_key        INT          NOT NULL PRIMARY KEY,
    full_date       DATE         NOT NULL,
    day_of_week     TINYINT      NOT NULL,
    day_name        VARCHAR(9)   NOT NULL,
    iso_year        SMALLINT     NOT NULL,
    week_of_year    TINYINT      NOT NULL,
    month           TINYINT      NOT NULL,
    month_name      VARCHAR(9)   NOT NULL,
    quarter         TINYINT      NOT NULL,
    year            SMALLINT     NOT NULL,
    is_weekend      BIT          NOT NULL,
    is_holiday      BIT          NOT NULL,
    is_working_day  BIT          NOT NULL,
    is_month_end    BIT          NOT NULL
);

CREATE TABLE dim_customer (
    customer_key  INT          NOT NULL PRIMARY KEY,
    customer_id   VARCHAR(20)  NOT NULL UNIQUE,
    city          VARCHAR(40)  NOT NULL,
    state         VARCHAR(40)  NOT NULL,
    city_tier     VARCHAR(10)  NOT NULL
);

CREATE TABLE dim_payment_method (
    payment_method_key  INT          NOT NULL PRIMARY KEY,
    method_name         VARCHAR(30)  NOT NULL,
    method_type         VARCHAR(10)  NOT NULL,
    requires_auth       BIT          NOT NULL
);

CREATE TABLE dim_failure_reason (
    failure_reason_key  INT          NOT NULL PRIMARY KEY,
    failure_reason      VARCHAR(60)  NOT NULL,
    failure_class       VARCHAR(20)  NOT NULL,
    retryable_flag      VARCHAR(10)  NOT NULL,
    failure_category    VARCHAR(20)  NOT NULL,

    CONSTRAINT ck_failure_class
        CHECK (failure_class IN ('Soft','Hard','Operational','Abandoned')),
    CONSTRAINT ck_retryable
        CHECK (retryable_flag IN ('Yes','No','Unknown')),
    CONSTRAINT ck_failure_category
        CHECK (failure_category IN ('Issuer','Authentication','Technical','Customer','Gateway'))
);

CREATE TABLE dim_gateway (
    gateway_key   INT          NOT NULL PRIMARY KEY,
    gateway_name  VARCHAR(30)  NOT NULL
);

CREATE TABLE dim_bank (
    bank_key   INT          NOT NULL PRIMARY KEY,
    bank_name  VARCHAR(50)  NOT NULL,
    bank_type  VARCHAR(25)  NOT NULL
);

CREATE TABLE dim_device (
    device_key   INT          NOT NULL PRIMARY KEY,
    device_type  VARCHAR(20)  NOT NULL,
    os           VARCHAR(20)  NOT NULL
);

CREATE TABLE dim_fulfilment_outcome (
    fulfilment_outcome_key  INT          NOT NULL PRIMARY KEY,
    outcome_name            VARCHAR(40)  NOT NULL,
    outcome_category        VARCHAR(20)  NOT NULL
);
GO

--fact_checkout

CREATE TABLE fact_checkout (
    checkout_key                INT           NOT NULL PRIMARY KEY,
    checkout_id                 VARCHAR(20)   NOT NULL UNIQUE,

    customer_key                INT           NOT NULL,
    created_date_key            INT           NOT NULL,
    created_datetime            DATETIME2     NOT NULL,
    device_key                  INT           NOT NULL,

    initial_payment_method_key  INT           NOT NULL,
    final_payment_method_key    INT           NULL,

    cart_value                  DECIMAL(10,2) NOT NULL,
    item_count                  TINYINT       NOT NULL,
    is_first_time_customer      BIT           NOT NULL,

    stage_reached               VARCHAR(20)   NOT NULL,
    attempt_count               TINYINT       NOT NULL,

    first_attempt_datetime      DATETIME2     NULL,
    authorised_datetime         DATETIME2     NULL,
    captured_datetime           DATETIME2     NULL,
    fulfilled_datetime          DATETIME2     NULL,

    final_failure_reason_key    INT           NULL,
    fulfilment_outcome_key      INT           NULL,

    is_duplicate_charge         BIT           NOT NULL,
    duplicate_charge_amount     DECIMAL(10,2) NULL,

    revenue_captured            DECIMAL(10,2) NOT NULL,

    CONSTRAINT fk_checkout_customer FOREIGN KEY (customer_key)               REFERENCES dim_customer(customer_key),
    CONSTRAINT fk_checkout_date     FOREIGN KEY (created_date_key)           REFERENCES dim_date(date_key),
    CONSTRAINT fk_checkout_device   FOREIGN KEY (device_key)                 REFERENCES dim_device(device_key),
    CONSTRAINT fk_checkout_method1  FOREIGN KEY (initial_payment_method_key) REFERENCES dim_payment_method(payment_method_key),
    CONSTRAINT fk_checkout_method2  FOREIGN KEY (final_payment_method_key)   REFERENCES dim_payment_method(payment_method_key),
    CONSTRAINT fk_checkout_reason   FOREIGN KEY (final_failure_reason_key)   REFERENCES dim_failure_reason(failure_reason_key),
    CONSTRAINT fk_checkout_outcome  FOREIGN KEY (fulfilment_outcome_key)     REFERENCES dim_fulfilment_outcome(fulfilment_outcome_key),

    CONSTRAINT ck_checkout_stage
        CHECK (stage_reached IN ('started','attempted','authorised','captured','fulfilled')),

    CONSTRAINT ck_checkout_cart_positive
        CHECK (cart_value > 0),

    CONSTRAINT ck_checkout_time_forward
        CHECK (captured_datetime IS NULL OR captured_datetime >= created_datetime),

    CONSTRAINT ck_checkout_auth_before_capture
        CHECK (captured_datetime IS NULL OR authorised_datetime IS NULL
               OR captured_datetime >= authorised_datetime),

    CONSTRAINT ck_checkout_revenue_needs_capture
        CHECK (captured_datetime IS NOT NULL OR revenue_captured = 0)
);
GO

CREATE TABLE fact_payment_attempt (
    attempt_key         INT           NOT NULL PRIMARY KEY,
    checkout_id         VARCHAR(20)   NOT NULL,
    attempt_seq         TINYINT       NOT NULL,
    attempted_datetime  DATETIME2     NOT NULL,

    payment_method_key  INT           NOT NULL,
    gateway_key         INT           NOT NULL,
    bank_key            INT           NULL,

    attempt_amount      DECIMAL(10,2) NOT NULL,
    result              VARCHAR(20)   NOT NULL,
    failure_reason_key  INT           NULL,

    auth_required       BIT           NOT NULL,
    auth_completed      BIT           NULL,
    response_time_ms    INT           NOT NULL,

    CONSTRAINT fk_attempt_checkout FOREIGN KEY (checkout_id)        REFERENCES fact_checkout(checkout_id),
    CONSTRAINT fk_attempt_method   FOREIGN KEY (payment_method_key) REFERENCES dim_payment_method(payment_method_key),
    CONSTRAINT fk_attempt_gateway  FOREIGN KEY (gateway_key)        REFERENCES dim_gateway(gateway_key),
    CONSTRAINT fk_attempt_bank     FOREIGN KEY (bank_key)           REFERENCES dim_bank(bank_key),
    CONSTRAINT fk_attempt_reason   FOREIGN KEY (failure_reason_key) REFERENCES dim_failure_reason(failure_reason_key),

    CONSTRAINT ck_attempt_seq_positive
        CHECK (attempt_seq >= 1),

    CONSTRAINT ck_attempt_result
        CHECK (result IN ('success','soft_decline','hard_decline','timeout','abandoned')),

    CONSTRAINT ck_attempt_amount_positive
        CHECK (attempt_amount > 0),

    CONSTRAINT ck_attempt_reason_matches_result
        CHECK ((result = 'success' AND failure_reason_key IS NULL)
            OR (result <> 'success' AND failure_reason_key IS NOT NULL)),

    CONSTRAINT ck_attempt_auth_logic
        CHECK (auth_required = 1 OR auth_completed IS NULL)
);
GO
--fact_payment_attempts


CREATE INDEX ix_checkout_date          ON fact_checkout (created_date_key);
CREATE INDEX ix_checkout_customer      ON fact_checkout (customer_key);
CREATE INDEX ix_checkout_stage         ON fact_checkout (stage_reached);
CREATE INDEX ix_checkout_final_method  ON fact_checkout (final_payment_method_key);
CREATE INDEX ix_attempt_checkout       ON fact_payment_attempt (checkout_id);
CREATE INDEX ix_attempt_method         ON fact_payment_attempt (payment_method_key);
CREATE INDEX ix_attempt_reason         ON fact_payment_attempt (failure_reason_key);
GO

PRINT 'Schema created successfully.';