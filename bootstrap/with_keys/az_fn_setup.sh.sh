#!/bin/bash
# ─────────────────────────────────────────────────────────────
# az_fn_setup.sh
# Creates the Azure Function App and configures all app settings.
# Run this after bootstrap.sh and cu_service_setup.sh.
#
# Before running this script, make sure these files exist
# in the same directory:
#   - function_app.py
#   - requirements.txt
#   - host.json
#   - local.settings.json
# ─────────────────────────────────────────────────────────────

# ── Variables ─────────────────────────────────────────────────
export RG="rg-eus2-cuexample-dev-001"
export SA_NAME="saeus2cuexampledev01"
export FN_NAME="azfuneus2cuexampledev01"
export CS_NAME="my-foundry-cu-01"
export LOCATION="eastus2"
export CU_ENDPOINT="https://myfoundrycu01.services.ai.azure.com"

# ── Step 1: Create Function App ───────────────────────────────
echo "Creating Azure Function App: $FN_NAME"
az functionapp create \
  --name $FN_NAME \
  --resource-group $RG \
  --storage-account $SA_NAME \
  --consumption-plan-location $LOCATION \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux

echo "$FN_NAME created."
echo "---"

# ── Step 2: Configure App Settings ───────────────────────────
echo "Configuring app settings for: $FN_NAME"

CONN_STR=$(az storage account show-connection-string \
  --name $SA_NAME \
  --resource-group $RG \
  --query connectionString -o tsv)

CU_KEY=$(az cognitiveservices account keys list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "key1" -o tsv)

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

echo "App settings configured. Verifying..."
az functionapp config appsettings list \
  --name $FN_NAME \
  --resource-group $RG \
  --output table
echo "---"

# ── Step 3: Deploy function code ──────────────────────────────
echo "Deploying function code to $FN_NAME"
echo "Checking required files are present..."
ls -l function_app.py requirements.txt host.json local.settings.json

func azure functionapp publish $FN_NAME

echo "---"
echo "Function App setup complete!"
echo "Test it with:"
echo "  curl \"https://$FN_NAME.azurewebsites.net/api/process_document?code=<key>&filename=invoice.pdf\""

wghB9rGsOl7nisPYtxesuqEZrGTz3AXy_eD5ffAURX1TAzFup7cExg==
curl \"https://$FN_NAME.azurewebsites.net/api/process_document?code=<key>&filename=invoice.pdf\"