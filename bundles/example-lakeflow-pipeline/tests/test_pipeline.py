"""
Unit Tests for Lakeflow Customer Pipeline
==========================================

Tests validate transformation logic without requiring a Databricks cluster.
Run locally with: pytest tests/test_pipeline.py -v

Install dependencies:
    pip install -r requirements-test.txt

Schema tested (13 Raw fields):
  customer_id, company_name, contact_name, email, country, city,
  industry, plan, mrr, employees, signup_date, status, acquisition_channel

Curated computed fields:
  days_since_signup, arr (mrr × 12), company_size (SMALL/MEDIUM/LARGE), plan_tier (0–3)

Mart tables tested:
  customers_by_country, customers_by_plan,
  customers_daily_signups, customers_kpi_summary,
  customers_by_industry
"""

import pytest
from datetime import datetime
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType, TimestampType,
)
from pyspark.sql.functions import (
    col, to_date, datediff, current_timestamp, count, when,
    sum as spark_sum,
)


# ==========================================================
# Spark session (session-scoped)
# ==========================================================

@pytest.fixture(scope="session")
def spark():
    return (
        SparkSession.builder
        .appName("CustomerPipelineTests")
        .master("local[2]")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .getOrCreate()
    )


@pytest.fixture(scope="session", autouse=True)
def cleanup(request):
    def _stop():
        SparkSession.builder.getOrCreate().stop()
    request.addfinalizer(_stop)


# ==========================================================
# Schema + test data
# ==========================================================

RAW_SCHEMA = StructType([
    StructField("customer_id",         StringType(),    True),
    StructField("company_name",        StringType(),    True),
    StructField("contact_name",        StringType(),    True),
    StructField("email",               StringType(),    True),
    StructField("country",             StringType(),    True),
    StructField("city",                StringType(),    True),
    StructField("industry",            StringType(),    True),
    StructField("plan",                StringType(),    True),
    StructField("mrr",                 IntegerType(),   True),
    StructField("employees",           IntegerType(),   True),
    StructField("signup_date",         StringType(),    True),
    StructField("status",              StringType(),    True),
    StructField("acquisition_channel", StringType(),    True),
    StructField("ingestion_timestamp", TimestampType(), True),
])

_NOW = datetime.now()

# fmt: off
_RAW_ROWS = [
    # ---------- valid records ----------
    # C001: active, professional, DE, 100 employees → MEDIUM, mrr=299
    ("C001", "DataSystems GmbH",    "Anna Mueller",  "a.mueller@datasystems.de",      "DE", "Berlin",   "Technology",    "professional", 299,  100,  "2023-06-15", "active",  "organic",     _NOW),
    # C002: active, enterprise,    US, 1000 employees → LARGE,  mrr=999
    ("C002", "CloudSolutions Inc.", "John Williams", "j.williams@cloudsolutions.com", "US", "New York", "Finance",       "enterprise",   999, 1000,  "2022-03-10", "active",  "sales",       _NOW),
    # C003: churned, starter,      GB,   30 employees → SMALL,  mrr=49
    ("C003", "TechLabs Ltd",        "Kate Brown",    "k.brown@techlabs.co.uk",        "GB", "London",   "Retail",        "starter",       49,   30,  "2024-01-20", "churned", "paid_search", _NOW),
    # C004: trial,   free,         FR,    5 employees → SMALL,  mrr=0
    ("C004", "ProServices SAS",     "Pierre Dupont", "p.dupont@proservices.fr",       "FR", "Paris",    "Healthcare",    "free",           0,    5,  "2025-02-01", "trial",   "referral",    _NOW),
    # C008: null country → @dp.expect warns, record is KEPT
    ("C008", "Nomad Inc.",          "Alex Wanderer", "alex@nomad.com",                None, None,       "Consulting",    "professional", 299,   50,  "2025-01-10", "trial",   "referral",    _NOW),
    # C009: old signup date → @dp.expect warns, record is KEPT
    ("C009", "OldCo AG",            "Eva Weber",     "e.weber@oldco.ch",              "CH", "Zurich",   "Manufacturing", "professional", 299,  200,  "2019-07-01", "active",  "partner",     _NOW),
    # ---------- invalid records (expect_or_drop) ----------
    # C005: null email  → dropped
    ("C005", "BadMail GmbH",        "Test User",     None,                            "DE", "Munich",   "Technology",    "starter",       49,   20,  "2024-05-01", "active",  "organic",     _NOW),
    # None:  null customer_id → dropped
    (None,   "Ghost Corp",          "Unknown User",  "ghost@ghost.de",                "DE", "Berlin",   "Technology",    "starter",       49,   10,  "2024-03-01", "active",  "organic",     _NOW),
    # C006: plan "gold" not in allowed set → dropped
    ("C006", "WrongPlan GmbH",      "Hans Schmidt",  "h.schmidt@wrongplan.de",        "DE", "Hamburg",  "Finance",       "gold",         499,   50,  "2024-04-01", "active",  "organic",     _NOW),
    # C007: negative mrr → dropped
    ("C007", "NegMRR Ltd",          "James Davis",   "j.davis@negmrr.com",            "US", "Boston",   "Consulting",    "starter",      -10,   25,  "2024-06-01", "active",  "paid_search", _NOW),
]
# fmt: on


@pytest.fixture
def sample_raw_data(spark):
    """10 raw records (6 valid, 4 invalid for DQ demonstration)."""
    return spark.createDataFrame(_RAW_ROWS, RAW_SCHEMA)


# ==========================================================
# Helpers that mirror the pipeline transformation logic
# ==========================================================

def _apply_dq_drops(df):
    """Mirrors the four @dp.expect_or_drop rules in customers_curated()."""
    return (
        df
        .filter(col("customer_id").isNotNull())
        .filter(col("email").isNotNull() & col("email").rlike(r".*@.*\..*"))
        .filter(col("plan").isin("free", "starter", "professional", "enterprise"))
        .filter(col("mrr") >= 0)
    )


def _apply_curated_transforms(df):
    """Mirrors the select + withColumn chain in customers_curated()."""
    return (
        df
        .select(
            col("customer_id"),
            col("company_name"),
            col("contact_name"),
            col("email").alias("email_address"),
            col("country"),
            col("city"),
            col("industry"),
            col("plan"),
            col("mrr").cast("integer"),
            col("employees").cast("integer"),
            to_date(col("signup_date")).alias("signup_date"),
            col("status"),
            col("acquisition_channel"),
            col("ingestion_timestamp"),
            current_timestamp().alias("processed_timestamp"),
        )
        .withColumn("days_since_signup", datediff(current_timestamp(), col("signup_date")))
        .withColumn("arr", col("mrr") * 12)
        .withColumn(
            "company_size",
            when(col("employees") < 50,  "SMALL")
            .when(col("employees") < 500, "MEDIUM")
            .otherwise("LARGE"),
        )
        .withColumn(
            "plan_tier",
            when(col("plan") == "free",         0)
            .when(col("plan") == "starter",      1)
            .when(col("plan") == "professional", 2)
            .when(col("plan") == "enterprise",   3)
            .otherwise(-1),
        )
    )


@pytest.fixture
def curated_data(sample_raw_data):
    """Curated DataFrame: DQ drops applied, transformations applied."""
    return _apply_curated_transforms(_apply_dq_drops(sample_raw_data))


# ==========================================================
# Raw layer tests
# ==========================================================

def test_raw_schema(sample_raw_data):
    expected = [
        "customer_id", "company_name", "contact_name", "email",
        "country", "city", "industry", "plan", "mrr", "employees",
        "signup_date", "status", "acquisition_channel", "ingestion_timestamp",
    ]
    for field in expected:
        assert field in sample_raw_data.columns, f"Missing Raw column: {field}"


def test_raw_row_count(sample_raw_data):
    assert sample_raw_data.count() == 10


# ==========================================================
# Curated DQ tests — expect_or_drop rules
# ==========================================================

def test_curated_drops_null_customer_id(sample_raw_data):
    result = _apply_dq_drops(sample_raw_data)
    ids = [r.customer_id for r in result.select("customer_id").collect()]
    assert None not in ids


def test_curated_drops_null_email(sample_raw_data):
    """C005 has a null email and must be dropped."""
    result = _apply_dq_drops(sample_raw_data)
    ids = [r.customer_id for r in result.select("customer_id").collect()]
    assert "C005" not in ids


def test_curated_drops_invalid_plan(sample_raw_data):
    """C006 has plan='gold' (not in allowed set) and must be dropped."""
    result = _apply_dq_drops(sample_raw_data)
    ids = [r.customer_id for r in result.select("customer_id").collect()]
    assert "C006" not in ids


def test_curated_drops_negative_mrr(sample_raw_data):
    """C007 has mrr=-10 and must be dropped."""
    result = _apply_dq_drops(sample_raw_data)
    ids = [r.customer_id for r in result.select("customer_id").collect()]
    assert "C007" not in ids


def test_curated_valid_record_count(sample_raw_data):
    """Exactly 6 of 10 records survive all expect_or_drop rules."""
    assert _apply_dq_drops(sample_raw_data).count() == 6


def test_curated_keeps_null_country_record(sample_raw_data):
    """C008 has a null country — @dp.expect only warns, must not be dropped."""
    result = _apply_dq_drops(sample_raw_data)
    ids = [r.customer_id for r in result.select("customer_id").collect()]
    assert "C008" in ids


# ==========================================================
# Curated transformation tests — computed fields
# ==========================================================

def test_curated_signup_date_cast_to_date(curated_data):
    assert dict(curated_data.dtypes)["signup_date"] == "date"


def test_curated_email_aliased(curated_data):
    """Raw 'email' must be renamed to 'email_address' in curated."""
    assert "email_address" in curated_data.columns
    assert "email" not in curated_data.columns


def test_curated_arr_equals_mrr_times_12(curated_data):
    for row in curated_data.select("mrr", "arr").collect():
        assert row.arr == row.mrr * 12, f"arr mismatch for mrr={row.mrr}"


def test_curated_days_since_signup_non_negative(curated_data):
    for row in curated_data.select("days_since_signup").collect():
        assert row.days_since_signup >= 0


def test_curated_days_since_signup_old_record(curated_data):
    """C009 signed up in 2019 — at least 5 years old."""
    row = curated_data.filter(col("customer_id") == "C009").collect()[0]
    assert row.days_since_signup > 365 * 5


def test_curated_company_size_small(curated_data):
    """C003: 30 employees → SMALL (< 50)."""
    row = curated_data.filter(col("customer_id") == "C003").collect()[0]
    assert row.company_size == "SMALL"


def test_curated_company_size_medium(curated_data):
    """C001: 100 employees → MEDIUM (50 ≤ x < 500)."""
    row = curated_data.filter(col("customer_id") == "C001").collect()[0]
    assert row.company_size == "MEDIUM"


def test_curated_company_size_large(curated_data):
    """C002: 1000 employees → LARGE (≥ 500)."""
    row = curated_data.filter(col("customer_id") == "C002").collect()[0]
    assert row.company_size == "LARGE"


def test_curated_plan_tier_mapping(curated_data):
    """Tier must follow free=0, starter=1, professional=2, enterprise=3."""
    expected = {"free": 0, "starter": 1, "professional": 2, "enterprise": 3}
    tiers = {r.plan: r.plan_tier for r in curated_data.select("plan", "plan_tier").collect()}
    for plan, tier in expected.items():
        if plan in tiers:
            assert tiers[plan] == tier, f"Wrong plan_tier for {plan}"


# ==========================================================
# Mart layer tests
# ==========================================================

def test_mart_by_country_row_count(curated_data):
    """One row per distinct country value (including NULL as its own group)."""
    mart = curated_data.groupBy("country").agg(count("*").alias("total_customers"))
    # Valid records: DE, US, GB, FR, None, CH  →  6 distinct country values
    assert mart.count() == 6


def test_mart_by_country_mrr(curated_data):
    """C001 (DE, active, mrr=299) is the only German active customer."""
    mart = (
        curated_data.groupBy("country")
        .agg(
            count("*").alias("total_customers"),
            spark_sum(when(col("status") == "active", col("mrr")).otherwise(0)).alias("total_mrr"),
        )
    )
    de = mart.filter(col("country") == "DE").collect()[0]
    assert de.total_customers == 1
    assert de.total_mrr == 299


def test_mart_by_plan_all_plans_present(curated_data):
    """All four plan tiers must appear in the curated fixture."""
    mart = (
        curated_data.groupBy("plan", "plan_tier")
        .agg(count("*").alias("total_customers"))
    )
    plans = {r.plan for r in mart.collect()}
    assert {"free", "starter", "professional", "enterprise"} == plans


def test_mart_by_plan_enterprise_count(curated_data):
    """Only C002 is on enterprise — exactly one row."""
    mart = (
        curated_data.groupBy("plan", "plan_tier")
        .agg(count("*").alias("total_customers"))
    )
    row = mart.filter(col("plan") == "enterprise").collect()[0]
    assert row.total_customers == 1


def test_mart_daily_signups_row_count(curated_data):
    """Each of the 6 valid records has a unique (date, country, plan) combination."""
    mart = (
        curated_data.groupBy("signup_date", "country", "plan")
        .agg(count("*").alias("signups_count"))
    )
    assert mart.count() == 6


def test_mart_kpi_summary_single_row(curated_data):
    """KPI summary must always produce exactly one row."""
    mart = curated_data.agg(count("*").alias("total_customers"))
    assert mart.count() == 1


def test_mart_kpi_summary_values(curated_data):
    """
    From the fixture:
      active:  C001, C002, C009  (3 customers, MRR = 299 + 999 + 299 = 1597)
      churned: C003              (1 customer)
      trial:   C004, C008        (2 customers)
    """
    mart = curated_data.agg(
        count("*").alias("total_customers"),
        count(when(col("status") == "active",  1)).alias("active_customers"),
        count(when(col("status") == "churned", 1)).alias("churned_customers"),
        spark_sum(
            when(col("status") == "active", col("mrr")).otherwise(0)
        ).alias("total_mrr"),
    ).collect()[0]

    assert mart.total_customers  == 6
    assert mart.active_customers == 3
    assert mart.churned_customers == 1
    assert mart.total_mrr == 1597  # 299 + 999 + 299


def test_mart_by_industry_finance_highest_mrr(curated_data):
    """C002 (Finance, active, mrr=999) contributes the highest industry MRR."""
    mart = (
        curated_data.groupBy("industry")
        .agg(
            spark_sum(
                when(col("status") == "active", col("mrr")).otherwise(0)
            ).alias("total_mrr"),
        )
    )
    finance = mart.filter(col("industry") == "Finance").collect()[0]
    assert finance.total_mrr == 999


def test_mart_by_industry_churned_mrr_zero(curated_data):
    """C003 (Retail, churned) must not contribute to active MRR."""
    mart = (
        curated_data.groupBy("industry")
        .agg(
            spark_sum(
                when(col("status") == "active", col("mrr")).otherwise(0)
            ).alias("total_mrr"),
        )
    )
    retail = mart.filter(col("industry") == "Retail").collect()[0]
    assert retail.total_mrr == 0


# ==========================================================
# Edge cases
# ==========================================================

def test_empty_dataframe_does_not_crash(spark):
    empty_df = spark.createDataFrame([], RAW_SCHEMA)
    result = _apply_dq_drops(empty_df)
    assert result.count() == 0


def test_null_country_not_dropped(sample_raw_data):
    """@dp.expect('valid_country') is a warn-only rule — null country stays."""
    result = _apply_dq_drops(sample_raw_data)
    assert result.filter(col("country").isNull()).count() == 1


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
