# set variables
RG=rg-eus2-cuexample-dev-01
SA_NAME=saeus2cuexampledev01
FN_NAME=azfuneus2cuexampledev01
CS_NAME=my-foundry-cu-02
LOCATION=eastus2
CU_ENDPOINT=https://$CS_NAME.services.ai.azure.com

echo "Create a new CS account - $CS_NAME in RG - $RG in location - $LOCATION"
az cognitiveservices account create \
 - name $CS_NAME \
 - resource-group $RG \
 - location $LOCATION \
 - kind AIServices \
 - sku S0 \
 - yes

echo "$CS_NAME created."

 # Deploy gpt-4.1
 echo "Deploy gpt4.1, gpt-4.1-mini and text-embedding-3-large model to $CS_NAME"
az cognitiveservices account deployment create \
 - name $CS_NAME \
 - resource-group $RG \
 - deployment-name gpt-4.1 \
 - model-name gpt-4.1 \
 - model-version "2025–04–14" \
 - model-format OpenAI \
 - sku-capacity 10 \
 - sku-name Standard

# Deploy gpt-4.1-mini
az cognitiveservices account deployment create \
 - name $CS_NAME \
 - resource-group $RG \
 - deployment-name gpt-4.1-mini \
 - model-name gpt-4.1-mini \
 - model-version "2025–04–14" \
 - model-format OpenAI \
 - sku-capacity 10 \
 - sku-name Standard

# Deploy text-embedding-3-large
az cognitiveservices account deployment create \
 - name $CS_NAME \
 - resource-group $RG \
 - deployment-name text-embedding-3-large \
 - model-name text-embedding-3-large \
 - model-version "1" \
 - model-format OpenAI \
 - sku-capacity 10 \
 - sku-name Standard
 echo "Successfully deployed all models"


CU_KEY=$(az cognitiveservices account keys list \
 - name $CS_NAME \
 - resource-group $RG \
 - query "key1" -o tsv)

 echo "Set default models - $CU_ENDPOINT using key - $CU_KEY"
 curl -X PATCH \
"$CU_ENDPOINT/contentunderstanding/defaults?api-version=2025–11–01" \
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