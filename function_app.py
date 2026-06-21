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

    conn_str         = os.environ["STORAGE_CONNECTION_STRING"]
    source_container = os.environ["SOURCE_CONTAINER"]
    dest_container   = os.environ["DESTINATION_CONTAINER"]
    cu_endpoint      = os.environ["CU_ENDPOINT"].rstrip("/")
    cu_key           = os.environ["CU_KEY"]
    analyzer_id      = os.environ["ANALYZER_ID"]

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
        logging.info('Submitting binary to CU analyzer: %s', analyzer_id)
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