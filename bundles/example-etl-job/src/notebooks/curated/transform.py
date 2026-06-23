# Databricks notebook source
"""
Transform — Orders ETL Job
===========================

Task 2 of 3: Reads from the raw Delta table, applies data quality checks,
type casts, and business-level enrichment, then writes to a curated Delta table.

Data Quality Rules:
  DROP  — order_id IS NULL
  DROP  — quantity <= 0 OR unit_price <= 0
  DROP  — order_date IS NULL
  WARN  — status NOT IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')
  WARN  — region IS NULL

Enrichment:
  - order_value   (quantity * unit_price)
  - order_month   (YYYY-MM string for partitioning)
  - is_high_value (order_value >= 1000)

Inputs (widget parameters):
  raw_table     — Fully-qualified source table (catalog.schema.table)
  curated_table — Fully-qualified target table (catalog.schema.table)

Output:
  Curated Delta table with validated, typed, and enriched order records.
  Existing table is overwritten (full refresh per run) for idempotency.

Run locally:
  databricks bundle run -t dev etl_workflow --task=transform
"""

from databricks.sdk.runtime import dbutils
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, to_date, date_format, round as spark_round,
    when, current_timestamp,
)
from pyspark.sql.types import IntegerType, DoubleType

spark = SparkSession.builder.getOrCreate()


# ==========================================================
# Parameters
# ==========================================================

dbutils.widgets.text("raw_table",     "lakehouse_dev.raw.orders_raw")
dbutils.widgets.text("curated_table", "lakehouse_dev.curated.orders")

RAW_TABLE     = dbutils.widgets.get("raw_table")
CURATED_TABLE = dbutils.widgets.get("curated_table")

print(f"[transform] raw_table     : {RAW_TABLE}")
print(f"[transform] curated_table : {CURATED_TABLE}")


# ==========================================================
# Step 1: Read raw
# ==========================================================

raw_df = spark.table(RAW_TABLE)
input_count = raw_df.count()
print(f"[transform] Input rows : {input_count}")


# ==========================================================
# Step 2: Type casting + column selection
# ==========================================================

typed_df = (
    raw_df
        .select(
            col("order_id").cast("string"),
            col("customer_id").cast("string"),
            col("product").cast("string"),
            col("quantity").cast(IntegerType()),
            col("unit_price").cast(DoubleType()),
            col("order_date").cast("string"),
            col("status").cast("string"),
            col("region").cast("string"),
            col("channel").cast("string"),
            col("ingestion_timestamp"),
            col("source_file"),
        )
)


# ==========================================================
# Step 3: Data quality — drop invalid records
# ==========================================================

VALID_STATUSES = ["pending", "confirmed", "shipped", "delivered", "cancelled"]

clean_df = (
    typed_df
        # DROP rules
        .filter(col("order_id").isNotNull())
        .filter(col("quantity") > 0)
        .filter(col("unit_price") > 0)
        .filter(col("order_date").isNotNull())
)

dropped_count = input_count - clean_df.count()
print(f"[transform] Dropped (DQ failures) : {dropped_count}")


# ==========================================================
# Step 4: Enrichment
# ==========================================================

enriched_df = (
    clean_df
        .withColumn("order_date",   to_date(col("order_date")))
        .withColumn("order_month",  date_format(col("order_date"), "yyyy-MM"))
        .withColumn("order_value",  spark_round(col("quantity") * col("unit_price"), 2))
        .withColumn(
            "is_high_value",
            when(col("order_value") >= 1000, True).otherwise(False),
        )
        .withColumn(
            "status_normalized",
            when(col("status").isin(VALID_STATUSES), col("status")).otherwise("unknown"),
        )
        .withColumn("processed_at", current_timestamp())
)


# ==========================================================
# Step 5: Write curated (overwrite for idempotency)
# ==========================================================

output_count = enriched_df.count()
print(f"[transform] Output rows : {output_count}")

(
    enriched_df.write
        .format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        .partitionBy("order_month")
        .saveAsTable(CURATED_TABLE)
)

print(f"[transform] Done. Written to: {CURATED_TABLE}")
