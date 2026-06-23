# Databricks notebook source
"""
Customers Curated — Cleansing & Validation Layer
=================================================

Part 2 of 3: Reads from raw.customers_raw, applies data quality expectations,
type casts, and derives business-level enrichment fields.

Curated Layer:  Cleaned, validated, and enriched data — source of truth for
                all downstream consumption (core, mart, reporting).

Data Flow:
  raw.customers_raw (streaming) → curated.customers_curated (streaming table)

Tables Created:
  curated.customers_curated   — Validated + enriched customer data

Data Quality Rules (Lakeflow @dp.expect_or_drop / @dp.expect):
  DROP  — customer_id IS NULL
  DROP  — email IS NULL OR not matching %@%.% pattern
  DROP  — plan NOT IN ('free', 'starter', 'professional', 'enterprise')
  DROP  — mrr < 0
  WARN  — country IS NULL          (record kept, metric logged)
  WARN  — signup_date < 2020-01-01 (record kept, metric logged)

Derived Fields:
  - email_address      (alias of email)
  - days_since_signup  (current date minus signup_date)
  - arr                (mrr × 12)
  - company_size       (small / medium / large / enterprise based on employees)
  - plan_tier          (integer rank: free=0, starter=1, professional=2, enterprise=3)
"""

from pyspark import pipelines as dp
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, to_date, datediff, when

spark = SparkSession.builder.getOrCreate()

# ==========================================================
# CURATED LAYER: Cleanse, validate, enrich
# ==========================================================

@dp.table(
    name="curated.customers_curated",
    comment="Validated SaaS customer records with derived business fields",
    table_properties={
        "pipelines.autoOptimize.managed": "true",
    },
)
@dp.expect_or_drop("valid_customer_id", "customer_id IS NOT NULL")
@dp.expect_or_drop("valid_email",       "email_address IS NOT NULL AND email_address LIKE '%@%.%'")
@dp.expect_or_drop("valid_plan",        "plan IN ('free', 'starter', 'professional', 'enterprise')")
@dp.expect_or_drop("valid_mrr",         "mrr >= 0")
@dp.expect("valid_country",  "country IS NOT NULL")   # warn — record kept
@dp.expect("recent_signup",  "signup_date >= '2020-01-01'")  # warn — record kept
def customers_curated():
    """
    Reads from raw.customers_curated, applies:
    - Data quality expectations (drop invalid records)
    - Type casting (mrr, employees → integer)
    - Derived fields (arr, days_since_signup, company_size, plan_tier)

    Quality rules:
    - DROP records with missing customer_id, invalid email, invalid plan, or negative MRR
    - WARN (but keep) records with missing country or old signup dates
    """
    return (
        spark.readStream.table("raw.customers_raw")
            .select(
                col("customer_id"),
                col("company_name"),
                col("contact_name"),
                col("email").alias("email_address"),
                col("country"),
                col("city"),
                col("industry"),
                col("signup_date"),
                col("plan"),
                col("status"),
                col("mrr").cast("int"),
                col("employees").cast("int"),
                col("ingestion_timestamp"),
                col("source_file"),
            )
            .withColumn(
                "days_since_signup",
                datediff(current_timestamp(), to_date(col("signup_date"))),
            )
            .withColumn(
                "arr",
                col("mrr") * 12,
            )
            .withColumn(
                "company_size",
                when(col("employees") < 10,     "small")
                .when(col("employees") < 100,   "medium")
                .when(col("employees") < 1000,  "large")
                .otherwise("enterprise"),
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
