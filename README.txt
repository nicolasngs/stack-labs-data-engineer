API
cd api
npm install
npx json-server@0.17.4 api.json --middlewares ./middleware.js --port 3000

Generer une url accessible depuis l'exterieur: 
ngrok http 3000 
Copier cette url pour la mettre dans le fichier tf


TERRAFORM
cd terraform
terraform apply --auto-approve

La pipeline s'execute toutes les 5 minutes par défaut 

Extract: Charge les données depuis l'API rest vers le bucket GCS (json)
Load: Transfert les données du bucket GCS (json) vers des tables bigquery
Transform: Effectue une transformation depuis ces tables bigquery vers une autre table BigQuery finale

LOCAL
EXTRACT
cd extract
uv venv
uv pip install python-dotenv google-cloud-storage
source .venv\Scripts\activate
gcloud auth application-default login

créer un fichier .env 
exemple de contenu:
'''
API_KEY="test"

API_URL="http://localhost:3000"
API_CUSTOMERS_URL="${API_URL}/customers"
API_PRODUCTS_URL="${API_URL}/products"
API_SALES_URL="${API_URL}/sales"

GCP_PROJECT_ID="stack-labs-data-engineer"
GCP_BUCKET_NAME="stack-labs-data-engineer-raw-data"
'''

uv run python main.py

LOAD
cd load
uv venv
uv pip install python-dotenv google-cloud-storage google-cloud-bigquery google-cloud-pubsub
uv run python main.py