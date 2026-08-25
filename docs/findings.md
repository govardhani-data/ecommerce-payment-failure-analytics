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

Each prediction is stated so it can be proved wrong. Where a hedge would have been more comfortable, a specific claim has been made instead — a prediction
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

*(Note: the first funnel stage is labelled "checkout submitted" in the results
below. The original label "checkout started" overclaimed what the data measures —
see limitations.)*

**Answer: 79.01% of submitted checkouts are fulfilled, retaining 77.58% of cart
value. ₹65.7M of ₹292.9M is lost, and the largest leak by far is payment
decline.**

| Stage | Checkouts | Conversion | Cart value | Value retained |
|---|---|---|---|---|
| Checkout submitted | 200,000 | 100% | ₹292.9M | 100% |
| Payment attempted | 200,000 | 100% | ₹292.9M | 100% |
| Authorised | 176,000 | 88.00% | ₹252.0M | 86.03% |
| Captured | 162,775 | 81.39% | ₹234.5M | 80.05% |
| Fulfilled | 158,029 | 79.01% | ₹227.2M | 77.58% |

No loss appears between submission and attempt because every checkout in this
dataset commits to a payment method. Pre-payment abandonment is out of scope —
see limitations.

**Where the money goes.**

| Step | Lost | % of losses | Value lost | % of value lost |
|---|---|---|---|---|
| Attempted to Authorised | 24,000 | 57.2% | ₹40.9M | 62.3% |
| Authorised to Captured | 13,225 | 31.5% | ₹17.5M | 26.7% |
| Captured to Fulfilled | 4,746 | 11.3% | ₹7.2M | 11.0% |

**Prediction was wrong.** I expected the largest count loss before payment was
attempted, and the largest value loss after authorisation. Neither held — payment
decline is the largest leak on both measures.

**The value insight sits elsewhere.** Checkouts lost at the payment decline stage
average ₹1,705 against an overall average of ₹1,465 — 16% higher. Failed payments
are disproportionately expensive ones. The reason connects to Q4: cards carry the
largest baskets and fail most often, so the highest-value orders are landing on
the least reliable method.

**Recommendation.** 62% of leaked revenue is lost at a single step, so anything
that improves payment authorisation addresses nearly two thirds of the problem.
Q3 and Q4 quantify which lever — retry logic or payment method routing — recovers
the most.

---

### Q2. Which payment failures create the greatest financial impact?

Rank failure reasons by count, then by revenue at risk, then compare.

**Prediction.** Insufficient funds will rank first by count. Authentication
failures will rank first by revenue at risk. The two top-three lists will not
match, because higher-value orders are more often paid by card, and cards are
the method that triggers authentication.

**Answer:** **Answer: Insufficient funds is the single most expensive failure reason
(₹8.25M, 20.2% of lost payment revenue), and issuer declines are the most
expensive category (₹17.77M, 43.4%). Ranking by count and by money produces
almost the same order. The finding that matters is that 86.8% of the lost money
died on a retryable failure.**

Scope: the ₹40,923,725 lost between payment attempted and authorised (Q1).
Each checkout is attributed to the reason on its **last** failed attempt — the
one on screen when the customer stopped. Alternatives (first failure, or
splitting across all failures) were rejected: first-failure ignores where they
actually gave up, and splitting double-counts and breaks reconciliation to Q1.

**Top ten reasons by revenue lost.**

| # | Reason | Class | Retryable | Failed attempts | Checkouts lost | Value lost | Avg lost basket | % of value | Rank by count |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Insufficient funds | Soft | Yes | 9,683 | 4,827 | ₹8,253,944 | ₹1,710 | 20.17% | 1 |
| 2 | OTP timeout | Abandoned | Yes | 4,768 | 2,376 | ₹4,721,030 | ₹1,987 | 11.54% | 2 |
| 3 | 3DS authentication failed | Soft | Yes | 2,611 | 1,304 | ₹2,487,186 | ₹1,907 | 6.08% | 4 |
| 4 | Transaction limit exceeded | Soft | Yes | 2,714 | 1,408 | ₹2,225,924 | ₹1,581 | 5.44% | 3 |
| 5 | Incorrect OTP | Soft | Yes | 2,206 | 1,110 | ₹2,222,960 | ₹2,003 | 5.43% | 8 |
| 6 | Do not honour | Soft | Yes | 2,209 | 1,085 | ₹2,167,393 | ₹1,998 | 5.30% | 7 |
| 7 | Bank unavailable | Operational | Yes | 2,490 | 1,262 | ₹1,903,918 | ₹1,509 | 4.65% | 5 |
| 8 | Gateway timeout | Operational | Yes | 1,857 | 957 | ₹1,837,102 | ₹1,920 | 4.49% | 9 |
| 9 | UPI request expired | Abandoned | Yes | 2,366 | 1,178 | ₹1,598,183 | ₹1,357 | 3.91% | 6 |
| 10 | Session expired | Abandoned | No | 1,710 | 896 | ₹1,553,475 | ₹1,734 | 3.80% | 11 |

**The two rankings agree.** Ranks 1 and 2 are identical on both lists. The largest
movement across all 26 reasons is four places. Counts vary 27× (9,683 to 355)
while average lost basket varies less than 2× (₹2,114 to ₹1,100), so volume
dominates the product and the money ranking collapses onto the count ranking.

This is a real result, not a failed analysis. It means a payments team here can
prioritise by volume — which is cheaper to measure — without misallocating
effort. It would not be safe to assume that on real data, where basket values
vary far more by failure reason than this model produces.

**By category.**

| Category | Reasons | Checkouts lost | Value lost | Share |
|---|---|---|---|---|
| Issuer | 10 | 10,227 | ₹17,766,748 | 43.41% |
| Authentication | 4 | 5,358 | ₹10,535,199 | 25.74% |
| Customer | 6 | 4,190 | ₹5,751,780 | 14.05% |
| Technical | 4 | 3,031 | ₹4,772,108 | 11.66% |
| Gateway | 2 | 1,194 | ₹2,097,890 | 5.13% |

Category size is a design decision — Issuer holds 10 of 26 reasons, Gateway holds
2 — so these totals summarise where money sits rather than rank root causes.

**By recoverability — the finding that matters.**

| Retryable | Checkouts lost | Value lost | Share |
|---|---|---|---|
| Yes | 20,973 | ₹35,529,607 | 86.82% |
| No | 3,027 | ₹5,394,118 | 13.18% |

**86.8% of the money lost at the payment step died on a failure another attempt could have survived.** 

Only ₹5.39M was structurally unrecoverable — expired and
blocked cards, closed accounts, fraud declines, KYC restrictions. Separately,
11,667 checkouts already hit a failure and converted anyway, so recovery is
happening; Q3 measures how much more is available.

**Prediction verdict — two of three claims wrong.**

*Correct:* insufficient funds ranks first by count.

*Wrong:* authentication does not rank first by revenue at risk. Not as a single
reason (insufficient funds leads at 20.2%), and not as a category (issuer leads at
43.4% against authentication's 25.7%).

*Technically correct, but far weaker than predicted:* the top-three lists do
differ, but by a single swap at position three between two reasons one place
apart. This was predicted as a divergence and turned out to be a hairline.

*The reasoning behind the prediction did hold.* Every authentication reason has an
above-average lost basket — incorrect OTP ₹2,003, OTP timeout ₹1,987,
authentication service down ₹1,944, 3DS ₹1,907, against ₹1,705 overall. High-value
orders genuinely do get stuck in authentication. That effect was real but too
small to overcome insufficient funds' volume.

**Recommendation.** Two reasons account for 31.7% of lost payment revenue and
five account for 48.7%, so effort concentrates well. But the ranking is not the
action — 86.8% retryability is. Before optimising any individual reason, Q3 establishes how much of that ₹35.5M a better retry path actually recovers.

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

This dataset is synthetic, produced by `src/generate_checkouts.py`. No client or production data has been used. Every behavioural parameter is an explicit assumption set in one configuration block at the top of that script.

## Deliberately out of scope

Promotions and discounts, refunds, chargebacks, multiple delivery attempts, and gateway routing detail. Each is a reasonable extension; none is needed by the five questions above.

---

## Limitations

What this analysis cannot tell you. This section grows as each question is
answered.

**The data is synthetic.** Every row was generated by the scripts in `src/`. No real customer, payment, or merchant data was used. Every behavioural assumption —
success rates by payment method, retry willingness, decline reason mix, fulfilment failure rates — is an explicit, editable value at the top of a generator script.
This analysis quantifies the consequences of those assumptions. It cannot validate whether the assumptions themselves match reality. That requires real
payment data.

**Pre-payment abandonment is not modelled.** The funnel begins at checkout submission, not at cart creation or checkout page view. Customers who abandon before committing to pay are outside this dataset. A complete revenue funnel would include browse-to-cart and cart-to-checkout conversion, which requires web
analytics data rather than payment records.

---