"""
load_to_sql.py

Loads every table into SQL Server, dimensions first so the foreign keys on the
fact tables have something to point at.
"""

import urllib.parse
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine

DATA_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"

ODBC_STRING = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    r"SERVER=localhost\SQLEXPRESS;"
    "DATABASE=VanyaPaymentsDB;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)

# Order matters: dimensions before facts, checkouts before attempts.
TABLES = [
    ("dim_date", []),
    ("dim_customer", []),
    ("dim_payment_method", []),
    ("dim_failure_reason", []),
    ("dim_gateway", []),
    ("dim_bank", []),
    ("dim_device", []),
    ("dim_fulfilment_outcome", []),
    ("fact_checkout", ["created_datetime", "first_attempt_datetime",
                       "authorised_datetime", "captured_datetime",
                       "fulfilled_datetime"]),
    ("fact_payment_attempt", ["attempted_datetime"]),
]


def main() -> None:
    url = "mssql+pyodbc:///?odbc_connect=" + urllib.parse.quote_plus(ODBC_STRING)
    engine = create_engine(url, fast_executemany=True)

    print("Loading into VanyaPaymentsDB\n")

    for table, date_cols in TABLES:
        df = pd.read_csv(DATA_DIR / f"{table}.csv", parse_dates=date_cols)
        df.to_sql(table, engine, if_exists="append", index=False, chunksize=5_000)
        print(f"  {table:26} {len(df):8,} rows loaded")

    print("\nDone.")


if __name__ == "__main__":
    main()