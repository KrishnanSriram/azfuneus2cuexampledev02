Excellent architecture choice — one UMI, two services, zero keys. Here's the full plan before we execute:
┌─────────────────────────────────────────────┐
│  User Assigned Managed Identity (UMI)        │
│  umi-eus2-cuexample-dev-01                  │
│                                             │
│  Roles:                                     │
│  - Storage Blob Data Reader (source)        │
│  - Storage Blob Data Contributor (dest)     │
│  - Cognitive Services User (CU resource)    │
└─────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────────┐
│  Azure Function │  │  Content            │
│  (no conn str)  │  │  Understanding      │
│  (no CU key)    │  │  (no API key)       │
└─────────────────┘  └─────────────────────┘
         │                    │
         └────────┬───────────┘
                  ▼
        ┌──────────────────┐
        │  Storage Account │
        │  source/dest     │
        └──────────────────┘
Execute in order:
Step 1 — Create the UMI
az identity create \
  --name umi-eus2-cuexample-dev-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --location eastus2
Capture the IDs we'll need:
UMI_ID=$(az identity show \
  --name umi-eus2-cuexample-dev-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --query id -o tsv)

UMI_PRINCIPAL_ID=$(az identity show \
  --name umi-eus2-cuexample-dev-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --query principalId -o tsv)

echo "UMI ID: $UMI_ID"
echo "Principal ID: $UMI_PRINCIPAL_ID"
Paste the output and we'll move to Step 2.

Step 2 — Assign Roles on Storage Account
bashSA_ID=$(az storage account show \
  --name saeus2cuexampledev01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --query id -o tsv)

# Read from source
az role assignment create \
  --assignee $UMI_PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope $SA_ID

# Write to destination
az role assignment create \
  --assignee $UMI_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $SA_ID

Step 3 — Assign UMI to CU Resource
az cognitiveservices account identity assign \
  --name my-foundry-cu-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --identities $UMI_ID
Also grant the UMI permission to call CU:
CU_ID=$(az cognitiveservices account show \
  --name my-foundry-cu-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --query id -o tsv)

az role assignment create \
  --assignee $UMI_PRINCIPAL_ID \
  --role "Cognitive Services User" \
  --scope $CU_ID

Step 4 — Assign UMI to Function App
az functionapp identity assign \
  --name azfuneus2cuexampledev01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --identities $UMI_ID
Tell the function which UMI to use:
UMI_CLIENT_ID=$(az identity show \
  --name umi-eus2-cuexample-dev-01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --query clientId -o tsv)

az functionapp config appsettings set \
  --name azfuneus2cuexampledev01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --settings "AZURE_CLIENT_ID=$UMI_CLIENT_ID"

Step 5 — Remove Old Key-Based Settings
az functionapp config appsettings delete \
  --name azfuneus2cuexampledev01 \
  --resource-group rg-eus2-cuexample-dev-01 \
  --setting-names "STORAGE_CONNECTION_STRING" "CU_KEY"

Step 6 — Update Function Code
pythonimport azure.functions as func
import logging
import os
import json
import time
import requests
from azure.identity import ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

@app.route(route="process_document", auth_level=func.AuthLevel.FUNCTION)
def process_document(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    storage_account  = os.environ["STORAGE_ACCOUNT_NAME"]
    source_container = os.environ["SOURCE_CONTAINER"]
    dest_container   = os.environ["DESTINATION_CONTAINER"]
    cu_endpoint      = os.environ["CU_ENDPOINT"].rstrip("/")
    analyzer_id      = os.environ["ANALYZER_ID"]
    client_id        = os.environ["AZURE_CLIENT_ID"]

    filename = req.params.get('filename')
    if not filename:
        try:
            filename = req.get_json().get('filename')
        except ValueError:
            pass

    if not filename:
        return func.HttpResponse(
            "Please pass 'filename' as a query param or in the request body.",
            status_code=400
        )

    try:
        # ── UMI credential — used for both storage and CU ─────────────────
        credential = ManagedIdentityCredential(client_id=client_id)

        # ── Step 1: Read file from source container ───────────────────────
        logging.info('Reading file from source container: %s', filename)
        blob_service = BlobServiceClient(
            account_url=f"https://{storage_account}.blob.core.windows.net",
            credential=credential
        )
        source_blob = blob_service.get_blob_client(container=source_container, blob=filename)
        file_bytes  = source_blob.download_blob().readall()
        logging.info('File downloaded. Size: %d bytes', len(file_bytes))

        # ── Step 2: Get token for CU using UMI ───────────────────────────
        logging.info('Acquiring token for Content Understanding')
        token = credential.get_token("https://cognitiveservices.azure.com/.default").token

        # ── Step 3: Submit binary to CU ───────────────────────────────────
        ext = os.path.splitext(filename)[1].lower()
        content_type_map = {
            ".pdf":  "application/pdf",
            ".png":  "image/png",
            ".jpg":  "image/jpeg",
            ".jpeg": "image/jpeg",
            ".tiff": "image/tiff",
            ".bmp":  "image/bmp",
        }
        content_type = content_type_map.get(ext, "application/octet-stream")

        submit_url = (
            f"{cu_endpoint}/contentunderstanding/analyzers"
            f"/{analyzer_id}:analyzeBinary"
            f"?api-version=2025-11-01"
        )
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": content_type,
        }
        logging.info('Submitting to CU analyzer: %s', analyzer_id)
        submit_resp = requests.post(submit_url, headers=headers, data=file_bytes, timeout=60)
        logging.info('CU submit response: %d', submit_resp.status_code)

        if submit_resp.status_code not in (200, 202):
            raise RuntimeError(f"CU submit failed: {submit_resp.status_code} — {submit_resp.text}")

        # ── Step 4: Poll for result ───────────────────────────────────────
        operation_url = submit_resp.headers.get("Operation-Location")
        if not operation_url:
            raise RuntimeError("No Operation-Location header returned from CU")

        logging.info('Polling: %s', operation_url)
        result = None

        for attempt in range(30):
            time.sleep(3)
            poll_resp = requests.get(
                operation_url,
                headers={"Authorization": f"Bearer {token}"},
                timeout=30
            )
            poll_resp.raise_for_status()
            poll_data = poll_resp.json()
            status = poll_data.get("status", "").lower()
            logging.info('Poll attempt %d: status=%s', attempt + 1, status)

            if status == "succeeded":
                result = poll_data
                break
            elif status in ("failed", "canceled"):
                raise RuntimeError(f"CU analysis {status}: {poll_data}")

        if not result:
            raise TimeoutError("Content Understanding did not complete within timeout")

        # ── Step 5: Write result to destination container ─────────────────
        logging.info('CU Result: %s', json.dumps(result, indent=2))
        output_filename = f"{os.path.splitext(filename)[0]}.json"
        dest_blob = blob_service.get_blob_client(container=dest_container, blob=output_filename)
        dest_blob.upload_blob(json.dumps(result, indent=2), overwrite=True)
        logging.info('Result written to %s/%s', dest_container, output_filename)

        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "input":  f"{source_container}/{filename}",
                "output": f"{dest_container}/{output_filename}"
            }),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logging.error('Error: %s', str(e))
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)

Update requirements.txt:
azure-functions
azure-storage-blob
azure-identity
requests

Deploy:
func azure functionapp publish azfuneus2cuexampledev01