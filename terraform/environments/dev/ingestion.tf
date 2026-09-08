# Get current Azure configuration (Tenant ID)
data "azurerm_client_config" "current" {}

# 1. Storage Integration for Azure ADLS Gen2
resource "snowflake_storage_integration" "adls_integration" {
  name = "ADLS_DEV_INTEGRATION"
  type = "EXTERNAL_STAGE"

  enabled = true

  storage_provider = "AZURE"
  azure_tenant_id  = data.azurerm_client_config.current.tenant_id

  storage_allowed_locations = [
    "azure://stecommbddev.blob.core.windows.net/raw/"
  ]
}

# 2. File Format (Assuming CSV for now, adjust to Parquet/JSON if needed)
resource "snowflake_file_format" "csv_format" {
  name        = "CSV_FORMAT"
  database    = snowflake_database.ecomm_dev.name
  schema      = snowflake_schema.raw.name
  format_type = "CSV"

  skip_header                  = 1
  field_optionally_enclosed_by = "\""
}

# 3. External Stage pointing to the ADLS Gen2 container
resource "snowflake_stage" "adls_stage" {
  name                = "ADLS_RAW_STAGE"
  database            = snowflake_database.ecomm_dev.name
  schema              = snowflake_schema.raw.name
  url                 = "azure://stecommbddev.blob.core.windows.net/raw/"
  storage_integration = snowflake_storage_integration.adls_integration.name
  file_format         = "FORMAT_NAME = ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv_format.name}"
}

# 4. Target Table in the RAW schema
# Note: Adjust columns based on the actual schema of your data/20260801 files.
resource "snowflake_table" "raw_data_table" {
  name     = "RAW_DATA"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  column {
    name = "RAW_VARIANT"
    type = "VARIANT"
  }
}

# 5. Snowpipe to automatically ingest data from the Stage to the Table
resource "snowflake_pipe" "auto_ingest_pipe" {
  name     = "RAW_DATA_PIPE"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  auto_ingest = true

  copy_statement = <<EOF
COPY INTO ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_data_table.name}
FROM @${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_stage.adls_stage.name}
EOF
}
