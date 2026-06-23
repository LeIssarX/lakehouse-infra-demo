"""
Unit Tests — Orders ETL Job
============================

Tests validate transformation and aggregation logic using a local Spark session.
No Databricks cluster or Unity Catalog connection required.

Run locally:
    pip install -r requirements-test.txt
    pytest tests/ -v

Test coverage:
  - transform: type casting, DQ drop rules, enrichment (order_value, is_high_value, status_normalized)
  - load:      aggregation correctness (total_orders, revenue, completion_rate_pct)
"""

import pytest
from datetime import date
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField,
    StringType, IntegerType, DoubleType, BooleanType, DateType,
)
from pyspark.sql.functions import (
    col, to_date, date_format, round as spark_round,
    when, count, sum as spark_sum, avg,
)


# ==========================================================
# Fixtures
# ==========================================================

@pytest.fixture(scope="session")
def spark():
    return (
        SparkSession.builder
            .appName("OrdersETLTests")
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


BRONZE_SCHEMA = StructType([
    StructField("order_id",    StringType(),  True),
    StructField("customer_id", StringType(),  True),
    StructField("product",     StringType(),  True),
    StructField("quantity",    IntegerType(), True),
    StructField("unit_price",  DoubleType(),  True),
    StructField("order_date",  StringType(),  True),
    StructField("status",      StringType(),  True),
    StructField("region",      StringType(),  True),
    StructField("channel",     StringType(),  True),
])


def make_raw(spark, rows):
    """Helper: build a raw-schema DataFrame from a list of dicts."""
    return spark.createDataFrame(rows, schema=BRONZE_SCHEMA)


def apply_transform(spark, raw_df):
    """
    Replicates the transform.py logic as a pure function for testing.
    Returns the curated DataFrame.
    """
    VALID_STATUSES = ["pending", "confirmed", "shipped", "delivered", "cancelled"]

    clean_df = (
        raw_df
            .filter(col("order_id").isNotNull())
            .filter(col("quantity") > 0)
            .filter(col("unit_price") > 0)
            .filter(col("order_date").isNotNull())
    )

    return (
        clean_df
            .withColumn("order_date",         to_date(col("order_date")))
            .withColumn("order_month",         date_format(col("order_date"), "yyyy-MM"))
            .withColumn("order_value",         spark_round(col("quantity") * col("unit_price"), 2))
            .withColumn("is_high_value",       when(col("order_value") >= 1000, True).otherwise(False))
            .withColumn(
                "status_normalized",
                when(col("status").isin(VALID_STATUSES), col("status")).otherwise("unknown"),
            )
    )


def apply_load(curated_df):
    """
    Replicates the load.py aggregation logic for testing.
    Returns the mart DataFrame.
    """
    return (
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
                spark_round(100.0 * col("completed_orders") / col("total_orders"), 1),
            )
            .orderBy("region", "order_month")
    )


# ==========================================================
# Transform Tests
# ==========================================================

class TestTransform:

    def test_valid_record_passes(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-001", "customer_id": "C-1", "product": "Widget",
            "quantity": 2, "unit_price": 50.0, "order_date": "2024-03-15",
            "status": "delivered", "region": "EMEA", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        assert curated.count() == 1

    def test_null_order_id_dropped(self, spark):
        raw = make_raw(spark, [{
            "order_id": None, "customer_id": "C-1", "product": "Widget",
            "quantity": 2, "unit_price": 50.0, "order_date": "2024-03-15",
            "status": "delivered", "region": "EMEA", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        assert curated.count() == 0

    def test_zero_quantity_dropped(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-002", "customer_id": "C-2", "product": "Gadget",
            "quantity": 0, "unit_price": 25.0, "order_date": "2024-03-15",
            "status": "pending", "region": "AMER", "channel": "phone",
        }])
        curated = apply_transform(spark, raw)
        assert curated.count() == 0

    def test_negative_price_dropped(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-003", "customer_id": "C-3", "product": "Thingamajig",
            "quantity": 1, "unit_price": -10.0, "order_date": "2024-03-15",
            "status": "confirmed", "region": "APAC", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        assert curated.count() == 0

    def test_null_order_date_dropped(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-004", "customer_id": "C-4", "product": "Doohickey",
            "quantity": 3, "unit_price": 30.0, "order_date": None,
            "status": "shipped", "region": "EMEA", "channel": "api",
        }])
        curated = apply_transform(spark, raw)
        assert curated.count() == 0

    def test_order_value_computed(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-005", "customer_id": "C-5", "product": "Widget",
            "quantity": 4, "unit_price": 125.0, "order_date": "2024-06-01",
            "status": "delivered", "region": "AMER", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        row = curated.collect()[0]
        assert row["order_value"] == 500.0

    def test_is_high_value_true(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-006", "customer_id": "C-6", "product": "Enterprise",
            "quantity": 5, "unit_price": 250.0, "order_date": "2024-06-01",
            "status": "confirmed", "region": "EMEA", "channel": "direct",
        }])
        curated = apply_transform(spark, raw)
        row = curated.collect()[0]
        assert row["order_value"] == 1250.0
        assert row["is_high_value"] is True

    def test_is_high_value_false_below_threshold(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-007", "customer_id": "C-7", "product": "Widget",
            "quantity": 1, "unit_price": 999.99, "order_date": "2024-06-01",
            "status": "shipped", "region": "APAC", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        row = curated.collect()[0]
        assert row["is_high_value"] is False

    def test_unknown_status_normalized(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-008", "customer_id": "C-8", "product": "Widget",
            "quantity": 2, "unit_price": 10.0, "order_date": "2024-06-15",
            "status": "refunded", "region": "EMEA", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        row = curated.collect()[0]
        assert row["status_normalized"] == "unknown"

    def test_valid_status_preserved(self, spark):
        for status in ["pending", "confirmed", "shipped", "delivered", "cancelled"]:
            raw = make_raw(spark, [{
                "order_id": f"O-{status}", "customer_id": "C-9", "product": "Widget",
                "quantity": 1, "unit_price": 10.0, "order_date": "2024-07-01",
                "status": status, "region": "AMER", "channel": "online",
            }])
            curated = apply_transform(spark, raw)
            row = curated.collect()[0]
            assert row["status_normalized"] == status, f"Status {status} should be preserved"

    def test_order_month_extracted(self, spark):
        raw = make_raw(spark, [{
            "order_id": "O-009", "customer_id": "C-10", "product": "Widget",
            "quantity": 1, "unit_price": 10.0, "order_date": "2024-08-22",
            "status": "delivered", "region": "APAC", "channel": "online",
        }])
        curated = apply_transform(spark, raw)
        row = curated.collect()[0]
        assert row["order_month"] == "2024-08"

    def test_mixed_valid_and_invalid(self, spark):
        raw = make_raw(spark, [
            {"order_id": "O-010", "customer_id": "C-1", "product": "A", "quantity": 1, "unit_price": 10.0, "order_date": "2024-01-01", "status": "delivered", "region": "EMEA", "channel": "online"},
            {"order_id": None,    "customer_id": "C-2", "product": "B", "quantity": 1, "unit_price": 10.0, "order_date": "2024-01-01", "status": "delivered", "region": "EMEA", "channel": "online"},
            {"order_id": "O-012", "customer_id": "C-3", "product": "C", "quantity": 0, "unit_price": 10.0, "order_date": "2024-01-01", "status": "pending",   "region": "AMER", "channel": "online"},
        ])
        curated = apply_transform(spark, raw)
        assert curated.count() == 1
        assert curated.collect()[0]["order_id"] == "O-010"


# ==========================================================
# Load (Aggregation) Tests
# ==========================================================

class TestLoad:

    CURATED_SCHEMA = StructType([
        StructField("order_id",          StringType(),  True),
        StructField("region",            StringType(),  True),
        StructField("order_month",       StringType(),  True),
        StructField("order_value",       DoubleType(),  True),
        StructField("is_high_value",     BooleanType(), True),
        StructField("status_normalized", StringType(),  True),
    ])

    def make_curated(self, spark, rows):
        return spark.createDataFrame(rows, schema=self.CURATED_SCHEMA)

    def test_total_orders_count(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "EMEA", "order_month": "2024-01", "order_value": 100.0, "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "EMEA", "order_month": "2024-01", "order_value": 200.0, "is_high_value": False, "status_normalized": "shipped"},
            {"order_id": "O-3", "region": "EMEA", "order_month": "2024-01", "order_value": 300.0, "is_high_value": False, "status_normalized": "pending"},
        ])
        mart = apply_load(curated)
        row = mart.collect()[0]
        assert row["total_orders"] == 3

    def test_completed_orders_only_shipped_and_delivered(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "AMER", "order_month": "2024-02", "order_value": 100.0, "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "AMER", "order_month": "2024-02", "order_value": 100.0, "is_high_value": False, "status_normalized": "shipped"},
            {"order_id": "O-3", "region": "AMER", "order_month": "2024-02", "order_value": 100.0, "is_high_value": False, "status_normalized": "pending"},
            {"order_id": "O-4", "region": "AMER", "order_month": "2024-02", "order_value": 100.0, "is_high_value": False, "status_normalized": "cancelled"},
        ])
        mart = apply_load(curated)
        row = mart.collect()[0]
        assert row["completed_orders"] == 2
        assert row["total_orders"] == 4

    def test_total_revenue_sum(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "APAC", "order_month": "2024-03", "order_value": 100.0, "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "APAC", "order_month": "2024-03", "order_value": 250.0, "is_high_value": False, "status_normalized": "shipped"},
        ])
        mart = apply_load(curated)
        row = mart.collect()[0]
        assert row["total_revenue"] == 350.0

    def test_high_value_order_count(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "EMEA", "order_month": "2024-04", "order_value": 1500.0, "is_high_value": True,  "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "EMEA", "order_month": "2024-04", "order_value": 200.0,  "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-3", "region": "EMEA", "order_month": "2024-04", "order_value": 2000.0, "is_high_value": True,  "status_normalized": "shipped"},
        ])
        mart = apply_load(curated)
        row = mart.collect()[0]
        assert row["high_value_orders"] == 2

    def test_completion_rate_calculated(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "AMER", "order_month": "2024-05", "order_value": 100.0, "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "AMER", "order_month": "2024-05", "order_value": 100.0, "is_high_value": False, "status_normalized": "shipped"},
            {"order_id": "O-3", "region": "AMER", "order_month": "2024-05", "order_value": 100.0, "is_high_value": False, "status_normalized": "pending"},
            {"order_id": "O-4", "region": "AMER", "order_month": "2024-05", "order_value": 100.0, "is_high_value": False, "status_normalized": "pending"},
        ])
        mart = apply_load(curated)
        row = mart.collect()[0]
        assert row["completion_rate_pct"] == 50.0

    def test_grouped_by_region_and_month(self, spark):
        curated = self.make_curated(spark, [
            {"order_id": "O-1", "region": "EMEA", "order_month": "2024-01", "order_value": 100.0, "is_high_value": False, "status_normalized": "delivered"},
            {"order_id": "O-2", "region": "AMER", "order_month": "2024-01", "order_value": 200.0, "is_high_value": False, "status_normalized": "shipped"},
            {"order_id": "O-3", "region": "EMEA", "order_month": "2024-02", "order_value": 300.0, "is_high_value": False, "status_normalized": "pending"},
        ])
        mart = apply_load(curated)
        assert mart.count() == 3
        regions = {r["region"] for r in mart.select("region").collect()}
        assert regions == {"EMEA", "AMER"}
