import os
import sys
import logging
import requests
import json
from dotenv import load_dotenv
from ingest_utils import validate_config, upload_to_gcs

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger(__name__)

load_dotenv()

api_key = os.getenv("API_KEY")
api_products_url = os.getenv("API_PRODUCTS_URL")
gcp_project_id = os.getenv("GCP_PROJECT_ID")
gcp_bucket_name = os.getenv("GCP_BUCKET_NAME")

required_vars = {
    "API_KEY": api_key,
    "API_PRODUCTS_URL": api_products_url,
    "GCP_PROJECT_ID": gcp_project_id,
    "GCP_BUCKET_NAME": gcp_bucket_name,
}

API_LIMIT = 4

def load_api_products():
    headers = {"X-API-KEY": api_key}
    start = 0
    all_products = []
    
    while True:
        params = {"_start": start, "_limit": API_LIMIT}
        r = requests.get(api_products_url, headers=headers, params=params, timeout=10)

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
            
        all_products.extend(data)
        start += API_LIMIT

    return all_products


def main():
    # Check configuration
    if not validate_config(required_vars):
        logger.error("Bad configuration")
        sys.exit(1)

    products = load_api_products()
    
    upload_to_gcs(products, gcp_project_id, gcp_bucket_name, 'Products', 'raw_products')

if __name__ == "__main__":
    main()