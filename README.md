## Semantic Ranking in Azure Database for PostgreSQL Flexible Server
Accuracy of the Information Retrieval pipeline plays a key role in the quality of the advanced Retrieval Augmented Generation (RAG) applications. Using Semantic Ranker Solution Accelerator you can extend Azure Database for PostgreSQL with a Semantic Ranker model and use it directly in Postgres SQL query to boost accuracy of the vector search results. Solution Accelerator provides automated deployment script to provision Semantic Ranker model as an Azure Machine Learning Inference Endpoint, and SQL UDF for Postgres to integrate ranker model into SQL queries. This Solution Accelerator requires [azure_ai](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/generative-ai-azure-overview) extension.

## About the Semantic Ranker Solution Accelerator Demonstration
In our Solution Accelerator demonstration, we leverage a subset of the CNN-DailyMail dataset, which features news articles authored by journalists. The demonstration process is structured as follows:
   1. Embedding and Indexing: We begin by embedding the articles and indexing the resulting vectors using the Hierarchical Navigable Small World (HNSW) algorithm. This step ensures efficient and scalable vector search capabilities.
   2. Query Processing: Upon receiving a query, we embed the query and retrieve the N closest vectors through a vector search. This allows us to identify the most relevant articles quickly.
   3. Semantic Reranking: The retrieved vectors are then passed to a semantic reranker model. This model reorders the vectors based on their semantic relevance and returns the top-K results, ensuring that the most pertinent articles are presented first.

## Before you start
* You need to have your own Azure subscription
* Install [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-linux)
* Install [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
* Install az ml extension using `az extension add --name ml`
* Ensure enough compute quota is available in the region you want to deploy the solution to. The required quota is 24 CPUs of Standard_NC24ads_A100_v4. ([view & manage quota](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-manage-quotas))

## Create the demonstration environment
In this demonstration you will use Bicep files to deploy the required resources. The steps below guides you to deploy the Azure services necessary for completing this demonstration into your Azure subscription.
1. Enter the following to clone the GitHub repo containing exercise resources:
    ```bash
    git clone https://github.com/microsoft/Semantic-Ranker-Solution-PostgreSQL.git
    cd Semantic-Ranker-Solution-PostgreSQL
    ```
2. Login to your Azure account
    ```bash
    azd auth login
    ```
3. Create a new azd environment
   ```bash
    azd env new
    ```
   Enter a name that will be used for the resource group. This will create a new folder in the .azure folder, and set it as the active environment for any calls to azd going forward.
4. Provision the resources
    ```bash
    azd up
    ```
    This will provision Azure resources and deploy this sample to those resources, including Azure Database for PostgreSQL Flexible Server, Azure OpenAI service, and Azure Machine Learning Workspace.

5. Deploy reranker model
   ```bash
   bash deploy_model.sh
   ```
   This will download reranker model from Hugging Face and deploy it to Azure Machine Learning Workspace.

## Semantic Reranking in Azure Database for PostgreSQL Flexible Server
6. Connect to database by providing database host, username, and database name.
    ```bash
    # load environment variables from azd environment
    source <(azd env get-values)
    # connect to PostgreSQL
    psql --host=$AZURE_POSTGRES_HOST --port=5432 --username=$AZURE_POSTGRES_USERNAME --dbname=$AZURE_POSTGRES_DB_NAME
    ```

    If the above command fails, try the following command:
    ```bash
    azd env get-values | awk '{print "export " $0}' > azd_env
    source azd_env
    psql --host=$AZURE_POSTGRES_HOST --port=5432 --username=$AZURE_POSTGRES_USERNAME --dbname=$AZURE_POSTGRES_DB_NAME
    ```

7. Create and setup necessary extensions
    ```sql
    \i setup_azure_ai.sql
    ```
   You will be prompted to enter OpenAI endpoint and subscription key and Azure Machine Learning scoring endpoint and key for the deployed embedding model and reranker model, respectively.
   >
   > You can find the endpoint and the keys for your Azure OpenAI resource under Resource Management
   > Keys and Endpoints in the the Azure OpenAI resource. Similarly, in the Azure Machine Learning studio, under Endpoints
   > Pick your endpoint
   > Consume you can find the endpoint URI and Key for the online endpoint.

9. Execute demo
    ```sql
    \i semantic_reranker_demo.sql
    ```
    After vector retrieval and reranking, it returns the top 3 articles along with their relevance scores for the given query, "Latest news on artificial intelligence"
