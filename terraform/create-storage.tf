# project parameters
locals {
  project_id = "stack-labs-data-engineer"
  region     = "europe-west1"

  services = [
    "iam.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "compute.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com"
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
  account_id   = "sa-data-ingest"
  display_name = "Service Account for Retail Data Ingestion"
}

# Create default Compute Engine service account if it doesn't exist
data "google_client_config" "current" {}

data "google_project" "self" {
  project_id = local.project_id
}

resource "google_service_account" "default_compute" {
  account_id   = "default"
  display_name = "Default Compute Engine Service Account"
}

resource "google_project_iam_member" "default_compute_viewer" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer",
    "roles/pubsub.publisher"
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.self.number}-compute@developer.gserviceaccount.com"
  depends_on = [
    google_project_service.enabled_apis
  ]
}

# Grant Cloud Build service account permissions to access Artifact Registry
resource "google_project_iam_member" "cloudbuild_artifact_registry" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter"
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.self.number}@cloudbuild.gserviceaccount.com"
  depends_on = [
    google_project_service.enabled_apis
  ]
}

resource "google_project_iam_member" "sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/storage.objectViewer",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudscheduler.jobRunner",
    "roles/cloudfunctions.developer",
    "roles/cloudfunctions.invoker",
    "roles/run.invoker",
    "roles/logging.logWriter",
    "roles/artifactregistry.reader"
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.data_ingest_sa.email}"

  depends_on = [
    google_project_service.enabled_apis,
    google_service_account.data_ingest_sa
  ]
}

# Grant Pub/Sub service account permission to invoke Cloud Run (2nd gen functions)
resource "google_project_iam_member" "pubsub_run_invoker" {
  project = local.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:service-${data.google_project.self.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
  depends_on = [
    google_project_service.enabled_apis
  ]
}

# create bucket for raw data
resource "google_storage_bucket" "raw_data" {
  name                        = "${local.project_id}-raw-data"
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


# ============================================================================
# EXTRACT: Cloud function to extract from API rest to bucket json files
# ============================================================================
# Archive du code source de la Cloud Function
data "archive_file" "extract" {
  type        = "zip"
  source_dir  = "${path.module}/../extract"
  output_path = "${path.module}/extract.zip"
}

# Upload le ZIP au bucket existant
resource "google_storage_bucket_object" "extract_zip" {
  name       = "extract.zip"
  bucket     = google_storage_bucket.raw_data.name
  source     = data.archive_file.extract.output_path
  depends_on = [data.archive_file.extract]
}

# Topic Pub/Sub pour déclencher l'ingestion
resource "google_pubsub_topic" "trigger_topic" {
  name       = "topic-ingestion-trigger"
  depends_on = [google_project_service.enabled_apis]
}

# Cloud Function 2e génération pour exécuter les ingesteurs
resource "google_cloudfunctions2_function" "ingest_function" {
  name        = "fn-extract"
  location    = local.region
  description = "Exécute les ingesteurs (customers, products, sales)"

  build_config {
    runtime     = "python311"
    entry_point = "orchestrate"
    source {
      storage_source {
        bucket = google_storage_bucket.raw_data.name
        object = google_storage_bucket_object.extract_zip.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    timeout_seconds       = 300
    service_account_email = google_service_account.data_ingest_sa.email

    # TODO modifier l'URL à chaque creation de tunnel ngrok
    environment_variables = {
      API_KEY            = "test"
      API_URL            = "https://dismantle-hula-upper.ngrok-free.dev"
      API_CUSTOMERS_URL  = "https://dismantle-hula-upper.ngrok-free.dev/customers"
      API_PRODUCTS_URL   = "https://dismantle-hula-upper.ngrok-free.dev/products"
      API_SALES_URL      = "https://dismantle-hula-upper.ngrok-free.dev/sales"
      GCP_PROJECT_ID     = local.project_id
      GCP_BUCKET_NAME    = google_storage_bucket.raw_data.name
    }
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_storage_bucket_object.extract_zip,
    google_pubsub_topic.trigger_topic
  ]
}

# Cloud Scheduler pour déclencher l'ingestion toutes les heures
resource "google_cloud_scheduler_job" "hourly_job" {
  name             = "job-retail-hourly-ingest"
  description      = "Déclenche l'ingestion retail toutes les heures"
  schedule         = "*/1 * * * *" # TODO toutes les 5 minutes pour les tests, à changer en "0 * * * *" pour une exécution toutes les heures
  time_zone        = "Europe/Paris"
  region           = local.region
  attempt_deadline = "600s"
  paused           = false # TODO to pause

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.ingest_function.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.data_ingest_sa.email
    }
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_cloudfunctions2_function.ingest_function,
    google_project_iam_member.sa_roles
  ]
}

# ============================================================================
# LOAD: Cloud functions json to bigQuery
# ============================================================================

# Archive du code source de la Cloud Function
data "archive_file" "load_source" {
  type        = "zip"
  source_dir  = "${path.module}/../load"
  output_path = "${path.module}/load.zip"
}

# Upload le ZIP au bucket
resource "google_storage_bucket_object" "load_zip" {
  name       = "load.zip"
  bucket     = google_storage_bucket.raw_data.name
  source     = data.archive_file.load_source.output_path
  depends_on = [data.archive_file.load_source]
}

# Topic Pub/Sub pour Cloud Storage
resource "google_pubsub_topic" "gcs_events" {
  name       = "topic-gcs-json-events"
  depends_on = [google_project_service.enabled_apis]
}

# Permission pour GCS de publier vers le topic
resource "google_pubsub_topic_iam_member" "gcs_pubsub_publisher" {
  topic  = google_pubsub_topic.gcs_events.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.self.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Notification GCS vers Pub/Sub
resource "google_storage_notification" "gcs_to_pubsub" {
  bucket         = google_storage_bucket.raw_data.name
  payload_format = "JSON_API_V1"
  topic          = "projects/${local.project_id}/topics/${google_pubsub_topic.gcs_events.name}"
  
  depends_on = [
    google_pubsub_topic.gcs_events,
    google_pubsub_topic_iam_member.gcs_pubsub_publisher
  ]
}

# Cloud Function
resource "google_cloudfunctions2_function" "load_function" {
  name        = "fn-load"
  location    = local.region
  description = "Convertit JSON en tables BigQuery"

  build_config {
    runtime     = "python311"
    entry_point = "json_to_bigquery"
    source {
      storage_source {
        bucket = google_storage_bucket.raw_data.name
        object = google_storage_bucket_object.load_zip.name
      }
    }
  }

  service_config {
    max_instance_count    = 100
    timeout_seconds       = 60
    service_account_email = google_service_account.data_ingest_sa.email

    environment_variables = {
      GCP_PROJECT_ID     = local.project_id
      GCP_BUCKET_NAME    = google_storage_bucket.raw_data.name
      BIGQUERY_DATASET   = google_bigquery_dataset.staging.dataset_id
    }
  }

  depends_on = [
    google_project_service.enabled_apis,
    google_storage_bucket_object.load_zip
  ]
}

# Pub/Sub subscription pour déclencher la Cloud Function
resource "google_pubsub_subscription" "gcs_to_function" {
  name            = "sub-gcs-json-events"
  topic           = google_pubsub_topic.gcs_events.name
  ack_deadline_seconds = 45

  push_config {
    push_endpoint = google_cloudfunctions2_function.load_function.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.data_ingest_sa.email
    }
  }

  depends_on = [
    google_cloudfunctions2_function.load_function,
    google_pubsub_topic.gcs_events
  ]
}

# Permission pour Pub/Sub d'invoquer la Cloud Function
resource "google_cloudfunctions2_function_iam_member" "pubsub_invoke" {
  cloud_function = google_cloudfunctions2_function.load_function.name
  location       = local.region
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:service-${data.google_project.self.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}



# ============================================================================
# Transform: from BigQuery tables in staging to data warehouse, ready for analysis
# ============================================================================