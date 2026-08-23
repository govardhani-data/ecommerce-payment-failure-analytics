"""Quick visual checks that the generated checkouts look realistic."""

from pathlib import Path
import matplotlib
matplotlib.use("Agg")          # save to file rather than opening a window
import matplotlib.pyplot as plt
import pandas as pd

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
OUT_DIR = Path(__file__).resolve().parents[1] / "docs" / "images"

df = pd.read_csv(DATA_DIR / "fact_checkout_stage1.csv", parse_dates=["created_datetime"])

fig, axes = plt.subplots(2, 2, figsize=(13, 9))

# Cart value - should be a right-skewed hump, not a bell
axes[0, 0].hist(df["cart_value"], bins=60, range=(0, 8000))
axes[0, 0].set_title("Cart value distribution")
axes[0, 0].set_xlabel("Rupees")

# By hour - should peak in the evening
by_hour = df["created_datetime"].dt.hour.value_counts().sort_index()
axes[0, 1].bar(by_hour.index, by_hour.values)
axes[0, 1].set_title("Checkouts by hour of day")

# By month - should show an October and November lift
by_month = df["created_datetime"].dt.to_period("M").value_counts().sort_index()
axes[1, 0].plot(range(len(by_month)), by_month.values, marker="o")
axes[1, 0].set_title("Checkouts by month")
axes[1, 0].set_xlabel("Month number since Jan 2024")

# By payment method
methods = pd.read_csv(DATA_DIR / "dim_payment_method.csv")
merged = df.merge(methods, left_on="initial_payment_method_key",
                  right_on="payment_method_key")
by_method = merged["method_name"].value_counts()
axes[1, 1].barh(by_method.index, by_method.values)
axes[1, 1].set_title("Checkouts by payment method")

plt.tight_layout()
plt.savefig(OUT_DIR / "00-data-sanity-checks.png", dpi=110)
print(f"Saved to {OUT_DIR / '00-data-sanity-checks.png'}")