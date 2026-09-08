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

resource "snowflake_file_format" "csv_format" {
  name                         = "CSV_FORMAT"
  database                     = snowflake_database.ecomm_dev.name
  schema                       = snowflake_schema.raw.name
  format_type                  = "CSV"
  skip_header                  = 1
  field_optionally_enclosed_by = "\""
}

# 3. External Stage pointing to the ADLS Gen2 container (No specific format attached)
resource "snowflake_stage" "adls_stage" {
  name                = "ADLS_RAW_STAGE"
  database            = snowflake_database.ecomm_dev.name
  schema              = snowflake_schema.raw.name
  url                 = "azure://stecommbddev.blob.core.windows.net/raw/"
  storage_integration = snowflake_storage_integration.adls_integration.name
}

# 4. Azure Storage Queue for Snowpipe Event Grid Notifications
resource "azurerm_storage_queue" "snowpipe_queue" {
  name                 = "snowpipedevqueue"
  storage_account_name = "stecommbddev"
}

# 5. Notification Integration in Snowflake
resource "snowflake_notification_integration" "azure_notification" {
  name    = "AZURE_DEV_NOTIFICATION_INTEGRATION"
  type    = "QUEUE"
  enabled = true

  notification_provider           = "AZURE_STORAGE_QUEUE"
  azure_storage_queue_primary_uri = "https://stecommbddev.queue.core.windows.net/${azurerm_storage_queue.snowpipe_queue.name}"
  azure_tenant_id                 = data.azurerm_client_config.current.tenant_id
}

# 6. RAW JSON Tables and Pipes (Iterating over entities)
locals {
  raw_json_tables = [
    "customers",
    "orders",
    "products",
    "return_items",
    "returns",
    "order_items"
  ]
}

resource "snowflake_table" "raw_json_tables" {
  for_each = toset(local.raw_json_tables)

  name     = "RAW_${upper(each.key)}"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  column {
    name = "RAW_DATA"
    type = "VARIANT"
  }
  column {
    name = "METADATA_FILENAME"
    type = "VARCHAR"
  }
}

resource "snowflake_pipe" "raw_json_pipes" {
  for_each = toset(local.raw_json_tables)

  name     = "RAW_${upper(each.key)}_PIPE"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  auto_ingest = true
  integration = snowflake_notification_integration.azure_notification.name

  copy_statement = <<EOF
COPY INTO ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_json_tables[each.key].name} (RAW_DATA, METADATA_FILENAME)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_stage.adls_stage.name}
)
FILE_FORMAT = (FORMAT_NAME = '${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_file_format.json_format.name}')
PATTERN = '.*${each.key}.*\\.json'
EOF
}

# 7. DATES CSV Table and Pipe (Infrequent load)
resource "snowflake_table" "raw_dates" {
  name     = "RAW_DATES"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  column {
    name = "DATE_KEY"
    type = "NUMBER"
  }
  column {
    name = "FULL_DATE"
    type = "DATE"
  }
  column {
    name = "DAY_OF_WEEK"
    type = "NUMBER"
  }
  column {
    name = "DAY_OF_MONTH"
    type = "NUMBER"
  }
  column {
    name = "MONTH"
    type = "NUMBER"
  }
  column {
    name = "MONTH_NAME"
    type = "VARCHAR"
  }
  column {
    name = "QUARTER"
    type = "NUMBER"
  }
  column {
    name = "YEAR"
    type = "NUMBER"
  }
  column {
    name = "IS_WEEKEND"
    type = "BOOLEAN"
  }
}

resource "snowflake_pipe" "raw_dates_pipe" {
  name     = "RAW_DATES_PIPE"
  database = snowflake_database.ecomm_dev.name
  schema   = snowflake_schema.raw.name

  auto_ingest = true
  integration = snowflake_notification_integration.azure_notification.name

  copy_statement = <<EOF
COPY INTO ${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_table.raw_dates.name}
FROM @${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_stage.adls_stage.name}
FILE_FORMAT = (FORMAT_NAME = '${snowflake_database.ecomm_dev.name}.${snowflake_schema.raw.name}.${snowflake_file_format.csv_format.name}')
PATTERN = '.*dates\\.csv'
EOF
}
