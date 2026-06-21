#!/bin/bash
# ─────────────────────────────────────────────────────────────
# cu_service_setup.sh
# Creates the Azure AI Content Understanding service,
# deploys the required models, and configures default mappings.
# Run this after bootstrap.sh.
# ─────────────────────────────────────────────────────────────

# ── Variables ─────────────────────────────────────────────────
export RG="rg-eus2-cuexample-dev-001"
export CS_NAME="my-foundry-cu-01"
export LOCATION="eastus2"
export CU_ENDPOINT="https://$CS_NAME.services.ai.azure.com"

# ── Step 1: Create Content Understanding resource ─────────────
echo "Creating Content Understanding resource: $CS_NAME"
az cognitiveservices account create \
  --name $CS_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --kind AIServices \
  --sku S0 \
  --yes

echo "$CS_NAME created."
echo "---"

# ── Step 2: Deploy required models ───────────────────────────
# Note: All three models are required for prebuilt analyzers to work.

echo "Deploying gpt-4.1..."
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name gpt-4.1 \
  --model-name gpt-4.1 \
  --model-version "2025-04-14" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

echo "Deploying gpt-4.1-mini..."
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name gpt-4.1-mini \
  --model-name gpt-4.1-mini \
  --model-version "2025-04-14" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

echo "Deploying text-embedding-3-large..."
az cognitiveservices account deployment create \
  --name $CS_NAME \
  --resource-group $RG \
  --deployment-name text-embedding-3-large \
  --model-name text-embedding-3-large \
  --model-version "1" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

echo "All models deployed. Verifying..."
az cognitiveservices account deployment list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "[].{Name:name, Model:properties.model.name, Status:properties.provisioningState}" \
  --output table
echo "---"

# ── Step 3: Configure default model mappings ──────────────────
# This tells Content Understanding which deployment to use for each role.
# Without this step, prebuilt analyzers will fail with ResourceError.
echo "Waiting for DNS to propagate before configuring defaults..."
echo "Testing DNS resolution for $CS_NAME..."

MAX_ATTEMPTS=20
ATTEMPT=0
until nslookup $CS_NAME.services.ai.azure.com > /dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "DNS did not resolve after $MAX_ATTEMPTS attempts. Try running the PATCH command manually later."
    exit 1
  fi
  echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: Not resolved yet, waiting 30s..."
  sleep 30
done

echo "DNS resolved. Configuring default model mappings..."
CU_KEY=$(az cognitiveservices account keys list \
  --name $CS_NAME \
  --resource-group $RG \
  --query "key1" -o tsv)

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

echo ""
echo "---"
echo "Content Understanding setup complete!"