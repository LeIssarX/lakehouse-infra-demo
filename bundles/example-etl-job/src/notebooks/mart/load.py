# Databricks notebook source
"""
Load — Orders ETL Job
======================

Task 3 of 3: Reads validated curated orders, aggregates by region and month,
and writes a mart summary table optimized for BI queries and dashboards.

Mart Layer:  Business aggregations — analytics-ready, BI-optimized.

Aggregations:
  Per region + order_month:
    - total_orders          (COUNT of orders)
    - completed_orders      (status IN ('shipped', 'delivered'))
    - total_revenue         (SUM of order_value)
    - avg_order_value       (AVG of order_value)
    - high_value_orders     (COUNT where is_high_value = true)

Inputs (widget parameters):
  curated_table — Fully-qualified source table (catalog.schema.table)
  mart_table    — Fully-qualified target table (catalog.schema.table)

Output:
  Mart Delta table with one row per region + order_month combination.
  Overwritten on every run (idempotent aggregation).

Run locally:
  databricks bundle run -t dev etl_workflow --task=load
"""

from databricks.sdk.runtime import dbutils
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, count, sum as spark_sum, avg, round as spark_round,
    when, current_timestamp,
)

spark = SparkSession.builder.getOrCreate()


# ==========================================================
# Parameters
# ==========================================================

dbutils.widgets.text("curated_table", "lakehouse_dev.curated.orders")
dbutils.widgets.text("mart_table",    "lakehouse_dev.mart.orders_by_region")

CURATED_TABLE = dbutils.widgets.get("curated_table")
MART_TABLE    = dbutils.widgets.get("mart_table")

print(f"[load] curated_table : {CURATED_TABLE}")
print(f"[load] mart_table    : {MART_TABLE}")


# ==========================================================
# Step 1: Read curated
# ==========================================================

curated_df = spark.table(CURATED_TABLE)
print(f"[load] Curated rows : {curated_df.count()}")


# ==========================================================
# Step 2: Aggregate by region + order_month
# ==========================================================

mart_df = (
    curated_df
        .groupBy("region", "order_month")
        .agg(
            count("*").alias("total_orders"),
            count(
                when(col("status_normalized").isin("shipped", "delivered"), 1)
            ).alias("completed_orders"),
            spark_round(spark_sum("order_value"), 2).alias("total_revenue"),
            spark_round(avg("order_value"), 2).alias("avg_order_value"),
            count(when(col("is_high_value"), 1)).alias("high_value_orders"),
        )
        .withColumn(
            "completion_rate_pct",
            spark_round(
                100.0 * col("completed_orders") / col("total_orders"), 1
            ),
        )
        .withColumn("aggregated_at", current_timestamp())
        .orderBy("region", "order_month")
)

output_count = mart_df.count()
print(f"[load] Mart rows (region × month) : {output_count}")


# ==========================================================
# Step 3: Write mart (overwrite for idempotency)
# ==========================================================

(
    mart_df.write
        .format("delta")
        .mode("overwrite")
        .option("overwriteSchema", "true")
        .saveAsTable(MART_TABLE)
)

print(f"[load] Done. Written to: {MART_TABLE}")
