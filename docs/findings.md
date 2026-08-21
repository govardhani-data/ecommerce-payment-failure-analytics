# Findings — Vanya Beauty Payment Failure Analysis

> Status: questions defined, no data generated yet.
> Answers filled in as each is completed.

**The business.** Vanya Beauty is an Indian direct-to-consumer brand selling
beauty and personal care products online. Customers pay by UPI, card,
netbanking, wallet, or cash on delivery.

**The problem.** Revenue leaks out of the checkout process in several places.
Management wants to know where, how much, and which leaks are worth fixing.

---

## Definitions used throughout

**Revenue at risk** — the value of checkouts that never reached captured status,
counted once per checkout, attributed to the failure reason on the final
attempt. Deliberately not measured per attempt: a ₹2,000 order that failed twice
then succeeded would otherwise be recorded as ₹4,000 of loss, when the actual
loss is zero.

**Revenue recovered** — the value of checkouts that failed at least once and
eventually succeeded. Never added to revenue at risk; they answer opposite
questions.

**Checkout** — a customer starting the payment process. May or may not become an
order.

**Soft decline** — refused, but a retry might work.
**Hard decline** — refused permanently; a retry will never work.

---

## On the predictions below

Each prediction is stated so it can be proved wrong. Where a hedge would have
been more comfortable, a specific claim has been made instead — a prediction
that cannot fail teaches nothing when checked against the result.

---

## The questions

### Q1. Where does revenue leak across the checkout-to-revenue funnel?

Of every 100 customers who start checkout, how many end with paid, fulfilled
revenue? Which stage loses the most customers, and which loses the most money?

**Prediction — and these are two different answers.**
By **count**, the largest drop will be between checkout started and payment
attempted: customers who abandon before they ever try to pay.
By **value**, the largest drop will be after authorisation — orders that were
approved but never became fulfilled revenue — because higher-value orders are
more likely to be cancelled or fail fulfilment.

**Answer:** _pending_

---

### Q2. Which payment failures create the greatest financial impact?

Rank failure reasons by count, then by revenue at risk, then compare.

**Prediction.** Insufficient funds will rank first by count. Authentication
failures will rank first by revenue at risk. The two top-three lists will not
match, because higher-value orders are more often paid by card, and cards are
the method that triggers authentication.

**Answer:** _pending_

---

### Q3. How much failed-payment revenue is realistically recoverable?

Split failures into retryable and non-retryable. Measure whether retries worked,
and on which attempt.

**Prediction.** More than half of all recovered revenue will come from the first
retry. Recovery from the third attempt onwards will be under 5% of the total
recovered. Among soft declines specifically, switching payment method will have
a higher success rate than retrying the same method.

**Answer:** _pending_

---

### Q4. Which payment method produces the best business outcome?

Success rate, average order value and total revenue together — not simply which
method fails least.

**Prediction.** UPI will have the highest success rate. Cards will have the
highest average order value. Cards will contribute more total revenue than UPI
despite failing more often — meaning a recommendation based on success rate
alone would reduce failures and reduce revenue at the same time.

**Answer:** _pending_

---

### Q5. After payment succeeds, how much revenue still fails to materialise?

Authorised but never captured. Captured but not fulfilled. Duplicate charges.
Cash-on-delivery parcels refused at the door.

**Prediction — again two different answers.**
By **value**, cash-on-delivery refusal will be the largest post-payment leak.
By **incident**, duplicate charges will affect under 1% of checkouts, but their
average value will sit above the overall average — making them rare, expensive,
and worse than the number suggests, because each one also creates a refund and a
support ticket.

**Answer:** _pending_

---

## Note on data

This dataset is synthetic, produced by `src/generate_checkouts.py`. No client or
production data has been used. Every behavioural parameter is an explicit
assumption set in one configuration block at the top of that script.

## Deliberately out of scope

Promotions and discounts, refunds, chargebacks, multiple delivery attempts, and
gateway routing detail. Each is a reasonable extension; none is needed by the
five questions above.