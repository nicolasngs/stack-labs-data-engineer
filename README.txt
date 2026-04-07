Execution du fichier terraform:
cd terraform



Lancement de l'API:
npm install dotenv
npx json-server@0.17.4 api.json --middlewares ./middleware.js --port 3000

Execution des script d'injection:
uv venv
uv pip install python-dotenv google-cloud-storage
source .venv\Scripts\activate
gcloud auth application-default login

créer un fichier .env 
exemple de contenu: 
API_KEY="test"

API_URL="http://localhost:3000"
API_CUSTOMERS_URL="${API_URL}/customers"
API_PRODUCTS_URL="${API_URL}/products"
API_SALES_URL="${API_URL}/sales"

GCP_PROJECT_ID="stack-labs-data-engineer"
GCP_BUCKET_NAME="stack-labs-data-engineer-raw-data"


uv run python ingest_customers.py
uv run python ingest_products.py
uv run python ingest_sales.py