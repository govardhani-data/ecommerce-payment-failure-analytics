"""
generate_attempts.py

Stage 2. Reads the checkouts produced by generate_checkouts.py and simulates
the payment attempts for each one - success, failure reason, retries, and
whether the customer switched payment method.

Writes:
    fact_payment_attempt.csv
    fact_checkout_stage2.csv   (checkouts updated with payment outcome)
"""

import random
from datetime import timedelta
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

RANDOM_SEED = 42
random.seed(RANDOM_SEED)
rng = np.random.default_rng(RANDOM_SEED)

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"

# Chance a first attempt succeeds, by method.
# Cards are worst because of the 3-D Secure step.
FIRST_ATTEMPT_SUCCESS = {
    "UPI":        0.88,
    "Card":       0.63,
    "Netbanking": 0.72,
    "Wallet":     0.85,
}

# Retrying the SAME method after a soft decline works less well than a
# fresh attempt would.
SAME_METHOD_RETRY_PENALTY = 0.55

# Switching method works nearly as well as a fresh attempt on that method.
SWITCH_METHOD_PENALTY = 0.90

# Chance the customer tries again at all, by which attempt just failed.
# Persistence drops sharply.
RETRY_WILLINGNESS = {1: 0.55, 2: 0.35, 3: 0.20}

# Of customers who do retry, how many change payment method.
SWITCH_METHOD_SHARE = 0.40

MAX_ATTEMPTS = 4

# Indian salaries land at month end. In the days before payday, more
# insufficient-funds failures and slightly lower success overall.
PAYDAY_WINDOW_DAYS = 5
PAYDAY_SUCCESS_PENALTY = 0.94
PAYDAY_INSUFFICIENT_FUNDS_BOOST = 2.2

# Failure reasons that can occur on each method, with relative weights.
FAILURE_WEIGHTS = {
    "UPI": {
        "Insufficient funds": 0.28, "UPI request expired": 0.18,
        "UPI timeout": 0.14, "PSP unavailable": 0.10,
        "Transaction limit exceeded": 0.08, "Bank unavailable": 0.08,
        "Customer cancelled": 0.08, "Invalid VPA": 0.06,
    },
    "Card": {
        "OTP timeout": 0.22, "Insufficient funds": 0.16,
        "3DS authentication failed": 0.12, "Incorrect OTP": 0.10,
        "Do not honour": 0.10, "Transaction limit exceeded": 0.06,
        "Gateway timeout": 0.06, "Card expired": 0.05,
        "Authentication service down": 0.05, "Card blocked": 0.04,
        "Fraud / risk decline": 0.04,
    },
    "Netbanking": {
        "Session expired": 0.24, "Bank unavailable": 0.22,
        "Incorrect bank credentials": 0.16, "Redirect failure": 0.14,
        "Insufficient funds": 0.12, "Gateway timeout": 0.08,
        "Customer cancelled": 0.04,
    },
    "Wallet": {
        "Insufficient wallet balance": 0.42, "Wallet KYC restriction": 0.14,
        "Transaction limit exceeded": 0.12, "Gateway error": 0.12,
        "Daily limit exceeded": 0.10, "Customer cancelled": 0.10,
    },
}

ONLINE_METHODS = ["UPI", "Card", "Netbanking", "Wallet"]


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

def pick(mix: dict):
    return random.choices(list(mix.keys()), weights=list(mix.values()))[0]


def is_near_payday(moment) -> bool:
    """True in the last few days of the month, before salaries land."""
    next_month = (moment.replace(day=28) + timedelta(days=4)).replace(day=1)
    days_to_month_end = (next_month - timedelta(days=1) - moment).days
    return days_to_month_end < PAYDAY_WINDOW_DAYS


def choose_failure_reason(method: str, near_payday: bool) -> str:
    """Pick a plausible failure reason for this method."""
    weights = dict(FAILURE_WEIGHTS[method])

    if near_payday and "Insufficient funds" in weights:
        weights["Insufficient funds"] *= PAYDAY_INSUFFICIENT_FUNDS_BOOST
    if near_payday and "Insufficient wallet balance" in weights:
        weights["Insufficient wallet balance"] *= PAYDAY_INSUFFICIENT_FUNDS_BOOST

    return pick(weights)


def result_from_class(failure_class: str) -> str:
    """Map a failure class to the result recorded on the attempt."""
    return {
        "Soft": "soft_decline",
        "Hard": "hard_decline",
        "Operational": "timeout",
        "Abandoned": "abandoned",
    }[failure_class]


def success_chance(method: str, attempt_no: int, switched: bool,
                   previous_class: str, near_payday: bool) -> float:
    """How likely this attempt is to succeed."""
    base = FIRST_ATTEMPT_SUCCESS[method]

    if attempt_no == 1:
        chance = base
    elif switched:
        chance = base * SWITCH_METHOD_PENALTY
    elif previous_class == "Hard":
        chance = 0.0            # same card, same problem - never works
    else:
        chance = base * SAME_METHOD_RETRY_PENALTY

    if near_payday:
        chance *= PAYDAY_SUCCESS_PENALTY

    return chance


# ---------------------------------------------------------------------------
# SIMULATE ONE CHECKOUT
# ---------------------------------------------------------------------------

def simulate_attempts(checkout, lookups) -> tuple:
    """
    Returns (list_of_attempt_rows, outcome_dict).
    Cash on delivery produces no attempts.
    """
    method_name = lookups["method_name_by_key"][checkout["initial_payment_method_key"]]

    if method_name == "Cash on Delivery":
        return [], {
            "attempt_count": 0,
            "final_payment_method_key": checkout["initial_payment_method_key"],
            "stage_reached": "authorised",       # order confirmed, money not taken yet
            "first_attempt_datetime": None,
            "authorised_datetime": checkout["created_datetime"],
            "final_failure_reason_key": None,
        }

    near_payday = is_near_payday(checkout["created_datetime"])
    amount = checkout["cart_value"]

    attempts = []
    current_method = method_name
    previous_class = None
    switched = False
    moment = checkout["created_datetime"] + timedelta(seconds=int(rng.integers(20, 180)))

    for attempt_no in range(1, MAX_ATTEMPTS + 1):
        chance = success_chance(current_method, attempt_no, switched,
                                previous_class, near_payday)
        succeeded = random.random() < chance

        needs_auth = 1 if current_method == "Card" else 0
        bank_key = (random.choice(lookups["bank_keys"])
                    if current_method in ("Card", "Netbanking") else None)

        if succeeded:
            attempts.append({
                "checkout_id": checkout["checkout_id"],
                "attempt_seq": attempt_no,
                "attempted_datetime": moment,
                "payment_method_key": lookups["method_key_by_name"][current_method],
                "gateway_key": random.choice(lookups["gateway_keys"]),
                "bank_key": bank_key,
                "attempt_amount": amount,
                "result": "success",
                "failure_reason_key": None,
                "auth_required": needs_auth,
                "auth_completed": 1 if needs_auth else None,
                "response_time_ms": int(rng.lognormal(np.log(1400), 0.5)),
            })

            return attempts, {
                "attempt_count": attempt_no,
                "final_payment_method_key": lookups["method_key_by_name"][current_method],
                "stage_reached": "authorised",
                "first_attempt_datetime": attempts[0]["attempted_datetime"],
                "authorised_datetime": moment,
                "final_failure_reason_key": None,
            }

        # --- it failed -----------------------------------------------------
        reason = choose_failure_reason(current_method, near_payday)
        reason_row = lookups["reason_by_name"][reason]
        failure_class = reason_row["failure_class"]

        auth_done = None
        if needs_auth:
            auth_done = 0 if reason_row["failure_category"] == "Authentication" else 1

        attempts.append({
            "checkout_id": checkout["checkout_id"],
            "attempt_seq": attempt_no,
            "attempted_datetime": moment,
            "payment_method_key": lookups["method_key_by_name"][current_method],
            "gateway_key": random.choice(lookups["gateway_keys"]),
            "bank_key": bank_key,
            "attempt_amount": amount,
            "result": result_from_class(failure_class),
            "failure_reason_key": int(reason_row["failure_reason_key"]),
            "auth_required": needs_auth,
            "auth_completed": auth_done,
            "response_time_ms": int(rng.lognormal(np.log(2600), 0.7)),
        })

        previous_class = failure_class

        # --- do they try again? --------------------------------------------
        if attempt_no >= MAX_ATTEMPTS:
            break
        if random.random() >= RETRY_WILLINGNESS.get(attempt_no, 0):
            break

        switched = random.random() < SWITCH_METHOD_SHARE
        if switched:
            others = [m for m in ONLINE_METHODS if m != current_method]
            current_method = random.choice(others)

        moment += timedelta(seconds=int(rng.integers(40, 600)))

    # every attempt failed
    last = attempts[-1]
    return attempts, {
        "attempt_count": len(attempts),
        "final_payment_method_key": None,
        "stage_reached": "attempted",
        "first_attempt_datetime": attempts[0]["attempted_datetime"],
        "authorised_datetime": None,
        "final_failure_reason_key": last["failure_reason_key"],
    }


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main() -> None:
    checkouts = pd.read_csv(DATA_DIR / "fact_checkout_stage1.csv",
                            parse_dates=["created_datetime"])
    methods = pd.read_csv(DATA_DIR / "dim_payment_method.csv")
    reasons = pd.read_csv(DATA_DIR / "dim_failure_reason.csv")
    gateways = pd.read_csv(DATA_DIR / "dim_gateway.csv")
    banks = pd.read_csv(DATA_DIR / "dim_bank.csv")

    lookups = {
        "method_name_by_key": dict(zip(methods["payment_method_key"], methods["method_name"])),
        "method_key_by_name": dict(zip(methods["method_name"], methods["payment_method_key"])),
        "reason_by_name": {r["failure_reason"]: r for _, r in reasons.iterrows()},
        "gateway_keys": gateways["gateway_key"].tolist(),
        "bank_keys": banks["bank_key"].tolist(),
    }

    print(f"Simulating payments for {len(checkouts):,} checkouts...")

    all_attempts = []
    outcomes = []

    for i, checkout in enumerate(checkouts.to_dict("records"), start=1):
        attempts, outcome = simulate_attempts(checkout, lookups)
        all_attempts.extend(attempts)
        outcomes.append(outcome)

        if i % 50_000 == 0:
            print(f"  {i:,} done")

    attempt_df = pd.DataFrame(all_attempts)
    attempt_df.insert(0, "attempt_key", range(1, len(attempt_df) + 1))

    outcome_df = pd.DataFrame(outcomes)
    checkout_df = pd.concat([checkouts.reset_index(drop=True), outcome_df], axis=1)

    attempt_df.to_csv(DATA_DIR / "fact_payment_attempt.csv", index=False)
    checkout_df.to_csv(DATA_DIR / "fact_checkout_stage2.csv", index=False)

    # --- summary --------------------------------------------------------
    online = checkout_df[checkout_df["attempt_count"] > 0]
    authorised = online[online["stage_reached"] == "authorised"]

    print(f"\n  fact_payment_attempt   {len(attempt_df):,} rows")
    print(f"  fact_checkout_stage2   {len(checkout_df):,} rows")
    print(f"\n  online checkouts       {len(online):,}")
    print(f"  reached authorised     {len(authorised):,}  ({100*len(authorised)/len(online):.2f}%)")
    print(f"  avg attempts per online checkout  {online['attempt_count'].mean():.2f}")
    print("\nDone.")


if __name__ == "__main__":
    main()