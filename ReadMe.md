# Azure Content Understanding — Azure Function End-to-End Setup

This guide walks through everything needed to build an Azure Function that reads a file from Blob Storage, processes it with Azure AI Content Understanding, and writes the result as JSON to a destination container.

---

## Architecture

```
HTTP Request (?filename=invoice.pdf)
        │
        ▼
┌──────────────────────────────┐
│  $FN_NAME     │  Azure Function (HTTP Trigger)
│  Python 3.11, Consumption    │
└──────────────────────────────┘
        │                          │
        ▼                          ▼
┌──────────────────┐    ┌──────────────────────────┐
│  source          │    │  $CS_NAME         │
│  (Blob Storage)  │───▶│  Content Understanding    │
│  invoice.pdf     │    │  prebuilt-documentSearch  │
└──────────────────┘    └──────────────────────────┘
                                   │
                                   ▼
                        ┌──────────────────┐
                        │  destination     │
                        │  invoice.json    │
                        └──────────────────┘
```

## Resource Summary

| Resource              | Name              |
| --------------------- | ----------------- |
| Subscription          | apps-eus2-dev-001 |
| Resource Group        | $RG               |
| Storage Account       | $SA_NAME          |
| Source Container      | source            |
| Destination Container | destination       |
| Azure Function App    | $FN_NAME          |
| Content Understanding | $CS_NAME          |
| Location              | East US 2         |

---

## Prerequisites

- Azure CLI installed and logged in (`az login`)
- Azure Functions Core Tools v4 installed (`npm install -g azure-functions-core-tools@4`)
- Python 3.11 installed locally
- Active Azure subscription

---

## Step 0 - Set variables

RG=rg-eus2-cuexample-dev-01
SA_NAME=saeus2cuexampledev01
FN_NAME=azfuneus2cuexampledev01
CS_NAME=my-foundry-cu-02
LOCATION=eastus2

## Step 1 — Create Resource Group

```bash
az group create \
  --name $RG \
  --location $LOCATION
```

Verify:

```bash
az group show \
  --name $RG \
  --output table
```

---

## Step 2 — Create Storage Account and Containers

```bash
# Create storage account
az storage account create \
  --name $SA_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS
```

Get the connection string for use in later steps:

```bash
az storage account show-connection-string \
  --name $SA_NAME \
  --resource-group $RG \
  --query connectionString -o tsv
```

Create source and destination containers:

```bash
CONN_STR=$(az storage account show-connection-string \
  --name $SA_NAME \
  --resource-group $RG \
  --query connectionString -o tsv)

az storage container create --name source --connection-string "$CONN_STR"
az storage container create --name destination --connection-string "$CONN_STR"
```

Upload a test file to source:

```bash
az storage blob upload \
  --account-name $SA_NAME \
  --container-name source \
  --name invoice.pdf \
  --file ./invoice.pdf
```

---

## Step 4 — Create Content Understanding Resource

Create the AI Services resource in East US 2. Content Understanding preview API requires this region and the `AIServices` kind:

```bash
az cognitiveservices account create \
  --name $CS_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --kind AIServices \
  --sku S0 \
  --yes
```

---

## Step 5 — Deploy Model Deployments on CU Resource

Three models are required: `gpt-4.1`, `gpt-4.1-mini`, and `text-embedding-3-large`.

```bash
# Deploy gpt-4.1
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name gpt-4.1 \
  --model-name gpt-4.1 \
  --model-version "2025-04-14" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

# Deploy gpt-4.1-mini
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name gpt-4.1-mini \
  --model-name gpt-4.1-mini \
  --model-version "2025-04-14" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

# Deploy text-embedding-3-large
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name text-embedding-3-large \
  --model-name text-embedding-3-large \
  --model-version "1" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard
```

Verify all three are deployed:

```bash
az cognitiveservices account deployment list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "[].{Name:name, Model:properties.model.name, Status:properties.provisioningState}" \
  --output table
```

Expected output:

```
Name                    Model                   Status
----------------------  ----------------------  ---------
gpt-4.1                 gpt-4.1                 Succeeded
text-embedding-3-large  text-embedding-3-large  Succeeded
gpt-4.1-mini            gpt-4.1-mini            Succeeded
```

---

## Step 6 — Configure Content Understanding Default Model Deployments

This maps the CU analyzer roles to the deployed models. Without this step analyzers will fail with `ResourceError`.

```bash
# Get CU key
CU_KEY=$(az cognitiveservices account keys list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "key1" -o tsv)

Note: If you using API key you can use both Foundry as well as AIService URLs. Eg: 
* Foundry - my-foundry-cu-001.services.ai.azure.com - custom subdomain, unique to your resource, only created in DNS when Azure provisions it
* AI Service - eastus2.api.cognitive.microsoft.com - regional endpoint, shared across all customers, always exists in DNS
For Managed Identity way of working you will need Foundry custom subdomain to work. The custom subdomain DNS entry takes time to propagate. It's a per-resource DNS record that Azure has to create and push out globally after provisioning.

# Set defaults
curl -X PATCH \
  "$CU_ENDPOINT/contentunderstanding/defaults?api-version=2025-11-01" \
  -H "Ocp-Apim-Subscription-Key: $CU_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "modelDeployments": {
      "gpt-4.1": "gpt-4.1",
      "text-embedding-3-large": "text-embedding-3-large",
      "prebuilt-analyzer-completion": "gpt-4.1",
      "prebuilt-analyzer-embedding": "text-embedding-3-large",
      "gpt-4.1-mini": "gpt-4.1-mini",
      "prebuilt-analyzer-completion-mini": "gpt-4.1-mini"
    }
  }'
```

Expected response:

```json
{
  "modelDeployments": {
    "completion": "gpt-4.1",
    "embedding": "text-embedding-3-large",
    "smallCompletion": "gpt-4.1-mini",
    "gpt-4.1": "gpt-4.1",
    "text-embedding-3-large": "text-embedding-3-large",
    "prebuilt-analyzer-completion": "gpt-4.1",
    "prebuilt-analyzer-embedding": "text-embedding-3-large",
    "gpt-4.1-mini": "gpt-4.1-mini",
    "prebuilt-analyzer-completion-mini": "gpt-4.1-mini"
  }
}
```

If you miss setup of defaults, you'll see this following error

```
Error: CU analysis failed: {'id': 'c57522ec-ccea-45cc-b950-996b691936a5', 'status': 'Failed', 'error': {'code': 'InvalidRequest', 'message': 'Invalid Request.', 'innererror': {'code': 'ResourceError', 'message': "This analyzer needs a 'completion' model deployment for current request, but none was resolved. Either 'models.completion' is not set on the analyzer, or the deployment it references is not registered for this resource. Configure it via 'PATCH /contentunderstanding/defaults'."}}, 'result': {'analyzerId': 'prebuilt-documentSearch', 'apiVersion': '2025-11-01', 'createdAt': '2026-06-17T12:21:22Z', 'warnings': [], 'contents': []}}
```

---

## Step 3 — Create Azure Function App

```bash
az functionapp create \
  --name $FN_NAME \
  --resource-group $RG \
  --storage-account $SA_NAME \
  --consumption-plan-location $LOCATION \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux
```

---

## Step 7 — Configure Function App Settings

Pull values directly from Azure to avoid manual copy-paste:

```bash
# Storage connection string
CONN_STR=$(az storage account show-connection-string \
  --name $SA_NAME \
  --resource-group $RG \
  --query connectionString -o tsv)

# CU endpoint and key
CU_ENDPOINT=$(az cognitiveservices account show \
  --name $CS_NAME \
  --resource-group $RG \
  --query "properties.endpoint" -o tsv)

CU_KEY=$(az cognitiveservices account keys list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "key1" -o tsv)

# Set all app settings
az functionapp config appsettings set \
  --name $FN_NAME \
  --resource-group $RG \
  --settings \
    "STORAGE_CONNECTION_STRING=$CONN_STR" \
    "STORAGE_ACCOUNT_NAME=$SA_NAME" \
    "SOURCE_CONTAINER=source" \
    "DESTINATION_CONTAINER=destination" \
    "CU_ENDPOINT=$CU_ENDPOINT" \
    "CU_KEY=$CU_KEY" \
    "ANALYZER_ID=prebuilt-documentSearch"
```

> **Note:** The CU endpoint must use the `services.ai.azure.com` format, not `cognitiveservices.azure.com`. Content Understanding preview API is not supported on the older endpoint format.

Verify all settings are in place:

```bash
az functionapp config appsettings list \
  --name $FN_NAME \
  --resource-group $RG \
  --output table
```

---

## Step 8 — Function App Code

### Project Structure

```
cu-function/
├── function_app.py
├── host.json
├── local.settings.json
└── requirements.txt
```

Initialize the project:

```bash
mkdir cu-function && cd cu-function
func init --worker-runtime python --model V2
func new --name process_document --template "HTTP trigger" --authlevel "function"
```

### `requirements.txt`

```
azure-functions
azure-storage-blob
requests
```

### `local.settings.json` (local development only, never commit)

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "STORAGE_CONNECTION_STRING": "<your-connection-string>",
    "STORAGE_ACCOUNT_NAME": "$SA_NAME",
    "SOURCE_CONTAINER": "source",
    "DESTINATION_CONTAINER": "destination",
    "CU_ENDPOINT": "https://$CS_NAME.services.ai.azure.com",
    "CU_KEY": "<your-cu-key>",
    "ANALYZER_ID": "prebuilt-documentSearch"
  }
}
```

### `function_app.py`

```python
import azure.functions as func
import logging
import os
import json
import time
import requests
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

@app.route(route="process_document", auth_level=func.AuthLevel.FUNCTION)
def process_document(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')

    # Load env variables
    conn_str         = os.environ["STORAGE_CONNECTION_STRING"]
    source_container = os.environ["SOURCE_CONTAINER"]
    dest_container   = os.environ["DESTINATION_CONTAINER"]
    cu_endpoint      = os.environ["CU_ENDPOINT"].rstrip("/")
    cu_key           = os.environ["CU_KEY"]
    analyzer_id      = os.environ["ANALYZER_ID"]

    # Get filename from request
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
        # ── Step 1: Read file bytes from source container ─────────────────
        logging.info('Reading file from source container: %s', filename)
        blob_service = BlobServiceClient.from_connection_string(conn_str)
        source_blob  = blob_service.get_blob_client(container=source_container, blob=filename)
        file_bytes   = source_blob.download_blob().readall()
        logging.info('File downloaded successfully. Size: %d bytes', len(file_bytes))

        # ── Step 2: Detect content type ───────────────────────────────────
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
        logging.info('Detected content type: %s', content_type)

        # ── Step 3: Send binary directly to CU ───────────────────────────
        # Using analyzeBinary so file bytes are sent directly.
        # This avoids SAS URLs or public blob access — the function acts
        # as the secure bridge between storage and CU.
        logging.info('Submitting binary to Content Understanding analyzer: %s', analyzer_id)
        submit_url = (
            f"{cu_endpoint}/contentunderstanding/analyzers"
            f"/{analyzer_id}:analyzeBinary"
            f"?api-version=2025-11-01"
        )
        headers = {
            "Ocp-Apim-Subscription-Key": cu_key,
            "Content-Type": content_type,
        }
        submit_resp = requests.post(submit_url, headers=headers, data=file_bytes, timeout=60)
        logging.info('CU submit response: %d', submit_resp.status_code)

        if submit_resp.status_code not in (200, 202):
            raise RuntimeError(f"CU submit failed: {submit_resp.status_code} — {submit_resp.text}")

        # ── Step 4: Poll for result ───────────────────────────────────────
        operation_url = submit_resp.headers.get("Operation-Location")
        if not operation_url:
            raise RuntimeError("No Operation-Location header returned from CU")

        logging.info('Polling operation: %s', operation_url)
        poll_headers = {"Ocp-Apim-Subscription-Key": cu_key}
        result = None

        for attempt in range(30):
            time.sleep(3)
            poll_resp = requests.get(operation_url, headers=poll_headers, timeout=30)
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

        # ── Step 5: Log and write result to destination ───────────────────
        logging.info('CU Result: %s', json.dumps(result, indent=2))

        output_filename = f"{os.path.splitext(filename)[0]}.json"
        dest_blob = blob_service.get_blob_client(container=dest_container, blob=output_filename)
        dest_blob.upload_blob(
            json.dumps(result, indent=2),
            overwrite=True
        )
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
```

---

## Step 9 — Deploy the Function

```bash
func azure functionapp publish $FN_NAME
```

At the end of the output you should see:

```
Functions in $FN_NAME:
    process_document - [httpTrigger]
        Invoke url: https://$FN_NAME.azurewebsites.net/api/process_document
```

---

## Step 10 — Test

Get the function key:

```bash
az functionapp function keys list \
  --name $FN_NAME \
  --resource-group $RG \
  --function-name process_document \
  --query "default" -o tsv
```

Open a log stream in one terminal:

```bash
func azure functionapp logstream $FN_NAME
```

Trigger the function in another terminal:

```bash
FN_KEY=redacted
curl "https://$FN_NAME.azurewebsites.net/api/process_document?code=$FN_KEY&filename=invoice.pdf"
```

Expected response:

```json
{
  "status": "success",
  "input": "source/invoice.pdf",
  "output": "destination/invoice.json"
}
```

Verify the output file in the destination container:

```bash
az storage blob download \
  --account-name $SA_NAME \
  --container-name destination \
  --name invoice.json \
  --file invoice_result.json

cat invoice_result.json
```

---

## Switching Analyzers

Change `ANALYZER_ID` in App Settings to use a different built-in analyzer — no code change needed:

```bash
az functionapp config appsettings set \
  --name $FN_NAME \
  --resource-group $RG \
  --settings "ANALYZER_ID=prebuilt-invoice"
```

| Analyzer ID               | Use Case                             |
| ------------------------- | ------------------------------------ |
| `prebuilt-documentSearch` | General document → markdown + fields |
| `prebuilt-invoice`        | Invoice extraction                   |
| `prebuilt-layout`         | Layout and table detection           |
| `prebuilt-read`           | OCR / text extraction only           |
| `prebuilt-businessCard`   | Business card extraction             |

---

## Key Lessons Learned

**CU endpoint format matters** — use `https://<name>.services.ai.azure.com`, not `https://<name>.cognitiveservices.azure.com`. The older format returns `Preview API is not supported in this region`.

**Model defaults must be configured** — even with models deployed, CU analyzers will fail with `ResourceError` until you run the `PATCH /contentunderstanding/defaults` call to map the deployment names to analyzer roles.

**Use `analyzeBinary` not URL-based analyze** — in enterprise environments, blob storage is private and SAS URLs are often prohibited. Sending raw bytes from the function is the correct pattern. The function acts as the secure bridge. Note the 4MB HTTP payload limit on Consumption plan.

**All env variables must be read inside the function body** — reading `os.environ["X"]` at module level causes the entire worker to crash at startup if the setting is missing, resulting in a 1ms failure with no useful error message.

**`requirements.txt` must be correct before first deploy** — if a package is missing the function will deploy successfully but no functions will be registered, showing an empty list after `func azure functionapp publish`.

**API version** — use `2025-11-01`. Earlier versions such as `2024-12-01-preview` return 404 on some endpoints.

**\*Purge CS**
To purge a Cognitive service execute this command

```
az cognitiveservices account purge \
  --name $CS_NAME \
  --resource-group $RG \
  --location $LOCATION

```
