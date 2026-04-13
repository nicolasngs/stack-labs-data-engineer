import json
import logging
import requests
import time
from datetime import datetime
from google.cloud import storage

logger = logging.getLogger(__name__)


def clear_gcs_bucket(project_id, bucket_name, max_retries=3):
    """Delete all objects in the specified GCS bucket with retry logic"""
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt + 1}/{max_retries} to clear bucket '{bucket_name}'")
            
            storage_client = storage.Client(project=project_id)
            bucket = storage_client.bucket(bucket_name)
            
            blobs = bucket.list_blobs()
            deleted_count = 0
            
            for blob in blobs:
                blob.delete()
                deleted_count += 1
                logger.info(f"Deleted: {blob.name}")
            
            logger.info(f"Successfully cleared bucket '{bucket_name}': {deleted_count} objects deleted")
            return deleted_count
        
        except Exception as e:
            error_msg = str(e)
            logger.warning(f"Attempt {attempt + 1} failed: {error_msg}")
            
            # Si c'est une erreur d'authentification et qu'on peut réessayer
            if "not authenticated" in error_msg.lower() or "unauthorized" in error_msg.lower():
                if attempt < max_retries - 1:
                    wait_time = 2 ** attempt  # Exponential backoff: 1s, 2s, 4s
                    logger.info(f"Retrying in {wait_time} seconds...")
                    time.sleep(wait_time)
                    continue
            
            # Si c'est la dernière tentative ou une erreur non-retry, lever l'exception
            raise RuntimeError(f"Failed to clear GCS bucket after {max_retries} attempts: {e}")


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