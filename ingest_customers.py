import requests
import os
import json
from datetime import datetime
from google.cloud import storage
from dotenv import load_dotenv

load_dotenv()

api_key = os.getenv("API_KEY")
api_customers_url = os.getenv("API_CUSTOMERS_URL")
gcp_project_id = os.getenv("GCP_PROJECT_ID")
gcp_bucket_name = os.getenv("GCP_BUCKET_NAME")

API_TIMEOUT = 10
API_LIMIT = 4


def validate_config() -> bool:
    required_vars = {
        "API_KEY": api_key,
        "API_CUSTOMERS_URL": api_customers_url,
        "GCP_PROJECT_ID": gcp_project_id,
        "GCP_BUCKET_NAME": gcp_bucket_name,
    }
    
    missing = [var for var, value in required_vars.items() if not value]
    if missing:
        print(f"Error: missing environments variables{', '.join(missing)}")
        return False
    
    return True

def load_api_customers():
    headers = {"X-API-KEY": api_key}
    start = 0
    all_customers = []
    
    while True:
        params = {"_start": start, "_limit": API_LIMIT}
        r = requests.get(api_customers_url, headers=headers, params=params, timeout=10)

        # Si clé API invalide, on arrête la boucle
        if r.status_code == 401:
            print("Error : Invalid API Key")
            break

        try:
            data = r.json()
        except json.JSONDecodeError:
            print("Error: Invalid JSON response")
            return None
        
        # S'il n'y a plus de données, on arrête la boucle
        if not data:
            break
            
        all_customers.extend(data)
        start += API_LIMIT

    return all_customers

def upload_to_gcs(data, project_id, bucket_name, folder_name):
    if not data:
        print("No data to upload")
        return
    
    try:
        # Connexion à GCS
        storage_client = storage.Client(project=project_id)
        bucket = storage_client.bucket(bucket_name)
        
        # Nom du fichier avec timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        blob_name = f"{folder_name}/customers_{timestamp}.json"
        
        # Sérialisation et upload du JSON
        blob = bucket.blob(blob_name)
        json_data = json.dumps(data, indent=2, ensure_ascii=False)
        blob.upload_from_string(json_data, content_type='application/json')

        print(f"Data uploaded to {blob_name} in bucket {bucket_name}.")

    except Exception as e:
        print(f"Error upload: {e}")


if __name__ == "__main__":
    if not validate_config():
        exit(1)

    customers = load_api_customers()
    upload_to_gcs(customers, gcp_project_id, gcp_bucket_name, 'Customers')