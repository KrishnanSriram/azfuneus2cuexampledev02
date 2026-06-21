
RG=rg-eus2-cuexample-dev-01
SA_NAME=saeus2cuexampledev01
FN_NAME=azfuneus2cuexampledev01
CS_NAME=my-foundry-cu-02
LOCATION=eastus2
CU_ENDPOINT=https://$CS_NAME.services.ai.azure.com

CU_KEY=$(az cognitiveservices account keys list \
 - name $CS_NAME \
 - resource-group $RG \
 - query "key1" -o tsv)

echo "Cretae a new Azure function - $FN_NAME"
az functionapp create \
 - name $FN_NAME \
 - resource-group $RG \
 - storage-account $SA_NAME \
 - consumption-plan-location $LOCATION \
 - runtime python \
 - runtime-version 3.11 \
 - functions-version 4 \
 - os-type Linux
 echo "$FN_NAME created successfully!"

 echo "Configure all App settings for function"
 # Storage connection string
CONN_STR=$(az storage account show-connection-string \
 - name $SA_NAME \
 - resource-group $RG \
 - query connectionString -o tsv)
# CU endpoint and key
#CU_ENDPOINT=$(az cognitiveservices account show \
# - name $CS_NAME \
# - resource-group $RG \
# - query "properties.endpoint" -o tsv)
CU_KEY=$(az cognitiveservices account keys list \
 - name $CS_NAME \
 - resource-group $RG \
 - query "key1" -o tsv)
# Set all app settings
az functionapp config appsettings set \
 - name $FN_NAME \
 - resource-group $RG \
 - settings \
"STORAGE_CONNECTION_STRING=$CONN_STR" \
"STORAGE_ACCOUNT_NAME=$SA_NAME" \
"SOURCE_CONTAINER=source" \
"DESTINATION_CONTAINER=destination" \
"CU_ENDPOINT=$CU_ENDPOINT" \
"CU_KEY=$CU_KEY" \
"ANALYZER_ID=prebuilt-documentSearch"


echo "Create a function app and publish it"
func init - worker-runtime python - model V2
func new - name process_document - template "HTTP trigger" - authlevel "function"
echo "Ensure you have these files in the location of exection - "