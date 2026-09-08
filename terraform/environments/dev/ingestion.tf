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
COPY INTO ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_data_table.name}
FROM @${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_stage.adls_stage.name}
EOF
}

# 8. Get Existing Storage Account for Event Grid setup
data "azurerm_storage_account" "adls" {
  name                = "stecommbddev"
  resource_group_name = "rg-ecomm-dev"
}

# 9. Azure Event Grid Subscription to trigger Snowpipe
resource "azurerm_eventgrid_event_subscription" "snowpipe_subscription" {
  name  = "snowpipe-dev-subscription"
  scope = data.azurerm_storage_account.adls.id

  storage_queue_endpoint {
    queue_id = azurerm_storage_queue.snowpipe_queue.resource_manager_id
  }

  included_event_types = ["Microsoft.Storage.BlobCreated"]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/raw/"
  }
}
