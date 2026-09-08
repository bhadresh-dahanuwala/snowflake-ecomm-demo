-- Use the correct schema
USE SCHEMA ECOMM_DEV.STAGING;

-- 1. Create Dynamic Table for STG_CUSTOMERS
CREATE OR REPLACE DYNAMIC TABLE STG_CUSTOMERS
  TARGET_LAG = '10 minutes'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    SELECT
      PAYLOAD:id::NUMBER AS customer_id,
      PAYLOAD:first_name::VARCHAR AS first_name,
      PAYLOAD:last_name::VARCHAR AS last_name,
      LOADED_AT AS raw_loaded_at
    FROM ECOMM_DEV.RAW.RAW_DATA
    WHERE FILE_NAME LIKE '%customers.json%';

-- 2. Create Dynamic Table for STG_ORDERS
CREATE OR REPLACE DYNAMIC TABLE STG_ORDERS
  TARGET_LAG = '10 minutes'
  WAREHOUSE = ECOMM_DEV_WH
  AS
    SELECT
      PAYLOAD:id::NUMBER AS order_id,
      PAYLOAD:user_id::NUMBER AS customer_id,
      PAYLOAD:status::VARCHAR AS order_status,
      PAYLOAD:created_at::TIMESTAMP_NTZ AS created_at,
      LOADED_AT AS raw_loaded_at
    FROM ECOMM_DEV.RAW.RAW_DATA
    WHERE FILE_NAME LIKE '%orders.json%';

-- (Additional staging tables can be added here)
