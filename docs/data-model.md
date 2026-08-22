# Data Model — Vanya Beauty Payment Analysis

## Grain

The most important statement in this document.

- **`fact_checkout`** — one row per checkout session, successful or not.
- **`fact_payment_attempt`** — one row per payment attempt.

A checkout is not an order. An order only exists once payment succeeds, but this
analysis is about the ones that did not. Storing only orders would leave the
funnel without a denominator.

## Why two fact tables

A single checkout can have several payment attempts, and the customer may switch
payment method between them.

```
Checkout VB0018472   cart value ₹2,340
    Attempt 1   UPI    failed  - insufficient funds
    Attempt 2   UPI    failed  - insufficient funds
    Attempt 3   Card   authorised
```

One checkout, three attempts. Three attempts cannot fit in a one-row-per-checkout
table. And because the method changed, payment method must be recorded on the
attempt as well as on the checkout.

## Schema shape

Star schema. Every dimension connects directly to a fact table. No dimension
connects to another dimension.

```
                          dim_date
                              |
      dim_customer            |            dim_device
                 \            |            /
                  \           |           /
   dim_payment_    +---- fact_checkout ---+---- dim_fulfilment_
   method         /           |           \     outcome
                 /            |            \
    dim_failure_             |
    reason                   |
                             |
                  fact_payment_attempt
                   /     |      |     \
                  /      |      |      \
        dim_payment_  dim_    dim_   dim_failure_
        method      gateway  bank     reason

```

Two fact tables sharing dimensions is a galaxy (or constellation) schema.

---

## fact_checkout

Grain: one checkout session.

| Column | Type | Notes |
|---|---|---|
| `checkout_key` | INT | Surrogate primary key |
| `checkout_id` | VARCHAR(20) | Business ID, e.g. VB0018472. Unique |
| `customer_key` | INT | FK → dim_customer |
| `created_date_key` | INT | FK → dim_date |
| `created_datetime` | DATETIME2 | |
| `device_key` | INT | FK → dim_device |
| `initial_payment_method_key` | INT | FK → dim_payment_method. What they chose first |
| `final_payment_method_key` | INT | FK → dim_payment_method. What worked. NULL if none did |
| `cart_value` | DECIMAL(10,2) | Rupees |
| `item_count` | TINYINT | |
| `is_first_time_customer` | BIT | |
| `stage_reached` | VARCHAR(20) | started / attempted / authorised / captured / fulfilled |
| `attempt_count` | TINYINT | 0 for cash on delivery |
| `first_attempt_datetime` | DATETIME2 | NULL if never attempted |
| `authorised_datetime` | DATETIME2 | NULL if never authorised |
| `captured_datetime` | DATETIME2 | NULL if never captured |
| `fulfilled_datetime` | DATETIME2 | NULL if never fulfilled |
| `final_failure_reason_key` | INT | FK → dim_failure_reason. NULL if it succeeded |
| `fulfilment_outcome_key` | INT | FK → dim_fulfilment_outcome. NULL if never captured |
| `is_duplicate_charge` | BIT | |
| `duplicate_charge_amount` | DECIMAL(10,2) | NULL unless duplicated |
| `revenue_captured` | DECIMAL(10,2) | 0 if never captured |

**Revenue at risk is deliberately not stored.** It is calculated in SQL as
`cart_value` where `captured_datetime IS NULL`. Keeping the definition in the
query rather than the table means it is visible and defensible rather than
buried.

---

## fact_payment_attempt

Grain: one payment attempt. Cash-on-delivery checkouts have no rows here.

| Column | Type | Notes |
|---|---|---|
| `attempt_key` | INT | Surrogate primary key |
| `checkout_id` | VARCHAR(20) | FK → fact_checkout |
| `attempt_seq` | TINYINT | 1, 2, 3... within a checkout |
| `attempted_datetime` | DATETIME2 | |
| `payment_method_key` | INT | FK. May differ between attempts |
| `gateway_key` | INT | FK → dim_gateway |
| `bank_key` | INT | FK → dim_bank. NULL for UPI and wallet |
| `attempt_amount` | DECIMAL(10,2) | |
| `result` | VARCHAR(20) | success / soft_decline / hard_decline / timeout / abandoned |
| `failure_reason_key` | INT | FK. NULL if successful |
| `auth_required` | BIT | Was 3-D Secure triggered |
| `auth_completed` | BIT | NULL if not required |
| `response_time_ms` | INT | |

`attempt_seq` plus `checkout_id` is what makes the retry analysis possible.
Answering "did the retry work, and on which attempt" requires looking at the
sequence within each checkout, which is a window function.

---

## The eight dimensions

### dim_date
`date_key`, `full_date`, `day_of_week`, `day_name`, `iso_year`, `week_of_year`,
`month`, `month_name`, `quarter`, `year`, `is_weekend`, `is_holiday`,
`is_working_day`, `is_month_end`

`is_month_end` is included deliberately. Indian salaries are typically paid at
month end, so insufficient-funds failures are expected to cluster in the days
before payday. Without this column that pattern cannot be tested.

`iso_year` is stored alongside `week_of_year` because under the ISO standard the
first days of January can belong to the previous year's final week. Weekly
grouping must use both.

### dim_customer
`customer_key`, `customer_id`, `city`, `state`, `city_tier` (Metro / Tier 2 / Tier 3)

### dim_payment_method
`payment_method_key`, `method_name` (UPI / Card / Netbanking / Wallet / Cash on
Delivery), `method_type` (Online / Offline), `requires_auth`

### dim_failure_reason
`failure_reason_key`, `failure_reason`, `failure_class`, `retryable_flag`,
`failure_category`

Three separate attributes because they answer three different questions:

| Column | Values | Answers |
|---|---|---|
| `failure_class` | Soft / Hard / Operational / Abandoned | Is this a decline at all? |
| `retryable_flag` | Yes / No / Unknown | Could a retry ever work? |
| `failure_category` | Issuer / Authentication / Technical / Customer / Gateway | Whose fault is it? |

Payment method is deliberately **not** stored here. Which methods a reason
applies to is a relationship, not an attribute of the reason.

### dim_gateway
`gateway_key`, `gateway_name`

### dim_bank
`bank_key`, `bank_name`, `bank_type` (Public sector / Private / Small finance)

### dim_device
`device_key`, `device_type` (Mobile app / Mobile web / Desktop), `os`

### dim_fulfilment_outcome
`fulfilment_outcome_key`, `outcome_name`, `outcome_category`

Outcomes: Fulfilled, Cancelled by customer, Cancelled - inventory unavailable,
Cancelled - pricing error, COD refused at delivery, COD customer unavailable,
Capture failed.

---

## Why surrogate keys

Every dimension has an integer `_key` alongside its business value. Integer joins
are faster than text, and business values change — if a gateway is renamed, a
join on the name breaks history while a join on the key does not.

---

## Completeness check

Every question checked against the model before any data was generated. This step
was skipped in the previous project and cost three full regenerations.

| Question | Needs | Where it lives |
|---|---|---|
| Q1 — funnel leakage | Stage reached, and value | `fact_checkout.stage_reached`, `cart_value` |
| Q2 — failure by money | Final failure reason at order level | `final_failure_reason_key`, `cart_value` |
| Q3 — retry recovery | Full sequence of attempts per checkout | `fact_payment_attempt.attempt_seq`, `result` |
| Q4 — payment method | Method, success, value together | `initial/final_payment_method_key`, `cart_value` |
| Q5 — after payment | Authorised vs captured vs fulfilled, duplicates | `authorised_datetime`, `captured_datetime`, `fulfilment_outcome_key`, `is_duplicate_charge` |
| Card auth drill-down | Was 3DS triggered and completed, which bank | `auth_required`, `auth_completed`, `bank_key` |
| Method switching | Did they change method between attempts | `fact_payment_attempt.payment_method_key` per attempt |
| Payday effect | Failures clustered before salary day | `dim_date.is_month_end` |

Every question has a home. Nothing is missing.

---

## Deliberately excluded

Promotions and discounts, refunds, chargebacks, multiple delivery attempts, and
gateway routing detail. Each is a reasonable extension; none is needed by the
five questions.