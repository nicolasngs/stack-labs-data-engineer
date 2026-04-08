import json
import logging
import requests
from datetime import datetime
from google.cloud import storage

logger = logging.getLogger(__name__)


def validate_config(required_vars):
    missing = [var for var, value in required_vars.items() if not value]
    if missing:
        logger.error(f"Missing environment variables: {', '.join(missing)}")
        return False
    return True


def upload_to_gcs(data, project_id, bucket_name, folder_name, file_prefix):
    
    if not data:
        raise ValueError("No data to upload")
    
    try:
        # Connexion à GCS
        storage_client = storage.Client(project=project_id)
        bucket = storage_client.bucket(bucket_name)
        
        # Nom du fichier avec timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        blob_name = f"{folder_name}/{file_prefix}_{timestamp}.json"
        
        # Sérialisation et upload du JSON
        blob = bucket.blob(blob_name)
        json_data = json.dumps(data, indent=2, ensure_ascii=False)
        blob.upload_from_string(json_data, content_type='application/json')
        
        logger.info(f"Data uploaded to gs://{bucket_name}/{blob_name}")
        return blob_name
    
    except Exception as e:
        raise RuntimeError(f"Failed to upload to GCS: {e}")