import sys
import os
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger(__name__)

from ingest_customers import main as main_customers
from ingest_products import main as main_products
from ingest_sales import main as main_sales
from ingest_utils import clear_gcs_bucket


def orchestrate(request=None, context=None):
    logger.info("Starting orchestration...")
    
    # Clear BUCKETS before ingestion as we overwrite, TODO sales should only add datas
    gcp_project_id = os.getenv("GCP_PROJECT_ID")
    gcp_bucket_name = os.getenv("GCP_BUCKET_NAME")
    
    if gcp_project_id and gcp_bucket_name:
        try:
            logger.info(f"Clearing bucket '{gcp_bucket_name}' before ingestion...")
            clear_gcs_bucket(gcp_project_id, gcp_bucket_name)
            logger.info("Bucket cleared successfully")
        except Exception as e:
            logger.error(f"Failed to clear bucket: {e}")
            return {"status": "error", "message": f"Failed to clear bucket: {e}"}, 500
    else:
        logger.warning("Missing GCP_PROJECT_ID or GCP_BUCKET_NAME environment variables")
    
    # Ingest CUSTOMERS
    try:
        logger.info("Running customers ingestion...")
        main_customers()
        logger.info("Customers ingestion completed successfully")
    except Exception as e:
        logger.error(f"Customers ingestion failed: {e}")
        return {"status": "error", "script": "ingest_customers", "error": str(e)}, 500

    # Ingest PRODUCTS
    try:
        logger.info("Running products ingestion...")
        main_products()
        logger.info("Products ingestion completed successfully")
    except Exception as e:
        logger.error(f"Products ingestion failed: {e}")
        return {"status": "error", "script": "ingest_products", "error": str(e)}, 500

    # Ingest SALES
    try:
        logger.info("Running sales ingestion...")
        main_sales()
        logger.info("Sales ingestion completed successfully")
    except Exception as e:
        logger.error(f"Sales ingestion failed: {e}")
        return {"status": "error", "script": "ingest_sales", "error": str(e)}, 500

    logger.info("All ingestions completed successfully!")
    return {"status": "success", "message": "All ingestions completed"}, 200


if __name__ == "__main__":
    status_code = orchestrate()[1]
    sys.exit(0 if status_code == 200 else 1)
