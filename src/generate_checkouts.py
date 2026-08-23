"""
generate_checkouts.py

Builds the synthetic checkout dataset for Vanya Beauty.

Stage 1 (this version): checkout details only - when, who, what device,
how much, which payment method chosen. Every checkout is assumed to
succeed. Failure, retries and fulfilment are added in later stages.

Data is synthetic. No client or production data is used.
"""

import random
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# CONFIGURATION - every behavioural assumption lives here
# ---------------------------------------------------------------------------

RANDOM_SEED = 42
random.seed(RANDOM_SEED)
rng = np.random.default_rng(RANDOM_SEED)

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"

CHECKOUT_COUNT = 200_000
START = datetime(2024, 1, 1)
END = datetime(2025, 12, 31, 23, 59)

# Cart value in rupees. Lognormal - most orders modest, a long tail of
# large ones. Median around Rs 1,150.
CART_MEDIAN = 1150
CART_SPREAD = 0.62

# Higher-value baskets skew towards cards; cash on delivery skews lower.
CART_MULTIPLIER_BY_METHOD = {
    "Card":             1.45,
    "Netbanking":       1.30,
    "UPI":              0.95,
    "Wallet":           0.70,
    "Cash on Delivery": 0.80,
}

# Payment method chosen, by city tier. Metros lean card, tier 3 leans COD.
METHOD_MIX_BY_TIER = {
    "Metro":  {"UPI": 0.46, "Card": 0.28, "Netbanking": 0.09, "Wallet": 0.07, "Cash on Delivery": 0.10},
    "Tier 2": {"UPI": 0.43, "Card": 0.18, "Netbanking": 0.09, "Wallet": 0.08, "Cash on Delivery": 0.22},
    "Tier 3": {"UPI": 0.38, "Card": 0.11, "Netbanking": 0.07, "Wallet": 0.08, "Cash on Delivery": 0.36},
}

# India is mobile-first for shopping.
DEVICE_MIX = {
    ("Mobile App", "Android"): 0.38,
    ("Mobile App", "iOS"):     0.14,
    ("Mobile Web", "Android"): 0.19,
    ("Mobile Web", "iOS"):     0.06,
    ("Desktop", "Windows"):    0.18,
    ("Desktop", "macOS"):      0.05,
}

# Relative shopping volume by hour. Evening peak, unlike a support desk.
HOURLY_WEIGHTS = [
    0.4, 0.2, 0.2, 0.2, 0.3, 0.5,      # 00-05  overnight
    0.8, 1.2, 1.8, 2.2, 2.4, 2.3,      # 06-11  morning
    2.0, 2.2, 2.1, 2.0, 2.2, 2.6,      # 12-17  afternoon
    3.4, 4.2, 5.0, 4.6, 3.2, 1.4,      # 18-23  evening peak at 20:00
]

# Relative volume by month. Festival season lifts October and November.
MONTHLY_WEIGHTS = {
    1: 0.85, 2: 0.90, 3: 0.95, 4: 1.00, 5: 1.05, 6: 0.95,
    7: 1.00, 8: 1.05, 9: 1.10, 10: 1.55, 11: 1.40, 12: 1.10,
}

WEEKEND_LIFT = 1.15          # people shop slightly more at weekends
FIRST_TIME_SHARE = 0.28      # share of checkouts from new customers

ITEM_COUNT_WEIGHTS = {1: 0.42, 2: 0.28, 3: 0.15, 4: 0.08, 5: 0.05, 6: 0.02}


# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

def pick(mix: dict):
    """Choose one key from a dict of {option: probability}."""
    return random.choices(list(mix.keys()), weights=list(mix.values()))[0]


def build_day_weights(start: datetime, end: datetime) -> tuple:
    """A weight for every day, combining month seasonality and weekend lift."""
    days, weights = [], []
    current = start.date()
    last = end.date()

    while current <= last:
        w = MONTHLY_WEIGHTS[current.month]
        if current.isoweekday() >= 6:
            w *= WEEKEND_LIFT
        days.append(current)
        weights.append(w)
        current += timedelta(days=1)

    return days, weights


def random_datetime(days, day_weights) -> datetime:
    """A random moment, weighted by season, weekday and hour."""
    day = random.choices(days, weights=day_weights)[0]
    hour = random.choices(range(24), weights=HOURLY_WEIGHTS)[0]
    minute = int(rng.integers(0, 60))
    second = int(rng.integers(0, 60))
    return datetime(day.year, day.month, day.day, hour, minute, second)


def cart_value_for(method: str) -> float:
    """Lognormal cart value, adjusted for the payment method chosen."""
    base = rng.lognormal(mean=np.log(CART_MEDIAN), sigma=CART_SPREAD)
    value = base * CART_MULTIPLIER_BY_METHOD[method]
    return round(min(max(value, 199), 25_000), 2)


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

def main() -> None:
    customers = pd.read_csv(DATA_DIR / "dim_customer.csv")
    methods = pd.read_csv(DATA_DIR / "dim_payment_method.csv")
    devices = pd.read_csv(DATA_DIR / "dim_device.csv")

    method_key = dict(zip(methods["method_name"], methods["payment_method_key"]))
    device_key = {
        (r["device_type"], r["os"]): r["device_key"]
        for _, r in devices.iterrows()
    }

    customer_records = customers[["customer_key", "city_tier"]].to_dict("records")
    days, day_weights = build_day_weights(START, END)

    print(f"Generating {CHECKOUT_COUNT:,} checkouts...")

    rows = []
    for i in range(1, CHECKOUT_COUNT + 1):
        customer = random.choice(customer_records)
        created = random_datetime(days, day_weights)

        method_name = pick(METHOD_MIX_BY_TIER[customer["city_tier"]])
        device = pick(DEVICE_MIX)

        rows.append({
            "checkout_key": i,
            "checkout_id": f"VB{i:07d}",
            "customer_key": customer["customer_key"],
            "created_date_key": int(created.strftime("%Y%m%d")),
            "created_datetime": created,
            "device_key": device_key[device],
            "initial_payment_method_key": method_key[method_name],
            "cart_value": cart_value_for(method_name),
            "item_count": pick(ITEM_COUNT_WEIGHTS),
            "is_first_time_customer": int(random.random() < FIRST_TIME_SHARE),
        })

        if i % 50_000 == 0:
            print(f"  {i:,} done")

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "fact_checkout_stage1.csv", index=False)

    print(f"\n  fact_checkout_stage1  {len(df):,} rows")
    print(f"  total cart value      Rs {df['cart_value'].sum():,.0f}")
    print(f"  median cart value     Rs {df['cart_value'].median():,.0f}")
    print("\nDone.")


if __name__ == "__main__":
    main()
    