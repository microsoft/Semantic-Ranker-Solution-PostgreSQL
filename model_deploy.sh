set -e

export ENDPOINT_NAME=endpt-moe-123
export DEPLOYMENT_NAME=mydeployment

# <create_endpoint>
#az ml online-endpoint create --name $ENDPOINT_NAME -f demo_asset/endpoint.yml --resource-group rg-genai-experiments --workspace-name myamlws
# </create_endpoint>

# <create_deployment>
#az ml online-deployment create --name $DEPLOYMENT_NAME --endpoint $ENDPOINT_NAME -f demo_asset/deployment.yml --all-traffic --resource-group rg-genai-experiments --workspace-name myamlws
# </create_deployment>

# <get_status>
az ml online-endpoint show -n $ENDPOINT_NAME --resource-group rg-genai-experiments --workspace-name myamlws
# </get_status>

# check if create was successful
endpoint_status=`az ml online-endpoint show --name $ENDPOINT_NAME --query "provisioning_state" -o tsv --resource-group rg-genai-experiments --workspace-name myamlws`
if [[ $endpoint_status == "Succeeded"* ]]
then
  echo "Endpoint created successfully"
else
  echo "Endpoint creation failed"
  exit 1
fi

deploy_status=`az ml online-deployment show --name $DEPLOYMENT_NAME --endpoint $ENDPOINT_NAME --query "provisioning_state" -o tsv --resource-group rg-genai-experiments --workspace-name myamlws`
if [[ $deploy_status == "Succeeded"* ]]
then
  echo "Deployment completed successfully"
else
  echo "Deployment failed"
  exit 1
fi

# <test_endpoint>
az ml online-endpoint invoke --name $ENDPOINT_NAME --request-file demo_asset/sample_request.json --resource-group rg-genai-experiments --workspace-name myamlws
# </test_endpoint>

# supress printing endpoint key
set +x

# <test_endpoint_using_curl_get_key>
ENDPOINT_KEY=$(az ml online-endpoint get-credentials -n $ENDPOINT_NAME -o tsv --query primaryKey --resource-group rg-genai-experiments --workspace-name myamlws)
# </test_endpoint_using_curl_get_key>

set -x

