#!/bin/bash
# ─────────────────────────────────────────────────────────────
# bootstrap.sh
# Creates the Resource Group, Storage Account, and containers.
# Run this first before any other script.
# ─────────────────────────────────────────────────────────────

# ── Variables ─────────────────────────────────────────────────
export RG="rg-eus2-cuexample-dev-001"
export SA_NAME="saeus2cuexampledev01"
export LOCATION="eastus2"

# ── Step 1: Create Resource Group ─────────────────────────────
echo "Creating Resource Group: $RG"
az group create \
  --name $RG \
  --location $LOCATION

echo "Verifying Resource Group..."
az group show \
  --name $RG \
  --output table
echo "---"

# ── Step 2: Create Storage Account ────────────────────────────
echo "Creating Storage Account: $SA_NAME"
az storage account create \
  --name $SA_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --sku Standard_LRS

echo "---"

# ── Step 3: Create source and destination containers ──────────
echo "Creating source and destination containers"
CONN_STR=$(az storage account show-connection-string \
  --name $SA_NAME \
  --resource-group $RG \
  --query connectionString -o tsv)

az storage container create \
  --name source \
  --connection-string "$CONN_STR"

az storage container create \
  --name destination \
  --connection-string "$CONN_STR"

echo "---"

# ── Step 4: Upload test file ──────────────────────────────────
echo "Uploading invoice.pdf to source container"
az storage blob upload \
  --account-name $SA_NAME \
  --container-name source \
  --name invoice.pdf \
  --file ./../../invoice.pdf

echo "---"
echo "Bootstrap complete! Resource Group, Storage Account, and containers are ready."