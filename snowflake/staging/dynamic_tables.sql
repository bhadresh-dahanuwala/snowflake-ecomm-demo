-- Use the correct database
USE DATABASE ECOMM_DEV;

-- ==============================================================================
-- 1. PARSED VIEWS (Schema Validation & Type Casting)
-- ==============================================================================

-- A. BASE CUSTOMER PARSED VIEW (Top-level validation)
CREATE OR REPLACE VIEW STAGING.CUSTOMERS_BASE_PARSED AS
SELECT 
    PAYLOAD:id::VARCHAR AS raw_id,
    TRY_CAST(PAYLOAD:id::VARCHAR AS NUMBER) AS parsed_id,
    
    PAYLOAD:first_name::VARCHAR AS raw_first_name,
    TRY_CAST(PAYLOAD:first_name::VARCHAR AS VARCHAR) AS parsed_first_name,

    PAYLOAD:last_name::VARCHAR AS raw_last_name,
    TRY_CAST(PAYLOAD:last_name::VARCHAR AS VARCHAR) AS parsed_last_name,

    -- OPTIONAL FIELD: email may be missing, but if present it must cast to string
    PAYLOAD:email::VARCHAR AS raw_email,
    TRY_CAST(PAYLOAD:email::VARCHAR AS VARCHAR) AS parsed_email,
    
    PAYLOAD,
    FILE_NAME,
    LOADED_AT,
    
    -- Base Validation Logic
    CASE 
      -- Mandatory fields
      WHEN PAYLOAD:id IS NULL OR TRY_CAST(PAYLOAD:id::VARCHAR AS NUMBER) IS NULL THEN TRUE
      WHEN PAYLOAD:first_name IS NULL OR TRY_CAST(PAYLOAD:first_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
      WHEN PAYLOAD:last_name IS NULL OR TRY_CAST(PAYLOAD:last_name::VARCHAR AS VARCHAR) IS NULL THEN TRUE
      -- Optional fields
      WHEN PAYLOAD:email IS NOT NULL AND TRY_CAST(PAYLOAD:email::VARCHAR AS VARCHAR) IS NULL THEN TRUE
      ELSE FALSE
    END AS base_invalid
FROM ECOMM_DEV.RAW.RAW_DATA
WHERE FILE_NAME LIKE '%customers.json%';


-- B. NESTED ADDRESS VALIDATION (Flattening and validating arrays)
CREATE OR REPLACE VIEW STAGING.CUSTOMERS_ADDRESS_VALIDATION AS
SELECT 
    FILE_NAME,
    LOADED_AT,
    PAYLOAD:id::VARCHAR AS raw_id,
    BOOLOR_AGG(
        CASE 
          -- Mandatory nested fields
          WHEN f.value:address_type IS NULL OR TRY_CAST(f.value:address_type::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          WHEN f.value:line_1 IS NULL OR TRY_CAST(f.value:line_1::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          WHEN f.value:city IS NULL OR TRY_CAST(f.value:city::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          WHEN f.value:state IS NULL OR TRY_CAST(f.value:state::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          WHEN f.value:zip IS NULL OR TRY_CAST(f.value:zip::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          -- Optional nested field (line_2)
          WHEN f.value:line_2 IS NOT NULL AND TRY_CAST(f.value:line_2::VARCHAR AS VARCHAR) IS NULL THEN TRUE
          ELSE FALSE
        END
    ) AS has_invalid_address
FROM ECOMM_DEV.RAW.RAW_DATA,
LATERAL FLATTEN(input => PAYLOAD:addresses, outer => TRUE) f
WHERE FILE_NAME LIKE '%customers.json%'
GROUP BY FILE_NAME, LOADED_AT, raw_id;


-- C. FINAL COMBINED PARSED VIEW
CREATE OR REPLACE VIEW STAGING.CUSTOMERS_PARSED AS
SELECT 
    b.*,
    CASE 
      WHEN b.base_invalid = TRUE THEN TRUE
      WHEN a.has_invalid_address = TRUE THEN TRUE
      ELSE FALSE 
    END AS is_invalid
FROM STAGING.CUSTOMERS_BASE_PARSED b
JOIN STAGING.CUSTOMERS_ADDRESS_VALIDATION a 
  ON b.raw_id = a.raw_id AND b.FILE_NAME = a.FILE_NAME AND b.LOADED_AT = a.LOADED_AT;


-- ==============================================================================
-- 2. STAGING DYNAMIC TABLES (Clean Data)
-- ==============================================================================
CREATE OR REPLACE DYNAMIC TABLE STAGING.CUSTOMERS
  TARGET_LAG = 'DOWNSTREAM'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    SELECT
      parsed_id AS customer_id,
      parsed_first_name AS first_name,
      parsed_last_name AS last_name,
      parsed_email AS email,
      LOADED_AT AS raw_loaded_at
    FROM STAGING.CUSTOMERS_PARSED
    WHERE is_invalid = FALSE;


-- ==============================================================================
-- 3. QUARANTINE DYNAMIC TABLES (Bad Data)
-- ==============================================================================
CREATE OR REPLACE DYNAMIC TABLE QUARANTINE.CUSTOMERS
  TARGET_LAG = 'DOWNSTREAM'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    SELECT
      PAYLOAD AS raw_record,
      FILE_NAME,
      LOADED_AT AS raw_loaded_at,
      CURRENT_TIMESTAMP() AS quarantined_at
    FROM STAGING.CUSTOMERS_PARSED
    WHERE is_invalid = TRUE;
