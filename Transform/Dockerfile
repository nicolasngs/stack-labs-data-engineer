FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    git gcc curl && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir dbt-bigquery google-cloud-bigquery

COPY . ./

ENV DBT_PROFILES_DIR=/app/.dbt \
    PYTHONUNBUFFERED=1

CMD ["dbt", "run", "--profiles-dir", "/app/.dbt"]
