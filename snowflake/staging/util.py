from snowflake.snowpark.types import BooleanType, VariantType

def get_validator_udf(session, schema_dict: dict, udf_name: str = "generic_validator"):
    """
    Creates a dynamic, native Snowflake UDF that validates a variant payload 
    against a declared schema dictionary.
    """
    
    # This function will be serialized and run natively on Snowflake!
    # Because of closure serialization, it automatically brings `schema_dict` with it.
    def _validate_record(payload: dict) -> bool:
        if not payload:
            return False
            
        def _check(data, schema):
            for field, spec in schema.items():
                is_mandatory = spec.get("mandatory", False)
                field_type = spec.get("type")
                
                # 1. Missing field check
                if field not in data or data[field] is None:
                    if is_mandatory: 
                        return False
                    continue
                
                val = data[field]
                
                # 2. Type checking (Simplified for demo)
                if field_type == "int" and not isinstance(val, int): 
                    return False
                if field_type == "string" and not isinstance(val, str): 
                    return False
                
                # 3. Nested Array Validation (Recursive)
                if field_type == "array" and "element_schema" in spec:
                    if not isinstance(val, list): 
                        return False
                    for item in val:
                        if not _check(item, spec["element_schema"]): 
                            return False
                            
            return True
            
        return _check(payload, schema_dict)

    # Register the Python function as a permanent Snowflake UDF
    return session.udf.register(
        _validate_record,
        return_type=BooleanType(),
        input_types=[VariantType()],
        name=udf_name,
        is_permanent=True,
        immutable=True,
        stage_location="@ECOMM_DEV.STAGING.UDF_STAGE",
        replace=True
    )
