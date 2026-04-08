import subprocess
import sys
import logging
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
)
logger = logging.getLogger(__name__)

SCRIPTS_DIR = Path(__file__).parent
SCRIPTS = ['ingest_customers.py', 'ingest_products.py', 'ingest_sales.py']


def orchestrate(request=None):
    for script in SCRIPTS:
        script_path = SCRIPTS_DIR / script
        logger.info(f"Running {script}...")
        
        result = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(SCRIPTS_DIR)
        )
        
        if result.returncode != 0:
            logger.error(f"{script} failed with exit code {result.returncode}")
            return {"status": "error", "script": script}, 500
        
        logger.info(f"{script} completed successfully")
    
    logger.info("All ingestions completed successfully!")
    return {"status": "success", "message": "All ingestions completed"}, 200


if __name__ == "__main__":
    status_code = orchestrate()[1]
    sys.exit(0 if status_code == 200 else 1)
