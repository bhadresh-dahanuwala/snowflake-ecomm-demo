import snowflake.snowpark.functions as F
from snowflake.snowpark.types import IntegerType, StringType
from util import get_validator_udf

# ==============================================================================
# 1. DECLARATIVE SCHEMA DEFINITIONS
# ==============================================================================

CUSTOMER_SCHEMA = {
    "id":         {"mandatory": True,  "type": "int"},
    "first_name": {"mandatory": True,  "type": "string"},
    "last_name":  {"mandatory": True,  "type": "string"},
    "email":      {"mandatory": False, "type": "string"},
}

CUSTOMER_CONTACT_SCHEMA = {
    "id":         {"mandatory": True,  "type": "int"},
    "first_name": {"mandatory": True,  "type": "string"},
    "last_name":  {"mandatory": True,  "type": "string"},
    "contact_numbers": {"mandatory": True, "type": "array"},
}

CUSTOMER_ADDRESS_SCHEMA = {
    "id":         {"mandatory": True,  "type": "int"},
    "first_name": {"mandatory": True,  "type": "string"},
    "last_name":  {"mandatory": True,  "type": "string"},
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
# 2. SNOWPARK DATAFRAME PIPELINES
# ==============================================================================
def process_customers(session):
    # Dynamically generate the Snowflake Validation UDFs
    val_customer = get_validator_udf(session, CUSTOMER_SCHEMA, "is_valid_customer")
    val_contact = get_validator_udf(session, CUSTOMER_CONTACT_SCHEMA, "is_valid_contact")
    val_address = get_validator_udf(session, CUSTOMER_ADDRESS_SCHEMA, "is_valid_address")

    # 1. Read the Raw Data (Filtering just for customers)
    df_raw = session.table("ECOMM_DEV.RAW.RAW_DATA").filter(F.col("FILE_NAME").like("%customers.json%"))

    # ==============================================================================
    # PIPELINE 1: CUSTOMER
    # ==============================================================================
    df_customer_val = df_raw.with_column("is_valid", val_customer(F.col("PAYLOAD")))

    df_customer_clean = df_customer_val.filter(F.col("is_valid") == True).select(
        F.try_cast(F.col("PAYLOAD")["id"], IntegerType()).alias("customer_id"),
        F.try_cast(F.col("PAYLOAD")["first_name"], StringType()).alias("first_name"),
        F.try_cast(F.col("PAYLOAD")["last_name"], StringType()).alias("last_name"),
        F.try_cast(F.col("PAYLOAD")["email"], StringType()).alias("email"),
        F.col("LOADED_AT").alias("raw_loaded_at")
    )
    df_customer_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    df_customer_quar = df_customer_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
        F.current_timestamp().alias("quarantined_at")
    )
    df_customer_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    # ==============================================================================
    # PIPELINE 2: CUSTOMER CONTACT
    # ==============================================================================
    df_contact_val = df_raw.with_column("is_valid", val_contact(F.col("PAYLOAD")))

    df_contact_clean = (
        df_contact_val.filter(F.col("is_valid") == True)
        .flatten(F.col("PAYLOAD")["contact_numbers"])
        .select(
            F.try_cast(F.col("PAYLOAD")["id"], IntegerType()).alias("customer_id"),
            F.try_cast(F.col("VALUE"), StringType()).alias("contact_number"),
            F.col("LOADED_AT").alias("raw_loaded_at")
        )
    )
    df_contact_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER_CONTACT",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    df_contact_quar = df_contact_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
        F.current_timestamp().alias("quarantined_at")
    )
    df_contact_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER_CONTACT",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    # ==============================================================================
    # PIPELINE 3: CUSTOMER ADDRESS
    # ==============================================================================
    df_address_val = df_raw.with_column("is_valid", val_address(F.col("PAYLOAD")))

    df_address_clean = (
        df_address_val.filter(F.col("is_valid") == True)
        .flatten(F.col("PAYLOAD")["addresses"])
        .select(
            F.try_cast(F.col("PAYLOAD")["id"], IntegerType()).alias("customer_id"),
            F.try_cast(F.col("VALUE")["address_type"], StringType()).alias("address_type"),
            F.try_cast(F.col("VALUE")["line_1"], StringType()).alias("line_1"),
            F.try_cast(F.col("VALUE")["line_2"], StringType()).alias("line_2"),
            F.try_cast(F.col("VALUE")["city"], StringType()).alias("city"),
            F.try_cast(F.col("VALUE")["state"], StringType()).alias("state"),
            F.try_cast(F.col("VALUE")["zip"], StringType()).alias("zip"),
            F.col("LOADED_AT").alias("raw_loaded_at")
        )
    )
    df_address_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER_ADDRESS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    df_address_quar = df_address_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
        F.current_timestamp().alias("quarantined_at")
    )
    df_address_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER_ADDRESS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="INCREMENTAL"
    )

    return "Pipeline execution complete"
