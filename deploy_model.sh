#!/bin/bash

set -e

# download model from Hugging Face
echo "Downloading bge-reranker-v2-m3 model from Hugging Face.."
MODEL_DIR="model_asset/model"
mkdir -p $MODEL_DIR
FILES=(
 "config.json"
 "model.safetensors"
 "sentencepiece.bpe.model"
 "special_tokens_map.json"
 "tokenizer.json"
 "tokenizer_config.json"
)
BASE_URL="https://huggingface.co/BAAI/bge-reranker-v2-m3/resolve/main"

for FILE in "${FILES[@]}"; do
  if [ ! -f "$MODEL_DIR/$FILE" ]; then
    curl -L -o "$MODEL_DIR/$FILE" "$BASE_URL/$FILE?download=true"
  else
    echo "- $FILE already exists - skipping download."
  fi
done

if [[ "$(uname)" == "Darwin" ]]; then
  azd env get-values | awk '{print "export " $0}' > azd_env
  source azd_env
  rm azd_env
else
  source <(azd env get-values)
fi

# <create_deployment>
echo "Deploying bge-reranker-v2-m3 model to Azure Machine Learning Workspace.."
if ! az account show > /dev/null 2>&1; then
  az login
else
  echo "Already logged in to Azure CLI."
fi
az account set --subscription $AZURE_SUBSCRIPTION_ID

object_id=$(az ad signed-in-user show --query id --output tsv)
storage_account=$(az storage account list --resource-group $AZURE_RESOURCE_GROUP_NAME --output table --query "[].name" -o tsv)
az role assignment create \
  --assignee $object_id \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$storage_account
az role assignment create \
  --assignee $object_id \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP_NAME/providers/Microsoft.Storage/storageAccounts/$storage_account

# try 2 minutes
max_retries=12
count=0

until az ml online-deployment create --name $AZURE_AML_DEPLOYMENT_NAME --endpoint $AZURE_AML_ENDPOINT_NAME -f model_asset/deployment.yml --all-traffic --resource-group $AZURE_RESOURCE_GROUP_NAME --workspace-name $AZURE_AML_WORKSPACE_NAME; do
  count=$((count+1))
  if [[ $count -ge $max_retries ]]; then
    echo "Max retries reached. Exiting."
    exit 1
  fi
  echo "Command failed. Retrying in 10 seconds... ($count/$max_retries)"
  sleep 10
done

echo "Deployment successful."
# </create_deployment>
