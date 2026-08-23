"""
generate_dimensions.py

Builds the eight lookup tables for the Vanya Beauty payment analysis.
Writes one CSV per dimension into data/raw/.

Data is synthetic. No client or production data is used.
"""

import random
from datetime import date, timedelta
from pathlib import Path

import pandas as pd
from faker import Faker

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------

RANDOM_SEED = 42
random.seed(RANDOM_SEED)

fake = Faker("en_IN")
Faker.seed(RANDOM_SEED)

OUTPUT_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

START_DATE = date(2024, 1, 1)
END_DATE = date(2025, 12, 31)

CUSTOMER_COUNT = 60_000


# ---------------------------------------------------------------------------
# REFERENCE DATA
# ---------------------------------------------------------------------------

FIXED_HOLIDAYS = [(1, 26), (8, 15), (10, 2), (12, 25)]

# (city, state, tier, share of customers)
CITIES = [
    ("Mumbai",        "Maharashtra",    "Metro",  0.11),
    ("Delhi",         "Delhi",          "Metro",  0.10),
    ("Bengaluru",     "Karnataka",      "Metro",  0.10),
    ("Hyderabad",     "Telangana",      "Metro",  0.08),
    ("Chennai",       "Tamil Nadu",     "Metro",  0.06),
    ("Pune",          "Maharashtra",    "Metro",  0.05),
    ("Kolkata",       "West Bengal",    "Metro",  0.04),
    ("Ahmedabad",     "Gujarat",        "Metro",  0.04),

    ("Jaipur",        "Rajasthan",      "Tier 2", 0.04),
    ("Lucknow",       "Uttar Pradesh",  "Tier 2", 0.04),
    ("Kochi",         "Kerala",         "Tier 2", 0.03),
    ("Coimbatore",    "Tamil Nadu",     "Tier 2", 0.03),
    ("Indore",        "Madhya Pradesh", "Tier 2", 0.03),
    ("Nagpur",        "Maharashtra",    "Tier 2", 0.03),
    ("Chandigarh",    "Chandigarh",     "Tier 2", 0.02),
    ("Visakhapatnam", "Andhra Pradesh", "Tier 2", 0.02),
    ("Surat",         "Gujarat",        "Tier 2", 0.02),
    ("Bhubaneswar",   "Odisha",         "Tier 2", 0.02),

    ("Warangal",      "Telangana",      "Tier 3", 0.02),
    ("Guntur",        "Andhra Pradesh", "Tier 3", 0.02),
    ("Nashik",        "Maharashtra",    "Tier 3", 0.02),
    ("Rajkot",        "Gujarat",        "Tier 3", 0.02),
    ("Jodhpur",       "Rajasthan",      "Tier 3", 0.02),
    ("Salem",         "Tamil Nadu",     "Tier 3", 0.02),
    ("Dehradun",      "Uttarakhand",    "Tier 3", 0.01),
    ("Raipur",        "Chhattisgarh",   "Tier 3", 0.01),
]

# (method, type, requires 3-D Secure authentication)
PAYMENT_METHODS = [
    ("UPI",              "Online",  0),
    ("Card",             "Online",  1),
    ("Netbanking",       "Online",  0),
    ("Wallet",           "Online",  0),
    ("Cash on Delivery", "Offline", 0),
]

GATEWAYS = ["Razorpay", "PayU", "Cashfree", "CCAvenue", "Paytm Payment Gateway"]

# (bank name, type)
BANKS = [
    ("State Bank of India",          "Public sector"),
    ("Punjab National Bank",         "Public sector"),
    ("Bank of Baroda",               "Public sector"),
    ("Canara Bank",                  "Public sector"),
    ("Union Bank of India",          "Public sector"),
    ("HDFC Bank",                    "Private"),
    ("ICICI Bank",                   "Private"),
    ("Axis Bank",                    "Private"),
    ("Kotak Mahindra Bank",          "Private"),
    ("IndusInd Bank",                "Private"),
    ("IDFC First Bank",              "Private"),
    ("AU Small Finance Bank",        "Small finance"),
    ("Equitas Small Finance Bank",   "Small finance"),
]

# (device type, operating system)
DEVICES = [
    ("Mobile App", "Android"),
    ("Mobile App", "iOS"),
    ("Mobile Web", "Android"),
    ("Mobile Web", "iOS"),
    ("Desktop",    "Windows"),
    ("Desktop",    "macOS"),
]

# (outcome, category)
FULFILMENT_OUTCOMES = [
    ("Fulfilled",                      "Success"),
    ("Cancelled by customer",          "Cancelled"),
    ("Cancelled - inventory unavailable", "Cancelled"),
    ("Cancelled - pricing error",      "Cancelled"),
    ("COD refused at delivery",        "Refused"),
    ("COD customer unavailable",       "Refused"),
    ("Capture failed",                 "Failed"),
]

# (reason, class, retryable, category)
#
# Classification notes for two ambiguous cases:
#   "UPI request expired" is classed as customer abandonment rather than a
#   technical timeout, because a request reaching expiry usually means the
#   customer never approved it in their UPI app.
#   "Session expired" is marked not retryable, because the same session cannot
#   be retried - the customer must start a fresh checkout.
FAILURE_REASONS = [
    # Issuer decisions
    ("Insufficient funds",              "Soft",        "Yes",     "Issuer"),
    ("Transaction limit exceeded",      "Soft",        "Yes",     "Issuer"),
    ("Daily limit exceeded",            "Soft",        "Yes",     "Issuer"),
    ("Do not honour",                   "Soft",        "Yes",     "Issuer"),
    ("Card expired",                    "Hard",        "No",      "Issuer"),
    ("Card blocked",                    "Hard",        "No",      "Issuer"),
    ("Invalid card number",             "Hard",        "No",      "Issuer"),
    ("Account closed",                  "Hard",        "No",      "Issuer"),
    ("Fraud / risk decline",            "Hard",        "No",      "Issuer"),
    ("Bank unavailable",                "Operational", "Yes",     "Issuer"),

    # Authentication
    ("OTP timeout",                     "Abandoned",   "Yes",     "Authentication"),
    ("Incorrect OTP",                   "Soft",        "Yes",     "Authentication"),
    ("3DS authentication failed",       "Soft",        "Yes",     "Authentication"),
    ("Authentication service down",     "Operational", "Yes",     "Authentication"),

    # UPI specific
    ("UPI request expired",             "Abandoned",   "Yes",     "Customer"),
    ("UPI timeout",                     "Operational", "Yes",     "Technical"),
    ("Invalid VPA",                     "Hard",        "No",      "Customer"),
    ("PSP unavailable",                 "Operational", "Yes",     "Technical"),

    # Netbanking specific
    ("Session expired",                 "Abandoned",   "No",      "Technical"),
    ("Incorrect bank credentials",      "Soft",        "Yes",     "Customer"),
    ("Redirect failure",                "Operational", "Yes",     "Technical"),

    # Wallet specific
    ("Insufficient wallet balance",     "Soft",        "Yes",     "Customer"),
    ("Wallet KYC restriction",          "Hard",        "No",      "Customer"),

    # Gateway and customer
    ("Gateway timeout",                 "Operational", "Yes",     "Gateway"),
    ("Gateway error",                   "Operational", "Yes",     "Gateway"),
    ("Customer cancelled",              "Abandoned",   "Yes",     "Customer"),
]


# ---------------------------------------------------------------------------
# BUILDERS
# ---------------------------------------------------------------------------

def build_dim_date(start: date, end: date) -> pd.DataFrame:
    """One row per calendar day."""
    rows = []
    current = start

    while current <= end:
        is_weekend = current.isoweekday() >= 6
        is_holiday = (current.month, current.day) in FIXED_HOLIDAYS

        # Month end matters in India: salaries are usually paid then, so
        # insufficient-funds failures are expected to cluster just before.
        next_day = current + timedelta(days=1)
        is_month_end = next_day.month != current.month

        rows.append({
            "date_key": int(current.strftime("%Y%m%d")),
            "full_date": current.isoformat(),
            "day_of_week": current.isoweekday(),
            "day_name": current.strftime("%A"),
            "iso_year": current.isocalendar().year,
            "week_of_year": current.isocalendar().week,
            "month": current.month,
            "month_name": current.strftime("%B"),
            "quarter": (current.month - 1) // 3 + 1,
            "year": current.year,
            "is_weekend": int(is_weekend),
            "is_holiday": int(is_holiday),
            "is_working_day": int(not is_weekend and not is_holiday),
            "is_month_end": int(is_month_end),
        })

        current += timedelta(days=1)

    return pd.DataFrame(rows)


def build_dim_customer(count: int) -> pd.DataFrame:
    """One row per customer, weighted across cities."""
    city_names = [c[0] for c in CITIES]
    weights = [c[3] for c in CITIES]
    lookup = {c[0]: (c[1], c[2]) for c in CITIES}

    rows = []
    for i in range(1, count + 1):
        city = random.choices(city_names, weights=weights)[0]
        state, tier = lookup[city]

        rows.append({
            "customer_key": i,
            "customer_id": f"CUST{i:06d}",
            "city": city,
            "state": state,
            "city_tier": tier,
        })

    return pd.DataFrame(rows)


def build_dim_payment_method() -> pd.DataFrame:
    rows = [
        {"payment_method_key": i, "method_name": name,
         "method_type": mtype, "requires_auth": auth}
        for i, (name, mtype, auth) in enumerate(PAYMENT_METHODS, start=1)
    ]
    return pd.DataFrame(rows)


def build_dim_failure_reason() -> pd.DataFrame:
    rows = [
        {"failure_reason_key": i, "failure_reason": reason,
         "failure_class": cls, "retryable_flag": retry,
         "failure_category": cat}
        for i, (reason, cls, retry, cat) in enumerate(FAILURE_REASONS, start=1)
    ]
    return pd.DataFrame(rows)


def build_dim_gateway() -> pd.DataFrame:
    rows = [
        {"gateway_key": i, "gateway_name": name}
        for i, name in enumerate(GATEWAYS, start=1)
    ]
    return pd.DataFrame(rows)


def build_dim_bank() -> pd.DataFrame:
    rows = [
        {"bank_key": i, "bank_name": name, "bank_type": btype}
        for i, (name, btype) in enumerate(BANKS, start=1)
    ]
    return pd.DataFrame(rows)


def build_dim_device() -> pd.DataFrame:
    rows = [
        {"device_key": i, "device_type": dtype, "os": os_name}
        for i, (dtype, os_name) in enumerate(DEVICES, start=1)
    ]
    return pd.DataFrame(rows)


def build_dim_fulfilment_outcome() -> pd.DataFrame:
    rows = [
        {"fulfilment_outcome_key": i, "outcome_name": name,
         "outcome_category": cat}
        for i, (name, cat) in enumerate(FULFILMENT_OUTCOMES, start=1)
    ]
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------

def main() -> None:
    dimensions = {
        "dim_date": build_dim_date(START_DATE, END_DATE),
        "dim_customer": build_dim_customer(CUSTOMER_COUNT),
        "dim_payment_method": build_dim_payment_method(),
        "dim_failure_reason": build_dim_failure_reason(),
        "dim_gateway": build_dim_gateway(),
        "dim_bank": build_dim_bank(),
        "dim_device": build_dim_device(),
        "dim_fulfilment_outcome": build_dim_fulfilment_outcome(),
    }

    print(f"Writing to: {OUTPUT_DIR}\n")

    for name, df in dimensions.items():
        path = OUTPUT_DIR / f"{name}.csv"
        df.to_csv(path, index=False)
        print(f"  {name:26} {len(df):7,} rows  ->  {path.name}")

    print("\nDone.")


if __name__ == "__main__":
    main()