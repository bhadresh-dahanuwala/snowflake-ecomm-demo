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

# 2. File Formats
resource "snowflake_file_format" "json_format" {
  name              = "JSON_FORMAT"
  database          = snowflake_database.ecomm_dev.name
  schema            = snowflake_schema.raw.name
  format_type       = "JSON"
  strip_outer_array = true
}

# 3. External Stage pointing to the ADLS Gen2 container (No specific format attached)
resource "snowflake_stage" "adls_stage" {
  name                = "ADLS_RAW_STAGE"
  database            = snowflake_database.ecomm_dev.name
  schema              = snowflake_schema.raw.name
  url                 = "azure://stecommbddev.blob.core.windows.net/raw/"
  storage_integration = snowflake_storage_integration.adls_integration.name
}

# 4. Target Landing Table in the RAW schema
resource "snowflake_table" "raw_data_table" {
  name     = "RAW_DATA"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  column {
    name = "FILE_NAME"
    type = "VARCHAR"
  }
  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = "LOADED_AT"
    type = "TIMESTAMP_NTZ"
    default {
      expression = "CURRENT_TIMESTAMP()"
    }
  }
}

# 5. Azure Storage Queue for Snowpipe Event Grid Notifications
resource "azurerm_storage_queue" "snowpipe_queue" {
  name                 = "snowpipedevqueue"
  storage_account_name = "stecommbddev"
}

# 6. Notification Integration in Snowflake
resource "snowflake_notification_integration" "azure_notification" {
  name    = "AZURE_DEV_NOTIFICATION_INTEGRATION"
  type    = "QUEUE"
  enabled = true

  notification_provider           = "AZURE_STORAGE_QUEUE"
  azure_storage_queue_primary_uri = "https://stecommbddev.queue.core.windows.net/${azurerm_storage_queue.snowpipe_queue.name}"
  azure_tenant_id                 = data.azurerm_client_config.current.tenant_id
}

# 7. Snowpipe to automatically ingest data from the Stage to the Table
resource "snowflake_pipe" "auto_ingest_pipe" {
  name     = "RAW_DATA_PIPE"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  auto_ingest = true
  integration = snowflake_notification_integration.azure_notification.name

  copy_statement = <<EOF
COPY INTO ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_data_table.name} (FILE_NAME, PAYLOAD)
FROM (
  SELECT METADATA$FILENAME, $1
  FROM @${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_stage.adls_stage.name}
)
FILE_FORMAT = (FORMAT_NAME = '${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_file_format.json_format.name}')
EOF
}
