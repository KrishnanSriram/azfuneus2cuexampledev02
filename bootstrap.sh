# set variables
RG=rg-eus2-cuexample-dev-01
SA_NAME=saeus2cuexampledev01
FN_NAME=azfuneus2cuexampledev01
CS_NAME=my-foundry-cu-02
LOCATION=eastus2

# Create RG
echo "Create RG - $RG"
az group create -name $RG - location $LOCATION
# verify if RG was created
echo "Successfully created $RG"
az group show - name $RG - output table
echo "-" * 80

# Create storage account
echo "Create new SA and containers for data - $SA_NAME"
az storage account create \
 - name $SA_NAME \
 - resource-group $RG \
 - location $LOCATION \
 - sku Standard_LRS
# Get the connection string for use in later steps
az storage account show-connection-string \
 - name $SA_NAME \
 - resource-group $RG \
 - query connectionString -o tsv
# Create source and destination containers
CONN_STR=$(az storage account show-connection-string \
 - name $SA_NAME \
 - resource-group $RG \
 - query connectionString -o tsv)
az storage container create - name source - connection-string "$CONN_STR"
az storage container create - name destination - connection-string "$CONN_STR"
# Upload a test file to source:
az storage blob upload \
 - account-name $SA_NAME \
 - container-name source \
 - name invoice.pdf \
 - file ./invoice.pdf
 echo "Create SA and a couple of containers, uploaded invoice.pdf into source container"
 echo "-" * 80