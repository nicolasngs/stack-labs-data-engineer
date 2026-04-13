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
api_customers_url = os.getenv("API_CUSTOMERS_URL")
gcp_project_id = os.getenv("GCP_PROJECT_ID")
gcp_bucket_name = os.getenv("GCP_BUCKET_NAME")

required_vars = {
    "API_KEY": api_key,
    "API_CUSTOMERS_URL": api_customers_url,
    "GCP_PROJECT_ID": gcp_project_id,
    "GCP_BUCKET_NAME": gcp_bucket_name,
}

API_LIMIT = 4

def load_api_customers():
    headers = {"X-API-KEY": api_key}
    start = 0
    all_customers = []
    
    while True:
        params = {"_start": start, "_limit": API_LIMIT}
        r = requests.get(api_customers_url, headers=headers, params=params, timeout=10)

        # Si clé API invalide, on arrête la boucle
        if r.status_code == 401:
            logger.error("Invalid API Key")
            break

        try:
            data = r.json()
        except json.JSONDecodeError:
            logger.error("Invalid JSON response")
            return None
        
        # S'il n'y a plus de données, on arrête la boucle
        if not data:
            break
            
        all_customers.extend(data)
        start += API_LIMIT

    return all_customers


def main():
    # Check configuration
    if not validate_config(required_vars):
        logger.error("Bad configuration")
        sys.exit(1)

    customers = load_api_customers()
    
    upload_to_gcs(customers, gcp_project_id, gcp_bucket_name, 'Customers', 'raw_customers')

if __name__ == "__main__":
    main()