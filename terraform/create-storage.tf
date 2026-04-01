# project parameters
locals {
  project_id = "stack-labs-data-engineer"
  region     = "europe-west1" # Belgique - région GCP la plus proche de Paris

  services = [
    "iam.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquerydatatransfer.googleapis.com"
  ]
}

provider "google" {
  project = local.project_id
  region  = local.region
}

# activate necessary APIs for the project
resource "google_project_service" "enabled_apis" {
  for_each           = toset(local.services)
  service            = each.key
  disable_on_destroy = false
}

# create specific account for data ingestion with necessary permissions
resource "google_service_account" "data_ingest_sa" {
  account_id   = "sa-retail-data-ingest"
  display_name = "Service Account for Retail Data Ingestion"
}

# create a secret in Secret Manager to securely store the Retail API Key
resource "google_secret_manager_secret" "api_key" {
  secret_id = "retail-api-key"
  replication {
    user_managed {
      replicas {
        location = local.region
      }
    }
  }

  depends_on = [google_project_service.enabled_apis]
}

# Roles: Storage (for JSON), BigQuery (for SQL), SecretManager (for API Key), Cloud Functions, Pub/Sub
resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/bigquery.dataEditor",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudscheduler.jobRunner",
    "roles/cloudfunctions.developer",
    "roles/logging.logWriter"
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.data_ingest_sa.email}"

  depends_on = [
    google_project_service.enabled_apis,
    google_service_account.data_ingest_sa
  ]
}

# create bucket for raw data
resource "google_storage_bucket" "raw_data" {
  name                        = "bkt-${local.project_id}-retail-raw"
  location                    = local.region
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.enabled_apis]
}

# Create folder structure for raw data ingestion
resource "google_storage_bucket_object" "products_folder" {
  name    = "Products/"
  bucket  = google_storage_bucket.raw_data.name
  content = " "
}

resource "google_storage_bucket_object" "sales_folder" {
  name    = "Sales/"
  bucket  = google_storage_bucket.raw_data.name
  content = " "
}

resource "google_storage_bucket_object" "customers_folder" {
  name    = "Customers/"
  bucket  = google_storage_bucket.raw_data.name
  content = " "
}

# create staging BigQuery tables, copied from json (Silver layer)
resource "google_bigquery_dataset" "staging" {
  dataset_id = "stg_retail"
  location   = local.region

  depends_on = [google_project_service.enabled_apis]
}

resource "google_bigquery_table" "stg_sales" {
  dataset_id          = google_bigquery_dataset.staging.dataset_id
  table_id            = "sales"
  deletion_protection = false

  schema = jsonencode([
    { name = "id", type = "INT64", mode = "REQUIRED", description = "ID unique de la vente" },
    { name = "datetime", type = "TIMESTAMP", mode = "NULLABLE", description = "Date of the sale" },
    { name = "total_amount", type = "FLOAT64", mode = "NULLABLE", description = "Total amount of the sale" },
    {
      name = "items",
      type = "RECORD",
      mode = "REPEATED",
      fields = [
        { name = "product_sku", type = "STRING", mode = "NULLABLE", description = "SKU of the product" },
        { name = "quantity", type = "INT64", mode = "NULLABLE", description = "Quantity of the product" },
        { name = "amount", type = "FLOAT64", mode = "NULLABLE", description = "Amount of the product" }
      ]
    },
    { name = "customer_id", type = "STRING", mode = "NULLABLE", description = "ID of the customer" },
    { name = "load_timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp of ingestion" }
  ])

  # Optimisation pour les requêtes temporelles
  time_partitioning {
    type  = "MONTH"
    field = "datetime"
  }
}



resource "google_bigquery_table" "stg_products" {
  dataset_id          = google_bigquery_dataset.staging.dataset_id
  table_id            = "products"
  deletion_protection = false

  schema = jsonencode([
    { name = "product_sku", type = "STRING", mode = "REQUIRED", description = "Unique identifier of the product" },
    { name = "description", type = "STRING", mode = "NULLABLE", description = "Product description" },
    { name = "unit_amount", type = "NUMERIC", mode = "NULLABLE", description = "Amount of the product" },
    { name = "supplier", type = "STRING", mode = "NULLABLE", description = "Supplier of the product" },
    { name = "ingestion_timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp of ingestion" }
  ])
}


resource "google_bigquery_table" "stg_customers" {
  dataset_id          = google_bigquery_dataset.staging.dataset_id
  table_id            = "customers"
  deletion_protection = false

  schema = jsonencode([
    { name = "customer_id", type = "STRING", mode = "REQUIRED", description = "Unique identifier of the customer" },
    { name = "emails", type = "STRING", mode = "REPEATED", description = "List of customer emails" },
    { name = "phone_numbers", type = "STRING", mode = "REPEATED", description = "List of customer phone numbers" },
    { name = "ingestion_timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp of ingestion" }
  ])
}



# Data ware house contain final table sales_items, ready to be analysed
resource "google_bigquery_dataset" "reporting" {
  dataset_id = "dw_retail"
  location   = local.region

  depends_on = [google_project_service.enabled_apis]
}

resource "google_bigquery_table" "gold_sales_items" {
  dataset_id          = google_bigquery_dataset.reporting.dataset_id
  table_id            = "sales_items"
  deletion_protection = false

  schema = jsonencode([
    { name = "ID", type = "INT64", mode = "REQUIRED", description = "Clé primaire de la table" },
    { name = "sales_datetime", type = "DATETIME", mode = "NULLABLE", description = "Date de la vente" },
    { name = "item_amount", type = "FLOAT64", mode = "NULLABLE", description = "Montant total par produit et par vente" },
    { name = "product_sku", type = "STRING", mode = "NULLABLE", description = "SKU du produit vendu (unique id)" },
    { name = "item_quantity", type = "INT64", mode = "NULLABLE", description = "Nombre d'item vendu de ce produit" },
    { name = "product_description", type = "STRING", mode = "NULLABLE", description = "Description du produit" },
    { name = "discount_perc", type = "FLOAT64", mode = "NULLABLE", description = "Pourcentage de discount entre le prix catalogue (table products) et le montant unitaire vendu" }
  ])

  depends_on = [google_bigquery_dataset.reporting]
}

resource "google_pubsub_topic" "trigger_topic" {
  name = "topic-ingestion-trigger"

  depends_on = [google_project_service.enabled_apis]
}


resource "google_cloud_scheduler_job" "hourly_job" {
  name             = "job-retail-hourly-ingest"
  description      = "Déclenche l'ingestion retail toutes les heures"
  schedule         = "0 * * * *"
  time_zone        = "Europe/Paris"
  region           = local.region
  attempt_deadline = "600s"

  pubsub_target {
    topic_name = google_pubsub_topic.trigger_topic.id
    data       = base64encode("scheduled-ingestion")
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_pubsub_topic.trigger_topic
  ]
}