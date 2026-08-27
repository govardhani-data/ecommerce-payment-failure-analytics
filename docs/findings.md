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

One clarification matters for reading the rest of this document: the ₹40.9M is
what remains **after** retries have already happened. Q3 shows that retries
separately rescued ₹19.79M that never entered this funnel loss at all. The ₹40.9M
is the money that died despite customers having the chance to try again.

---


### Q2. Which payment failures create the greatest financial impact?

Rank failure reasons by count, then by revenue at risk, then compare.

**Prediction.** Insufficient funds will rank first by count. Authentication
failures will rank first by revenue at risk. The two top-three lists will not
match, because higher-value orders are more often paid by card, and cards are
the method that triggers authentication.

**Answer: Insufficient funds is the single most expensive failure reason
(₹8.25M, 20.2% of lost payment revenue), and issuer declines are the most
expensive category (₹17.77M, 43.4%). Ranking by count and by money produces
almost the same order. The finding that matters is that 86.8% of the lost money
died on a retryable failure.**

Scope: the ₹40,923,725 lost between payment attempted and authorised (Q1).
Each checkout is attributed to the reason on its **last** failed attempt — the
one on screen when the customer stopped. Alternatives were rejected:
first-failure ignores where they actually gave up, and splitting the value across
all failures double-counts and breaks reconciliation to Q1.

**Top ten reasons by revenue lost.**

| # | Reason | Class | Retryable | Failed attempts | Checkouts lost | Value lost | Avg lost basket | % of value | Rank by count |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Insufficient funds | Soft | Yes | 9,683 | 4,827 | ₹8,253,944 | ₹1,710 | 20.17% | 1 |
| 2 | OTP timeout | Abandoned | Yes | 4,768 | 2,376 | ₹4,721,030 | ₹1987 | 11.54% | 2 |
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
dominates and the money ranking lands on the same order as the count ranking

This is a real result, not a failed analysis. It means a payments team here can
prioritise by volume — which is cheaper to measure — without misallocating
effort. It would not be safe to assume the same on real data, where basket values
vary far more by failure reason than this model produces.

**By category.**

| Category | Reasons | Checkouts lost | Value lost | Share |
|---|---|---|---|---|
| Issuer | 10 | 10,227 | ₹17,766,748 | 43.41% |
| Authentication | 4 | 5,358 | ₹10,535,199 | 25.74% |
| Customer | 6 | 4,190 | ₹5,751,780 | 14.05% |
| Technical | 4 | 3,031 | ₹4,772,108 | 11.66% |
| Gateway | 2 | 1,194 | ₹2,097,890 | 5.13% |

Category size is a design decision — Issuer holds 10 of the 26 reasons, Gateway
holds 2 — so these totals summarise where money sits rather than rank root
causes.

**By recoverability — the finding that matters.**

| Retryable | Checkouts lost | Value lost | Share |
|---|---|---|---|
| Yes | 20,973 | ₹35,529,607 | 86.82% |
| No | 3,027 | ₹5,394,118 | 13.18% |

**86.8% of the money lost at the payment step died on a failure another attempt
could have survived.** Only ₹5.39M was structurally unrecoverable — expired and
blocked cards, closed accounts, fraud declines, KYC restrictions.

**Prediction verdict — two of three claims wrong.**

*Correct:* insufficient funds ranks first by count.

*Wrong:* authentication does not rank first by revenue at risk. Not as a single
reason (insufficient funds leads at 20.2%), and not as a category (issuer leads
at 43.4% against authentication's 25.7%).

*Technically correct, but far weaker than predicted:* the top-three lists do
differ, but by a single swap at position three between two reasons one place
apart. This was predicted as a divergence and turned out to be a hairline.

*The reasoning behind the prediction did hold.* Every authentication reason has
an above-average lost basket — incorrect OTP ₹2,003, OTP timeout ₹1,987,
authentication service down ₹1,944, 3DS ₹1,907, against ₹1,705 overall.
High-value orders genuinely do get stuck in authentication. The effect was real
but too small to overcome insufficient funds' volume.

**Recommendation.** Two reasons account for 31.7% of lost payment revenue and
five account for 48.7%, so effort concentrates well. But the ranking is not the
action — 86.8% retryability is.

Q3 shows retries already rescue ₹19.79M elsewhere in the funnel. This ₹35.5M is
different money: checkouts that had retryable failures, had the chance to try
again, and still ended without payment. That is the gap worth attacking, and Q4
tests whether payment method routing is the lever that closes it.

---

### Q3. How much failed-payment revenue is realistically recoverable?

Split failures into retryable and non-retryable. Measure whether retries worked and on which attempt.

**Prediction.** More than half of all recovered revenue will come from the first
retry. Recovery from the third attempt onwards will be under 5% of the total
recovered. Among soft declines specifically, switching payment method will have
a higher success rate than retrying the same method.

**Answer:** **Answer: One in three failed checkouts recovers on its own, worth ₹19.79M.
Nearly all of that happens on the second attempt. Customers who try a different
payment method succeed 75.14% of the time; customers who stay on the same method
succeed 45.93% of the time. But the size of that gap is an assumption built into
the generator, not a discovery.**

Scope: the 35,667 checkouts with at least one failed payment attempt.

**How much comes back.**

| Outcome | Checkouts | Cart value | Share of checkouts | Share of value |
|---|---|---|---|---|
| Recovered | 11,667 | ₹19,786,938 | 32.71% | 32.59% |
| Lost | 24,000 | ₹40,923,725 | 67.29% | 67.41% |

The two share columns are almost identical, so recovered baskets are worth about
the same as lost ones. Whether a retry works does not depend on how much is in
the cart.

**Which attempt succeeds.**

| Attempt | Successes | Value | Share of all successes | Share of recovered revenue |
|---|---|---|---|---|
| 1st | 130,203 | ₹194,080,342 | 91.78% | — |
| 2nd | 9,758 | ₹16,472,801 | 6.88% | 83.25% |
| 3rd | 1,739 | ₹3,001,081 | 1.23% | 15.17% |
| 4th | 170 | ₹313,057 | 0.12% | 1.58% |

These four rows total 141,870, not the 176,000 authorised checkouts from Q1. The
difference is 34,130 Cash on Delivery orders, which are authorised without making
any payment attempt and therefore have no row in `fact_payment_attempt`.

**Switching payment method versus staying.**

A checkout counts as switching if more than one payment method appears across its
attempts. An earlier version of this analysis compared the first method against
the last, which wrongly classified Card → UPI → Card as "same method" and
overstated same-method recovery on hard declines by 1.2 percentage points.

| Retry path | Checkouts | Recovered | Recovery rate | Value recovered |
|---|---|---|---|---|
| Used another method | 9,069 | 6,814 | 75.14% | ₹11,764,575 |
| Stayed on one method | 10,565 | 4,853 | 45.93% | ₹8,022,364 |

**This result is an input, not a finding.** `src/generate_attempts.py` sets
`SWITCH_METHOD_PENALTY = 0.90` and `SAME_METHOD_RETRY_PENALTY = 0.55`. Those
divide to 1.636. The measured rates divide to 75.14 / 45.93 = 1.636. The query
returned the assumption it was given. Real data would be needed to establish
whether switching genuinely helps, and by how much.

**What is not an assumption:** only 9,069 of 19,634 retrying customers used a
second method — **46.2%**. That share emerged from the interaction of several
settings rather than being set directly, and it is the number a business could
act on. More than half of retrying customers stay on the method that just failed.

**Recovery by failure class — the shape worth reporting.**

| Failure class | Stayed on one method | Used another method |
|---|---|---|
| Soft | 48.52% | 73.94% |
| Abandoned | 49.85% | 77.21% |
| Operational | 51.12% | 75.66% |
| Hard | **7.83%** | **75.00%** |

Read the right-hand column down: 73.94, 75.00, 75.66, 77.21. Almost flat. Read
the left-hand column: 7.83, 48.52, 49.85, 51.12. Very wide.

**Once the customer changes payment method, the original failure reason stops
mattering.** If they stay on the same method it matters enormously — and on a
hard decline such as an expired or blocked card, staying is close to futile at
7.83%. This flatness also follows from the model, since switching resets to a
fresh method's own success rate. The shape is worth reporting; the exact levels
are not evidence.

**Recovery by first failure reason.**

The spread is narrow: 36.84% (UPI timeout) down to 21.27% (Invalid VPA), a range
of only 1.7×. In this model, whether a customer retries is driven mainly by
attempt number rather than by which reason they saw, so the reason has limited
influence. The five worst-recovering reasons are all flagged non-retryable —
fraud decline, card expired, card blocked, wallet KYC restriction, invalid VPA —
which is the model behaving correctly.

One row does not fit: `Session expired` is flagged non-retryable but recovers at
35.23%, near the top. The flag is being used to mean "this exact attempt cannot
be repeated" rather than "this customer cannot succeed", and the two readings
disagree for session timeouts. The definition needs tightening.

**Prediction verdict — two of three claims correct.**

*Correct:* more than half of recovered revenue came from the first retry. It was
83.25%, well beyond the threshold predicted.

*Wrong:* recovery from the third attempt onwards was not under 5%. Attempts three
and four together returned ₹3,314,137, which is 16.75% of recovered revenue. The
direction was right — later attempts matter less — but the size was
underestimated by more than three times.

*Correct:* among soft declines, switching method beat staying, 73.94% against
48.52%.

**Recommendation.** Retries already return ₹19.79M without any intervention, and
83% of that lands on the second attempt, so the second attempt is where any
improvement should be aimed. A fourth attempt returned ₹313,057 across the whole
two-year period and is not worth engineering effort. The clearest opportunity is
that 53.8% of retrying customers stay on a method that has just failed them — but
the value of moving them cannot be estimated from this dataset, because the
benefit of switching was set by hand rather than measured.
---


### Q4. Which payment method produces the best business outcome?

Success rate, average order value and total revenue together — not simply which method fails least.

**Prediction.** UPI will have the highest success rate. Cards will have the
highest average order value. Cards will contribute more total revenue than UPI
despite failing more often — meaning a recommendation based on success rate
alone would reduce failures and reduce revenue at the same time.

**Answer: UPI wins on every measure that matters — highest success rate, highest
volume, and 57% more revenue than Card. Card has the largest baskets and the
worst outcome: 22.8% of checkouts, 31.4% of cart value, and 44.8% of all lost
revenue. The ranking is identical in every city tier and on every device.**

**First-attempt success rate.**

| Method | First attempts | Succeeded | Success rate | Avg attempt value |
|---|---|---|---|---|
| UPI | 87,977 | 76,707 | 87.19% | ₹1,329 |
| Wallet | 14,889 | 12,595 | 84.59% | ₹973 |
| Netbanking | 17,379 | 12,443 | 71.60% | ₹1,805 |
| Card | 45,625 | 28,458 | 62.37% | ₹2,016 |

Cash on Delivery does not appear: it makes no payment attempt and therefore
cannot fail at this step. Comparing methods on payment success alone would hand
COD an automatic win and tell you nothing.

**End-to-end outcome, measured to fulfilled revenue.**

| Method | Checkouts | Avg cart | Cart value started | Fulfilled | Revenue kept | Value kept | Value lost |
|---|---|---|---|---|---|---|---|
| UPI | 87,977 | ₹1,329 | ₹116,944,433 | 84.16% | ₹98,366,302 | 84.11% | ₹18,578,131 |
| Wallet | 14,889 | ₹973 | ₹14,482,568 | 81.95% | ₹11,917,202 | 82.29% | ₹2,565,366 |
| Cash on Delivery | 34,130 | ₹1,117 | ₹38,112,624 | 81.71% | ₹31,123,012 | 81.66% | ₹6,989,612 |
| Netbanking | 17,379 | ₹1,805 | ₹31,374,844 | 74.31% | ₹23,269,312 | 74.17% | ₹8,105,532 |
| **Card** | **45,625** | **₹2,016** | **₹91,989,160** | **67.91%** | **₹62,569,502** | **68.02%** | **₹29,419,658** |

**Card's problem is two problems stacked.**

| Method | Share of checkouts | Share of cart value | Share of losses |
|---|---|---|---|
| Card | 22.8% | 31.4% | 44.8% |
| UPI | 44.0% | 39.9% | 28.3% |
| Netbanking | 8.7% | 10.7% | 12.4% |
| Cash on Delivery | 17.1% | 13.0% | 10.6% |
| Wallet | 7.4% | 4.9% | 3.9% |

Read the Card row left to right: each figure is larger than the last. Card
customers spend more, and card payments fail more, so the failures land on the
expensive baskets. Every other method holds steady or shrinks across the row.

Card keeps ₹68 of every ₹100 a customer tries to spend with it.

**Where each method loses its money.**

| Method | At payment | At capture | At fulfilment |
|---|---|---|---|
| Card | 80.5% | 11.6% | 7.9% |
| Netbanking | 72.8% | 15.6% | 11.7% |
| Wallet | 58.8% | 24.5% | 16.7% |
| UPI | 52.9% | 28.1% | 19.0% |
| Cash on Delivery | 0% | 100% | 0% |

Four out of every five rupees Card loses die at bank authorisation. Card has one
problem, not several. UPI's losses are spread across all three steps, so there is
no single fix.

Cash on Delivery's losses appear under "at capture" because with COD, payment and
delivery happen at the same moment — a refused parcel is a failed capture. The
funnel stages were designed around online payment and do not map cleanly onto an
offline method. This is a labelling artefact, not a COD capture problem.

**Cash on Delivery is not the villain.** COD authorises 100% of the time and then
loses 18.3% at the door — 6,244 refusals worth ₹6.99M. Net, it keeps 81.66% of
cart value, third best of five, ahead of Netbanking and 13.6 points ahead of
Card. Card authorisation failures alone cost ₹23.69M, more than three times what
COD refusals cost.

**The ranking does not change by segment.**

Value kept, by city tier:

| Method | Metro | Tier 2 | Tier 3 |
|---|---|---|---|
| UPI | 84.31% | 83.75% | 83.98% |
| Wallet | 82.22% | 81.28% | 84.52% |
| Cash on Delivery | 81.50% | 81.94% | 81.72% |
| Netbanking | 74.35% | 73.49% | 74.90% |
| Card | 68.03% | 67.98% | 67.98% |

Value kept, by device:

| Method | Desktop | Mobile App | Mobile Web |
|---|---|---|---|
| UPI | 83.96% | 84.37% | 83.72% |
| Wallet | 81.73% | 81.81% | 83.78% |
| Cash on Delivery | 81.05% | 81.66% | 82.22% |
| Netbanking | 73.83% | 74.35% | 74.08% |
| Card | 68.34% | 68.26% | 67.21% |

Card is worst in all six segments. UPI is best in five of six. No method moves
more than about two percentage points across any segment. **One routing rule
works for the whole business** — no tier-specific or device-specific logic is
needed, which makes it far cheaper to build and maintain.

**One cell was checked and rejected.** In Tier 3, Wallet shows 84.52% against
UPI's 83.98%, appearing to overtake it. That cell holds 2,275 checkouts, and the
gap is 0.54 percentage points. This is within sampling variation and is not
treated as a finding.

**What customers choose does vary by tier**, even though performance does not:

| Method | Metro | Tier 2 | Tier 3 |
|---|---|---|---|
| Card | 28.2% | 17.9% | 10.4% |
| UPI | 45.9% | 43.1% | 37.8% |
| Cash on Delivery | 10.0% | 22.1% | 36.3% |

Cash on Delivery rises from one in ten checkouts in Metro to more than one in
three in Tier 3, while Card falls to one in ten. This mix is set directly in
`METHOD_MIX_BY_TIER` and is not a finding. Its consequence is worth noting
though: smaller cities carry less exposure to the worst-performing method.

**Prediction verdict — two of three claims correct.**

*Correct:* UPI has the highest success rate, 87.19%.

*Correct:* Card has the highest average order value, ₹2,016 against UPI's ₹1,329.

*Wrong:* Card does not contribute more total revenue than UPI. UPI brings in
₹98.37M against Card's ₹62.57M — 57% more. The gap breaks down into three parts:
UPI has 1.93× the checkouts, Card has 1.52× the basket, and UPI keeps 1.24× more
of what it starts with. Multiplied out, 1.93 ÷ 1.52 × 1.24 = 1.57, exactly the
observed gap. Card's basket advantage was swamped twice over.

*The reasoning behind the prediction still holds, and matters.* Card generates
₹62.57M of real revenue. Any recommendation to steer customers away from cards
would destroy that revenue while improving the success-rate chart. The trap was
correctly identified; it was placed on the wrong method.

**Recommendation.** Card is the single largest source of lost revenue — ₹29.42M,
44.8% of everything lost — and 80.5% of that dies at bank authorisation. That is
one problem with one address, and it is the highest-value target in this dataset.

Do not act by discouraging card usage. Card revenue is real and its baskets are
the largest. The action is to improve card authorisation, not to reduce card
volume.

The size of the gap should not be read as an opportunity estimate. Card and UPI
success rates were set by hand in `FIRST_ATTEMPT_SUCCESS` (0.63 and 0.88), so
the distance between them is an input. Closing it would require establishing on
real data that card authorisation can be improved, and by how much.

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

**Two findings are inputs, not discoveries.** Cards were configured to carry
larger baskets (`CART_MULTIPLIER_BY_METHOD`) and to fail most often
(`FIRST_ATTEMPT_SUCCESS`). So "expensive orders land on the least reliable method" is arithmetic following from two chosen values, not something the data revealed. What is genuinely computed is the size of that interaction — Card carries 31.4% of cart value and 44.8% of losses — and how it compares against the other leaks. The direction was assumed; the magnitude was measured.

**Small segments are not treated as findings.** Payment method crossed with city tier produces cells as small as 2,043 checkouts. Differences of under one percentage point in those cells are within sampling variation. One such case was identified and rejected in Q4 rather than reported.



---