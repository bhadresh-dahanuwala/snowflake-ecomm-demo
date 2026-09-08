# Dev Environment - main.tf

# 1. Create the Snowflake Database for Dev
resource "snowflake_database" "ecomm_dev" {
  name    = "ECOMM_DEV"
  comment = "Database for the e-commerce dev environment"
}

resource "snowflake_warehouse" "ecomm_dev_wh" {
  name           = "ECOMM_DEV_WH"
  warehouse_size = "X-SMALL"
  auto_suspend   = 60
  auto_resume    = true
  comment        = "Compute warehouse for dev environment transformations"
}

# 2. Create the Database Schemas
resource "snowflake_schema" "raw" {
  database = snowflake_database.ecomm_dev.name
  name     = "RAW"
  comment  = "Raw data landing layer"
}

resource "snowflake_schema" "staging" {
  database = snowflake_database.ecomm_dev.name
  name     = "STAGING"
  comment  = "Cleansed and quarantined data layer"
}

resource "snowflake_schema" "intermediate" {
  database = snowflake_database.ecomm_dev.name
  name     = "INTERMEDIATE"
  comment  = "Calculated columns and intermediate transformations layer"
}

resource "snowflake_schema" "quarantine" {
  database = snowflake_database.ecomm_dev.name
  name     = "QUARANTINE"
  comment  = "Quarantined records failing schema validation"
}

resource "snowflake_schema" "analytics" {
  database = snowflake_database.ecomm_dev.name
  name     = "ANALYTICS"
  comment  = "Dimensions and facts layer"
}

# TODO: Add Storage Integration, External Stage, Snowpipe, Roles and Permissions
