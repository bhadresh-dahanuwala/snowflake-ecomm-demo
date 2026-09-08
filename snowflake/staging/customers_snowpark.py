import snowflake.snowpark.functions as F
from snowflake.snowpark.types import BooleanType, VariantType, IntegerType, StringType

# ==============================================================================
# 1. PURE PYTHON VALIDATION LOGIC (Runs natively on Snowflake compute nodes!)
# ==============================================================================
# This function behaves exactly like your Databricks PySpark logic. 
# Snowflake will package this into a UDF and parallelize it across the warehouse.
def validate_customer_json(payload: dict) -> bool:
    if not payload:
        return False
        
    # A. Mandatory top-level fields
    if "id" not in payload or not isinstance(payload["id"], int):
        return False
    if "first_name" not in payload or not isinstance(payload["first_name"], str):
        return False
    if "last_name" not in payload or not isinstance(payload["last_name"], str):
        return False
        
    # B. Optional field type check (if it's there, it must be a string)
    if "email" in payload and not isinstance(payload["email"], str):
        return False
        
    # C. Mandatory Nested Array check
    if "addresses" not in payload or not isinstance(payload["addresses"], list):
        return False
        
    # D. Validate every nested address in the array
    for address in payload["addresses"]:
        if "address_type" not in address or not isinstance(address["address_type"], str): return False
        if "line_1" not in address or not isinstance(address["line_1"], str): return False
        if "city" not in address or not isinstance(address["city"], str): return False
        if "state" not in address or not isinstance(address["state"], str): return False
        if "zip" not in address or not isinstance(address["zip"], str): return False
        # Optional nested field
        if "line_2" in address and not isinstance(address["line_2"], str): return False
        
    return True


# ==============================================================================
# 2. SNOWPARK DATAFRAME PIPELINE (Equivalent to Delta Live Tables)
# ==============================================================================
def process_customers(session):
    # Register the pure Python function as a Native Snowflake UDF
    validate_udf = session.udf.register(
        validate_customer_json, 
        return_type=BooleanType(), 
        input_types=[VariantType()],
        name="is_valid_customer",
        is_permanent=False, # Temporary UDF for this pipeline run
        replace=True
    )

    # 1. Read the Raw Data (Filtering just for customers)
    df_raw = session.table("ECOMM_DEV.RAW.RAW_DATA").filter(F.col("FILE_NAME").like("%customers.json%"))

    # 2. Apply the Python UDF to flag records!
    df_validated = df_raw.with_column("is_valid", validate_udf(F.col("PAYLOAD")))

    # 3. Write Clean Data to Staging
    df_clean = df_validated.filter(F.col("is_valid") == True).select(
        F.try_cast(F.col("PAYLOAD")["id"], IntegerType()).alias("customer_id"),
        F.try_cast(F.col("PAYLOAD")["first_name"], StringType()).alias("first_name"),
        F.try_cast(F.col("PAYLOAD")["last_name"], StringType()).alias("last_name"),
        F.try_cast(F.col("PAYLOAD")["email"], StringType()).alias("email"),
        F.col("LOADED_AT").alias("raw_loaded_at")
    )
    
    # In a real Snowpark Task, you would append/merge to the target table:
    # df_clean.write.mode("append").save_as_table("ECOMM_DEV.STAGING.CUSTOMERS")

    # 4. Write Bad Data to Quarantine
    df_quarantine = df_validated.filter(F.col("is_valid") == False).select(
        F.col("PAYLOAD").alias("raw_record"),
        F.col("FILE_NAME"),
        F.col("LOADED_AT").alias("raw_loaded_at"),
        F.current_timestamp().alias("quarantined_at")
    )
    
    # df_quarantine.write.mode("append").save_as_table("ECOMM_DEV.QUARANTINE.CUSTOMERS")
    
    return "Pipeline execution complete"
