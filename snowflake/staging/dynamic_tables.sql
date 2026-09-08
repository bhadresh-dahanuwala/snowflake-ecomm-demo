-- Use the correct database
USE DATABASE ECOMM_DEV;

-- ==============================================================================
-- 1. STAGING DYNAMIC TABLE (Clean Data)
-- ==============================================================================
CREATE OR REPLACE DYNAMIC TABLE STAGING.CUSTOMERS
  TARGET_LAG = 'DOWNSTREAM'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    WITH CUSTOMERS_BASE_PARSED AS (
      SELECT 
          PAYLOAD:id::VARCHAR AS raw_id,
          TRY_CAST(PAYLOAD:id::VARCHAR AS NUMBER) AS parsed_id,
          PAYLOAD:first_name::VARCHAR AS raw_first_name,
          TRY_CAST(PAYLOAD:first_name::VARCHAR AS VARCHAR) AS parsed_first_name,
          PAYLOAD:last_name::VARCHAR AS raw_last_name,
          TRY_CAST(PAYLOAD:last_name::VARCHAR AS VARCHAR) AS parsed_last_name,
          PAYLOAD:email::VARCHAR AS raw_email,
          TRY_CAST(PAYLOAD:email::VARCHAR AS VARCHAR) AS parsed_email,
          PAYLOAD, FILE_NAME, LOADED_AT,
          CASE 
            WHEN PAYLOAD:id IS NULL OR TRY_CAST(PAYLOAD:id::VARCHAR AS NUMBER) IS NULL THEN TRUE
            WHEN PAYLOAD:first_name IS NULL OR TRY_CAST(PAYLOAD:first_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            WHEN PAYLOAD:last_name IS NULL OR TRY_CAST(PAYLOAD:last_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            WHEN PAYLOAD:addresses IS NULL OR NOT IS_ARRAY(PAYLOAD:addresses) THEN TRUE
            WHEN PAYLOAD:email IS NOT NULL AND TRY_CAST(PAYLOAD:email::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            ELSE FALSE
          END AS base_invalid
      FROM ECOMM_DEV.RAW.RAW_DATA
      WHERE FILE_NAME LIKE '%customers.json%'
    ),
    CUSTOMERS_ADDRESS_VALIDATION AS (
      SELECT 
          FILE_NAME, LOADED_AT, PAYLOAD:id::VARCHAR AS raw_id,
          BOOLOR_AGG(
              CASE 
                WHEN f.value:address_type IS NULL OR TRY_CAST(f.value:address_type::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:line_1 IS NULL OR TRY_CAST(f.value:line_1::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:city IS NULL OR TRY_CAST(f.value:city::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:state IS NULL OR TRY_CAST(f.value:state::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:zip IS NULL OR TRY_CAST(f.value:zip::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:line_2 IS NOT NULL AND TRY_CAST(f.value:line_2::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                ELSE FALSE
              END
          ) AS has_invalid_address
      FROM ECOMM_DEV.RAW.RAW_DATA,
      LATERAL FLATTEN(input => IFF(IS_ARRAY(PAYLOAD:addresses), PAYLOAD:addresses, ARRAY_CONSTRUCT()), outer => TRUE) f
      WHERE FILE_NAME LIKE '%customers.json%'
      GROUP BY FILE_NAME, LOADED_AT, raw_id
    ),
    CUSTOMERS_PARSED AS (
      SELECT 
          b.*,
          CASE 
            WHEN b.base_invalid = TRUE THEN TRUE
            WHEN a.has_invalid_address = TRUE THEN TRUE
            ELSE FALSE 
          END AS is_invalid
      FROM CUSTOMERS_BASE_PARSED b
      JOIN CUSTOMERS_ADDRESS_VALIDATION a 
        ON b.raw_id = a.raw_id AND b.FILE_NAME = a.FILE_NAME AND b.LOADED_AT = a.LOADED_AT
    )
    SELECT
      parsed_id AS customer_id,
      parsed_first_name AS first_name,
      parsed_last_name AS last_name,
      parsed_email AS email,
      LOADED_AT AS raw_loaded_at
    FROM CUSTOMERS_PARSED
    WHERE is_invalid = FALSE;


-- ==============================================================================
-- 2. QUARANTINE DYNAMIC TABLE (Bad Data)
-- ==============================================================================
CREATE OR REPLACE DYNAMIC TABLE QUARANTINE.CUSTOMERS
  TARGET_LAG = 'DOWNSTREAM'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    WITH CUSTOMERS_BASE_PARSED AS (
      SELECT 
          PAYLOAD:id::VARCHAR AS raw_id,
          PAYLOAD, FILE_NAME, LOADED_AT,
          CASE 
            WHEN PAYLOAD:id IS NULL OR TRY_CAST(PAYLOAD:id::VARCHAR AS NUMBER) IS NULL THEN TRUE
            WHEN PAYLOAD:first_name IS NULL OR TRY_CAST(PAYLOAD:first_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            WHEN PAYLOAD:last_name IS NULL OR TRY_CAST(PAYLOAD:last_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            WHEN PAYLOAD:addresses IS NULL OR NOT IS_ARRAY(PAYLOAD:addresses) THEN TRUE
            WHEN PAYLOAD:email IS NOT NULL AND TRY_CAST(PAYLOAD:email::VARCHAR AS VARCHAR) IS NULL THEN TRUE
            ELSE FALSE
          END AS base_invalid
      FROM ECOMM_DEV.RAW.RAW_DATA
      WHERE FILE_NAME LIKE '%customers.json%'
    ),
    CUSTOMERS_ADDRESS_VALIDATION AS (
      SELECT 
          FILE_NAME, LOADED_AT, PAYLOAD:id::VARCHAR AS raw_id,
          BOOLOR_AGG(
              CASE 
                WHEN f.value:address_type IS NULL OR TRY_CAST(f.value:address_type::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:line_1 IS NULL OR TRY_CAST(f.value:line_1::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:city IS NULL OR TRY_CAST(f.value:city::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:state IS NULL OR TRY_CAST(f.value:state::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:zip IS NULL OR TRY_CAST(f.value:zip::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                WHEN f.value:line_2 IS NOT NULL AND TRY_CAST(f.value:line_2::VARCHAR AS VARCHAR) IS NULL THEN TRUE
                ELSE FALSE
              END
          ) AS has_invalid_address
      FROM ECOMM_DEV.RAW.RAW_DATA,
      LATERAL FLATTEN(input => IFF(IS_ARRAY(PAYLOAD:addresses), PAYLOAD:addresses, ARRAY_CONSTRUCT()), outer => TRUE) f
      WHERE FILE_NAME LIKE '%customers.json%'
      GROUP BY FILE_NAME, LOADED_AT, raw_id
    ),
    CUSTOMERS_PARSED AS (
      SELECT 
          b.*,
          CASE 
            WHEN b.base_invalid = TRUE THEN TRUE
            WHEN a.has_invalid_address = TRUE THEN TRUE
            ELSE FALSE 
          END AS is_invalid
      FROM CUSTOMERS_BASE_PARSED b
      JOIN CUSTOMERS_ADDRESS_VALIDATION a 
        ON b.raw_id = a.raw_id AND b.FILE_NAME = a.FILE_NAME AND b.LOADED_AT = a.LOADED_AT
    )
    SELECT
      PAYLOAD AS raw_record,
      FILE_NAME,
      LOADED_AT AS raw_loaded_at,
      CURRENT_TIMESTAMP() AS quarantined_at
    FROM CUSTOMERS_PARSED
    WHERE is_invalid = TRUE;
