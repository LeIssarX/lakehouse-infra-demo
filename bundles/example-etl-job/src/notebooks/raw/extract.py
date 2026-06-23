# Databricks notebook source
"""
Extract — Orders ETL Job
=========================

Task 1 of 3: Reads raw JSON order files from a Unity Catalog Volume and
writes them to a raw Delta table. Creates the table if it does not exist.

Raw Layer:  1:1 representation of source files — no transformations,
            only ingestion metadata columns added.

Inputs (widget parameters):
  source_path — UC Volume path containing raw JSON files
                e.g. /Volumes/lakehouse_dev/raw/raw_files/orders/
  raw_table   — Fully-qualified Delta table name (catalog.schema.table)
                e.g. lakehouse_dev.raw.orders_raw

Output:
  Raw Delta table with order records + ingestion metadata columns.

Run locally (after databricks bundle deploy):
  databricks bundle run -t dev etl_workflow --task=extract
"""

import sys
from databricks.sdk.runtime import dbutils
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, input_file_name

spark = SparkSession.builder.getOrCreate()


# ==========================================================
# Parameters (injected via notebook widgets in Databricks)
# ==========================================================

dbutils.widgets.text("source_path", "/Volumes/lakehouse_dev/raw/raw_files/orders/")
dbutils.widgets.text("raw_table",   "lakehouse_dev.raw.orders_raw")

SOURCE_PATH = dbutils.widgets.get("source_path")
RAW_TABLE   = dbutils.widgets.get("raw_table")

print(f"[extract] source_path : {SOURCE_PATH}")
print(f"[extract] raw_table   : {RAW_TABLE}")


# ==========================================================
# Step 1: Read raw files
# ==========================================================

raw_df = (
    spark.read
        .option("multiLine", "false")
        .option("inferSchema", "true")
        .json(SOURCE_PATH)
        .withColumn("ingestion_timestamp", current_timestamp())
        .withColumn("source_file",         input_file_name())
)

print(f"[extract] Records read  : {raw_df.count()}")
print(f"[extract] Schema:")
raw_df.printSchema()


# ==========================================================
# Step 2: Write to raw Delta table (append + merge schema)
# ==========================================================

(
    raw_df.write
        .format("delta")
        .mode("append")
        .option("mergeSchema", "true")
        .saveAsTable(RAW_TABLE)
)

record_count = spark.table(RAW_TABLE).count()
print(f"[extract] Raw table total rows : {record_count}")
print(f"[extract] Done. Written to: {RAW_TABLE}")
