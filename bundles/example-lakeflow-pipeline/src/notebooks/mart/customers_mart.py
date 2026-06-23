# Databricks notebook source
"""
Customers Mart — Aggregations & KPIs
======================================

Part 3 of 3: Reads from curated.customers_curated and produces five
dashboard-ready materialized views in the mart layer.

Mart Layer:  Business aggregations and KPIs — analytics-ready, BI-optimized.
             Refreshed on every pipeline run (full recompute from curated).

Data Flow:
  curated.customers_curated → mart.customers_by_country
                             → mart.customers_by_plan
                             → mart.customers_daily_signups
                             → mart.customers_kpi_summary
                             → mart.customers_by_industry

Tables Created:
  mart.customers_by_country      — Revenue breakdown by country (choropleth / bar chart)
  mart.customers_by_plan         — Revenue breakdown by subscription plan
  mart.customers_daily_signups   — Growth trend (signups per day × country)
  mart.customers_kpi_summary     — Single-row KPI header tiles (MRR, ARR, churn rate)
  mart.customers_by_industry     — Revenue distribution by industry vertical
"""

from pyspark import pipelines as dp
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, current_timestamp, count, avg, sum as spark_sum, when

spark = SparkSession.builder.getOrCreate()

# ==========================================================
# MART LAYER: Dashboard-Ready Aggregations
# ==========================================================

@dp.materialized_view(
    name="mart.customers_by_country",
    comment="Customer counts and MRR broken down by country — for a choropleth / bar chart",
    table_properties={"pipelines.autoOptimize.managed": "true"},
)
def customers_by_country():
    """
    Aggregates customer metrics by country:
    - Total, active, churned, and trial customer counts
    - Total and average MRR for active customers
    """
    return (
        spark.read.table("curated.customers_curated")
            .groupBy("country")
            .agg(
                count("*").alias("total_customers"),
                count(when(col("status") == "active",  1)).alias("active_customers"),
                count(when(col("status") == "churned", 1)).alias("churned_customers"),
                count(when(col("status") == "trial",   1)).alias("trial_customers"),
                spark_sum(
                    when(col("status") == "active", col("mrr")).otherwise(0)
                ).alias("total_mrr"),
                avg(
                    when(col("status") == "active", col("mrr"))
                ).alias("avg_mrr_active"),
                current_timestamp().alias("aggregation_timestamp"),
            )
    )


@dp.materialized_view(
    name="mart.customers_by_plan",
    comment="Revenue and customer counts per subscription plan — for a revenue breakdown chart",
    table_properties={"pipelines.autoOptimize.managed": "true"},
)
def customers_by_plan():
    """
    Aggregates metrics by subscription plan:
    - Customer distribution across plans
    - Revenue per plan tier
    - Average days since signup
    """
    return (
        spark.read.table("curated.customers_curated")
            .groupBy("plan", "plan_tier")
            .agg(
                count("*").alias("total_customers"),
                count(when(col("status") == "active",  1)).alias("active_customers"),
                count(when(col("status") == "churned", 1)).alias("churned_customers"),
                spark_sum(
                    when(col("status") == "active", col("mrr")).otherwise(0)
                ).alias("total_mrr"),
                avg(
                    when(col("status") == "active", col("mrr"))
                ).alias("avg_mrr_active"),
                avg("days_since_signup").alias("avg_days_since_signup"),
                current_timestamp().alias("aggregation_timestamp"),
            )
            .orderBy("plan_tier")
    )


@dp.materialized_view(
    name="mart.customers_daily_signups",
    comment="New customer signups per day and country — for a time-series growth chart",
    table_properties={"pipelines.autoOptimize.managed": "true"},
)
def customers_daily_signups():
    """
    Time-series data for growth analysis:
    - Daily signup counts by country and plan
    - MRR added per day
    """
    return (
        spark.read.table("curated.customers_curated")
            .groupBy("signup_date", "country", "plan")
            .agg(
                count("*").alias("signups_count"),
                spark_sum("mrr").alias("mrr_added"),
                current_timestamp().alias("aggregation_timestamp"),
            )
            .orderBy("signup_date")
    )


@dp.materialized_view(
    name="mart.customers_kpi_summary",
    comment="Single-row KPI summary — for dashboard header tiles (total MRR, churn rate, etc.)",
    table_properties={"pipelines.autoOptimize.managed": "true"},
)
def customers_kpi_summary():
    """
    Produces one row with business KPIs:
      total_mrr, active_customers, churned_customers, trial_customers,
      avg_mrr_active, churn_rate_pct, enterprise_count, arr_total

    Used for dashboard header tiles showing key metrics at a glance.
    """
    return (
        spark.read.table("curated.customers_curated")
            .agg(
                count("*").alias("total_customers"),
                count(when(col("status") == "active",  1)).alias("active_customers"),
                count(when(col("status") == "churned", 1)).alias("churned_customers"),
                count(when(col("status") == "trial",   1)).alias("trial_customers"),
                count(when(col("plan") == "enterprise", 1)).alias("enterprise_count"),
                spark_sum(
                    when(col("status") == "active", col("mrr")).otherwise(0)
                ).alias("total_mrr"),
                # ARR = total_mrr * 12
                (spark_sum(
                    when(col("status") == "active", col("mrr")).otherwise(0)
                ) * 12).alias("arr_total"),
                avg(
                    when(col("status") == "active", col("mrr"))
                ).alias("avg_mrr_active"),
                # churn_rate_pct = avg(1 if churned else 0) * 100
                (avg(when(col("status") == "churned", 1).otherwise(0)) * 100)
                    .alias("churn_rate_pct"),
                current_timestamp().alias("calculated_at"),
            )
    )


@dp.materialized_view(
    name="mart.customers_by_industry",
    comment="Customer counts and MRR broken down by industry vertical — for a pie / treemap chart",
    table_properties={"pipelines.autoOptimize.managed": "true"},
)
def customers_by_industry():
    """
    Industry vertical analysis:
    - Customer distribution across industries
    - Revenue per industry
    - Average MRR per customer by industry
    """
    return (
        spark.read.table("curated.customers_curated")
            .groupBy("industry")
            .agg(
                count("*").alias("total_customers"),
                count(when(col("status") == "active",  1)).alias("active_customers"),
                count(when(col("status") == "churned", 1)).alias("churned_customers"),
                spark_sum(
                    when(col("status") == "active", col("mrr")).otherwise(0)
                ).alias("total_mrr"),
                avg(
                    when(col("status") == "active", col("mrr"))
                ).alias("avg_mrr_per_customer"),
                current_timestamp().alias("aggregation_timestamp"),
            )
    )
