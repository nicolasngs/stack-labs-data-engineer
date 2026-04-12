import json
import base64
import os
import logging
from google.cloud import storage
from google.cloud import bigquery

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def json_to_bigquery(request):    
    try:
        envelope = request.get_json()
        if not envelope:
            return ("OK", 204)
        
        pubsub_message = envelope.get('message')
        if not pubsub_message or 'data' not in pubsub_message:
            return ("OK", 204)
        
        try:
            pubsub_data = json.loads(
                base64.b64decode(pubsub_message['data']).decode()
            )
        except Exception:
            return ("OK", 204)
        
        bucket_name = pubsub_data.get('bucket')
        file_name = pubsub_data.get('name')
        
        if not file_name or not file_name.endswith('.json'):
            return ("OK", 204)
        
        project_id = os.getenv("GCP_PROJECT_ID")
        dataset_id = os.getenv("BIGQUERY_DATASET")
        
        # Télécharger le fichier
        storage_client = storage.Client(project=project_id)
        blob = storage_client.bucket(bucket_name).blob(file_name)
        blob_data = blob.download_as_string()
        
        data = json.loads(blob_data)
        if not isinstance(data, list):
            data = [data]
        
        if not data:
            return ("OK", 204)
        
        # Extraire le nom de la table
        table_id = file_name.split('/')[0].lower()
        
        # Charger dans BigQuery
        bq_client = bigquery.Client(project=project_id)
        job_config = bigquery.LoadJobConfig(
            autodetect=True,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
        )
        
        load_job = bq_client.load_table_from_json(
            data,
            f"{project_id}.{dataset_id}.{table_id}",
            job_config=job_config
        )
        load_job.result()
        
        logger.info(f"✓ Table {table_id} mise à jour avec {load_job.output_rows} lignes")
        return ("OK", 200)
    
    except Exception as e:
        logger.error(f"Erreur: {e}")
        return (f"Error: {e}", 500)
