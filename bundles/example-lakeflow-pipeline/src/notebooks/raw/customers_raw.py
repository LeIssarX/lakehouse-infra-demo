# Databricks notebook source
"""
Customers Raw — Ingestion Layer
================================

Part 1 of 3: Ingests JSONL customer files from a Unity Catalog Volume into
the raw layer using Auto Loader (Spark Structured Streaming).

Raw Layer:  1:1 representation of the source files — no transformations,
            only metadata columns added (ingestion_timestamp, source_file).

Data Flow:
  JSONL files (UC Volume) → raw.customers_raw (streaming table)

Tables Created:
  raw.customers_raw   — Raw SaaS customer records with ingestion metadata

Auto Loader Features:
  - Schema inference and evolution (addNewColumns mode)
  - Exactly-once processing guarantees
  - Automatic file discovery via cloudFiles

Configuration (injected from pipeline YAML):
  source_path     — UC Volume path containing JSONL files
  checkpoint_path — Volume path for streaming checkpoints + schema
"""

from pyspark import pipelines as dp
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp

spark = SparkSession.builder.getOrCreate()

# Configuration (injected from pipeline YAML via spark.conf)
SOURCE_PATH     = spark.conf.get("source_path")
CHECKPOINT_PATH = spark.conf.get("checkpoint_path")

# ==========================================================
# RAW LAYER: Ingest from Volume via Auto Loader
# ==========================================================

@dp.table(
    name="raw.customers_raw",
    comment="Raw SaaS customer records ingested 1:1 from JSONL files via Auto Loader",
    table_properties={
        "pipelines.autoOptimize.managed": "true",
    },
)
def customers_raw():
    """
    Ingest JSONL files from Unity Catalog Volume using Auto Loader.

    No business transformations applied — all source fields preserved as-is.
    Only ingestion metadata columns are added:
      - ingestion_timestamp: when the record was loaded
      - source_file:         originating file path
      - file_modified_time:  last modification time of the source file
    """
    return (
        spark.readStream
            .format("cloudFiles")
            .option("cloudFiles.format", "json")
            .option("cloudFiles.schemaLocation", f"{CHECKPOINT_PATH}/schema")
            .option("cloudFiles.inferColumnTypes", "true")
            .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
            .load(SOURCE_PATH)
            .select(
                "*",
                current_timestamp().alias("ingestion_timestamp"),
                col("_metadata.file_path").alias("source_file"),
                col("_metadata.file_modification_time").alias("file_modified_time"),
            )
    )
