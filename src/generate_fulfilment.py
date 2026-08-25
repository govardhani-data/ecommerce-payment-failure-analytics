"""
generate_fulfilment.py

Stage 3. Reads the checkouts produced by generate_attempts.py and decides what
happened after payment: captured or not, fulfilled or not, COD delivered or
refused, and whether the customer was charged twice.

Writes:
    fact_checkout.csv   (final, ready to load)
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

# Of online payments the bank authorised, how many are never actually taken
NEVER_CAPTURED_SHARE = 0.05

# Of captured payments, how many fail to reach the customer
FULFILMENT_FAILURE_SHARE = 0.035

# Of cash-on-delivery orders, how many come back
COD_REFUSAL_SHARE = 0.18

# Of successful online checkouts, how many are charged twice.
# Skewed towards higher-value orders: a customer who has just spent a lot and
# sees no confirmation is more anxious, and more likely to press Pay again.
DUPLICATE_CHARGE_SHARE = 0.006
DUPLICATE_VALUE_SKEW = 0.8

# Why an authorised payment is never captured
NEVER_CAPTURED_REASONS = {
    "Cancelled by customer": 0.45,
    "Cancelled - inventory unavailable": 0.30,
    "Capture failed": 0.25,
}

# Why a captured order is never fulfilled
FULFILMENT_FAILURE_REASONS = {
    "Cancelled - inventory unavailable": 0.52,
    "Cancelled by customer": 0.31,
    "Cancelled - pricing error": 0.17,
}

# How a refused COD order is recorded
COD_REFUSAL_REASONS = {
    "COD refused at delivery": 0.67,
    "COD customer unavailable": 0.33,
}

# Realistic delays, in hours
CAPTURE_DELAY_HOURS = (2, 72)
FULFIL_DELAY_HOURS = (24, 168)
COD_DELIVERY_HOURS = (48, 216)


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

def pick(mix: dict):
    return random.choices(list(mix.keys()), weights=list(mix.values()))[0]


def hours_after(moment, low: int, high: int):
    return moment + timedelta(hours=float(rng.uniform(low, high)))


def duplicate_flags(df: pd.DataFrame, eligible_mask) -> np.ndarray:
    """
    Choose which checkouts get charged twice, weighted by cart value so that
    higher-value orders are more likely, while keeping the overall rate at
    DUPLICATE_CHARGE_SHARE.
    """
    flags = np.zeros(len(df), dtype=int)
    eligible = df.loc[eligible_mask]

    if len(eligible) == 0:
        return flags

    weights = (eligible["cart_value"] / eligible["cart_value"].mean()) ** DUPLICATE_VALUE_SKEW
    probs = weights * DUPLICATE_CHARGE_SHARE
    probs = probs * (DUPLICATE_CHARGE_SHARE * len(eligible) / probs.sum())  # normalise
    probs = probs.clip(upper=0.06)

    draws = rng.random(len(eligible))
    flags[eligible.index[draws < probs.values]] = 1
    return flags


# ---------------------------------------------------------------------------
# DECIDE ONE CHECKOUT
# ---------------------------------------------------------------------------

def resolve(row, cod_method_key, outcome_key) -> dict:
    """Work out capture, fulfilment and retained revenue for one checkout."""

    # --- payment never succeeded -------------------------------------------
    if row["stage_reached"] == "attempted":
        return {
            "stage_reached": "attempted",
            "captured_datetime": None,
            "fulfilled_datetime": None,
            "fulfilment_outcome_key": None,
            "revenue_captured": 0.0,
        }

    authorised = row["authorised_datetime"]

    # --- cash on delivery ---------------------------------------------------
    if row["initial_payment_method_key"] == cod_method_key:
        if random.random() < COD_REFUSAL_SHARE:
            return {
                "stage_reached": "authorised",
                "captured_datetime": None,
                "fulfilled_datetime": None,
                "fulfilment_outcome_key": outcome_key[pick(COD_REFUSAL_REASONS)],
                "revenue_captured": 0.0,
            }

        delivered = hours_after(authorised, *COD_DELIVERY_HOURS)
        return {
            "stage_reached": "fulfilled",
            "captured_datetime": delivered,       # COD money is taken at the door
            "fulfilled_datetime": delivered,
            "fulfilment_outcome_key": outcome_key["Fulfilled"],
            "revenue_captured": float(row["cart_value"]),
        }

    # --- online: authorised but never captured ------------------------------
    if random.random() < NEVER_CAPTURED_SHARE:
        return {
            "stage_reached": "authorised",
            "captured_datetime": None,
            "fulfilled_datetime": None,
            "fulfilment_outcome_key": outcome_key[pick(NEVER_CAPTURED_REASONS)],
            "revenue_captured": 0.0,
        }

    captured = hours_after(authorised, *CAPTURE_DELAY_HOURS)

    # --- online: captured but never fulfilled -------------------------------
    if random.random() < FULFILMENT_FAILURE_SHARE:
        return {
            "stage_reached": "captured",
            "captured_datetime": captured,
            "fulfilled_datetime": None,
            "fulfilment_outcome_key": outcome_key[pick(FULFILMENT_FAILURE_REASONS)],
            "revenue_captured": 0.0,          # refunded
        }

    # --- online: everything worked ------------------------------------------
    return {
        "stage_reached": "fulfilled",
        "captured_datetime": captured,
        "fulfilled_datetime": hours_after(captured, *FULFIL_DELAY_HOURS),
        "fulfilment_outcome_key": outcome_key["Fulfilled"],
        "revenue_captured": float(row["cart_value"]),
    }


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main() -> None:
    df = pd.read_csv(
        DATA_DIR / "fact_checkout_stage2.csv",
        parse_dates=["created_datetime", "first_attempt_datetime", "authorised_datetime"],
    )
    methods = pd.read_csv(DATA_DIR / "dim_payment_method.csv")
    outcomes = pd.read_csv(DATA_DIR / "dim_fulfilment_outcome.csv")

    cod_method_key = int(
        methods.loc[methods["method_name"] == "Cash on Delivery", "payment_method_key"].iloc[0]
    )
    outcome_key = dict(zip(outcomes["outcome_name"], outcomes["fulfilment_outcome_key"]))

    print(f"Resolving {len(df):,} checkouts...")

    resolved = [resolve(r, cod_method_key, outcome_key) for r in df.to_dict("records")]
    df = pd.concat([df, pd.DataFrame(resolved)[
        ["captured_datetime", "fulfilled_datetime",
         "fulfilment_outcome_key", "revenue_captured"]
    ]], axis=1)

    df["stage_reached"] = [r["stage_reached"] for r in resolved]

    # --- duplicate charges ---------------------------------------------------
    online = df["initial_payment_method_key"] != cod_method_key
    succeeded = df["authorised_datetime"].notna()
    df["is_duplicate_charge"] = duplicate_flags(df, online & succeeded)
    df["duplicate_charge_amount"] = np.where(
        df["is_duplicate_charge"] == 1, df["cart_value"], np.nan
    )

    columns = [
        "checkout_key", "checkout_id", "customer_key", "created_date_key",
        "created_datetime", "device_key", "initial_payment_method_key",
        "final_payment_method_key", "cart_value", "item_count",
        "is_first_time_customer", "stage_reached", "attempt_count",
        "first_attempt_datetime", "authorised_datetime", "captured_datetime",
        "fulfilled_datetime", "final_failure_reason_key",
        "fulfilment_outcome_key", "is_duplicate_charge",
        "duplicate_charge_amount", "revenue_captured",
    ]
    df[columns].to_csv(DATA_DIR / "fact_checkout.csv", index=False)

    # --- summary -------------------------------------------------------------
    stages = df["stage_reached"].value_counts()
    dup = int(df["is_duplicate_charge"].sum())

    print(f"\n  fact_checkout          {len(df):,} rows\n")
    for stage in ["attempted", "authorised", "captured", "fulfilled"]:
        n = stages.get(stage, 0)
        print(f"  stage {stage:<12} {n:7,}  ({100*n/len(df):5.2f}%)")

    print(f"\n  revenue retained       Rs {df['revenue_captured'].sum():,.0f}")
    print(f"  total cart value       Rs {df['cart_value'].sum():,.0f}")
    print(f"  revenue capture rate   {100*df['revenue_captured'].sum()/df['cart_value'].sum():.2f}%")
    print(f"\n  duplicate charges      {dup:,}  ({100*dup/len(df):.2f}%)")
    print(f"  duplicate avg value    Rs {df.loc[df['is_duplicate_charge']==1,'cart_value'].mean():,.0f}")
    print(f"  overall avg cart       Rs {df['cart_value'].mean():,.0f}")
    print("\nDone.")


if __name__ == "__main__":
    main()