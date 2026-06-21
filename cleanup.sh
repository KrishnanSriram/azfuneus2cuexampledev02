# ── Variables ─────────────────────────────────────────────────
export RG="rg-eus2-cuexample-dev-001"
export SA_NAME="saeus2cuexampledev01"
export LOCATION="eastus2"


echo "Delete Resource Group: $RG"
az group delete \
  --name $RG \
  --yes \
  --no-wait
echo "Resource Group deletion initiated. It may take a few minutes to complete."
echo "---"