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
    # Ensure an internal stage exists to store the serialized Python UDFs permanently
    session.sql("CREATE STAGE IF NOT EXISTS ECOMM_DEV.STAGING.UDF_STAGE").collect()

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
        F.col("PAYLOAD")["id"].cast(IntegerType()).alias("customer_id"),
        F.col("PAYLOAD")["first_name"].cast(StringType()).alias("first_name"),
        F.col("PAYLOAD")["last_name"].cast(StringType()).alias("last_name"),
        F.col("PAYLOAD")["email"].cast(StringType()).alias("email"),
        F.col("LOADED_AT").alias("raw_loaded_at")
    )
    df_customer_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    df_customer_quar = df_customer_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
    )
    df_customer_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    # ==============================================================================
    # PIPELINE 2: CUSTOMER CONTACT
    # ==============================================================================
    df_contact_val = df_raw.with_column("is_valid", val_contact(F.col("PAYLOAD")))

    df_contact_clean = (
        df_contact_val.filter(F.col("is_valid") == True)
        .flatten(F.col("PAYLOAD")["contact_numbers"])
        .select(
            F.col("PAYLOAD")["id"].cast(IntegerType()).alias("customer_id"),
            F.col("VALUE").cast(StringType()).alias("contact_number"),
            F.col("LOADED_AT").alias("raw_loaded_at")
        )
    )
    df_contact_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER_CONTACT",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    df_contact_quar = df_contact_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
    )
    df_contact_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER_CONTACT",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    # ==============================================================================
    # PIPELINE 3: CUSTOMER ADDRESS
    # ==============================================================================
    df_address_val = df_raw.with_column("is_valid", val_address(F.col("PAYLOAD")))

    df_address_clean = (
        df_address_val.filter(F.col("is_valid") == True)
        .flatten(F.col("PAYLOAD")["addresses"])
        .select(
            F.col("PAYLOAD")["id"].cast(IntegerType()).alias("customer_id"),
            F.col("VALUE")["address_type"].cast(StringType()).alias("address_type"),
            F.col("VALUE")["line_1"].cast(StringType()).alias("line_1"),
            F.col("VALUE")["line_2"].cast(StringType()).alias("line_2"),
            F.col("VALUE")["city"].cast(StringType()).alias("city"),
            F.col("VALUE")["state"].cast(StringType()).alias("state"),
            F.col("VALUE")["zip"].cast(StringType()).alias("zip"),
            F.col("LOADED_AT").alias("raw_loaded_at")
        )
    )
    df_address_clean.create_or_replace_dynamic_table(
        name="ECOMM_DEV.STAGING.CUSTOMER_ADDRESS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    df_address_quar = df_address_val.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
    )
    df_address_quar.create_or_replace_dynamic_table(
        name="ECOMM_DEV.QUARANTINE.CUSTOMER_ADDRESS",
        warehouse="ECOMM_DEV_WH",
        lag="1 minute",
        refresh_mode="AUTO"
    )

    return "Pipeline execution complete"

if __name__ == "__main__":
    import os
    from snowflake.snowpark import Session
    
    print("Initializing Snowpark session...")
    connection_parameters = {
        "account": os.environ.get("SNOWFLAKE_ACCOUNT"),
        "user": os.environ.get("SNOWFLAKE_USER"),
        "role": os.environ.get("SNOWFLAKE_ROLE", "ACCOUNTADMIN"),
        "warehouse": "ECOMM_DEV_WH",
        "database": "ECOMM_DEV",
        "schema": "STAGING"
    }
    
    # Handle authentication
    if "SNOWFLAKE_PASSWORD" in os.environ:
        connection_parameters["password"] = os.environ["SNOWFLAKE_PASSWORD"]
    elif "SNOWFLAKE_PRIVATE_KEY" in os.environ:
        # Snowpark expects the private key as bytes, and often requires the cryptography library
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.backends import default_backend
        
        p_key = serialization.load_pem_private_key(
            os.environ["SNOWFLAKE_PRIVATE_KEY"].encode(),
            password=None,
            backend=default_backend()
        )
        pkb = p_key.private_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        connection_parameters["private_key"] = pkb
        
    session = Session.builder.configs(connection_parameters).create()
    print("Session created. Executing process_customers...")
    result = process_customers(session)
    print(result)
