import snowflake.snowpark.functions as F
from snowflake.snowpark.types import IntegerType, StringType
from util import get_validator_udf

# ==============================================================================
# 1. DECLARATIVE SCHEMA DEFINITION
# ==============================================================================
# Beautiful, clean declaration exactly like your Databricks project!
CUSTOMER_SCHEMA = {
    "id":         {"mandatory": True,  "type": "int"},
    "first_name": {"mandatory": True,  "type": "string"},
    "last_name":  {"mandatory": True,  "type": "string"},
    "email":      {"mandatory": False, "type": "string"},
    "addresses": {
        "mandatory": True,
        "type": "array",
        "element_schema": {
            "address_type": {"mandatory": True,  "type": "string"},
            "line_1":       {"mandatory": True,  "type": "string"},
            "line_2":       {"mandatory": False, "type": "string"},
            "city":         {"mandatory": True,  "type": "string"},
            "state":        {"mandatory": True,  "type": "string"},
            "zip":          {"mandatory": True,  "type": "string"},
        },
    },
}

# ==============================================================================
# 2. SNOWPARK DATAFRAME PIPELINE
# ==============================================================================
def process_customers(session):
    # Dynamically generate the Snowflake Validation UDF using our generic utility!
    validate_udf = get_validator_udf(session, CUSTOMER_SCHEMA, "is_valid_customer")

    # 1. Read the Raw Data (Filtering just for customers)
    df_raw = session.table("ECOMM_DEV.RAW.RAW_DATA").filter(F.col("FILE_NAME").like("%customers.json%"))

    # 2. Apply the dynamic Python UDF to flag records!
    df_validated = df_raw.with_column("is_valid", validate_udf(F.col("PAYLOAD")))

    # 3. Write Clean Data to Staging
    df_clean = df_validated.filter(F.col("is_valid") == True).select(
        F.try_cast(F.col("PAYLOAD")["id"], IntegerType()).alias("customer_id"),
        F.try_cast(F.col("PAYLOAD")["first_name"], StringType()).alias("first_name"),
        F.try_cast(F.col("PAYLOAD")["last_name"], StringType()).alias("last_name"),
        F.try_cast(F.col("PAYLOAD")["email"], StringType()).alias("email"),
        F.col("LOADED_AT").alias("raw_loaded_at")
    )
    
    df_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMERS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    # 4. Write Bad Data to Quarantine
    df_quarantine = df_validated.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
        F.current_timestamp().alias("quarantined_at")
    )
    
    df_quarantine.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMERS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )
    
    return "Pipeline execution complete"
