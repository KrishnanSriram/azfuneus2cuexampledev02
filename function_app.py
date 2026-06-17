import azure.functions as func
import datetime
import json
import logging
from azure.storage.blob import BlobServiceClient
import os

app = func.FunctionApp()

@app.route(route="process_document", auth_level=func.AuthLevel.FUNCTION)
def process_document(req: func.HttpRequest) -> func.HttpResponse:
  logging.info('Python HTTP trigger function processed a request.')
  STORAGE_CONNECTION_STRING = os.environ["STORAGE_CONNECTION_STRING"]
  SOURCE_CONTAINER = os.environ["SOURCE_CONTAINER"]

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
      blob_client = BlobServiceClient.from_connection_string(STORAGE_CONNECTION_STRING)
      logging.info('Connected to Blob Storage successfully.')
      container_client = blob_client.get_container_client(SOURCE_CONTAINER)
      logging.info('Container client created successfully.')
      blob = container_client.get_blob_client(filename)
      logging.info('Blob client created successfully for file: %s', filename)
      data = blob.download_blob().readall()
      logging.info('Blob downloaded successfully. Size: %d bytes', len(data))

      return func.HttpResponse(
          f"Successfully read '{filename}' from '{SOURCE_CONTAINER}'. Size: {len(data)} bytes.",
          status_code=200
      )

  except Exception as e:
      logging.error(f"Failed to read blob: {e}")
      return func.HttpResponse(f"Error: {str(e)}", status_code=500)
    # logging.info('Python HTTP trigger function processed a request.')

    # name = req.params.get('name')
    # if not name:
    #     try:
    #         req_body = req.get_json()
    #     except ValueError:
    #         pass
    #     else:
    #         name = req_body.get('name')

    # if name:
    #     return func.HttpResponse(f"Hello, {name}. This HTTP triggered function executed successfully.")
    # else:
    #     return func.HttpResponse(
    #          "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
    #          status_code=200
    #     )