import os
import sys
import logging
import requests
import json
# from dotenv import load_dotenv
from ingest_utils import validate_config, upload_to_gcs

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger(__name__)

#load_dotenv()

api_key = os.getenv("API_KEY")
api_sales_url = os.getenv("API_SALES_URL")
gcp_project_id = os.getenv("GCP_PROJECT_ID")
gcp_bucket_name = os.getenv("GCP_BUCKET_NAME")

required_vars = {
    "API_KEY": api_key,
    "API_SALES_URL": api_sales_url,
    "GCP_PROJECT_ID": gcp_project_id,
    "GCP_BUCKET_NAME": gcp_bucket_name,
}

API_LIMIT = 4

# TODO: prendre uniquement à partir de start_sales_id
def load_api_sales():
    headers = {"X-API-KEY": api_key}
    start = 0
    all_sales = []
    
    while True:
        params = {"_start": start, "_limit": API_LIMIT}
        r = requests.get(api_sales_url, headers=headers, params=params, timeout=10)

        # Si clé API invalide, on arrête la boucle
        if r.status_code == 401:
            logger.error("Error : Invalid API Key")
            break

        try:
            data = r.json()
        except json.JSONDecodeError:
            logger.error("Error: Invalid JSON response")
            return None
        
        # S'il n'y a plus de données, on arrête la boucle
        if not data:
            break
            
        all_sales.extend(data)
        start += API_LIMIT

    return all_sales


def main():
    # Check configuration
    if not validate_config(required_vars):
        logger.error("Bad configuration")
        sys.exit(1)

    sales = load_api_sales()
    
    upload_to_gcs(sales, gcp_project_id, gcp_bucket_name, 'Sales', 'raw_sales')

if __name__ == "__main__":
    main()