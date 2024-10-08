import os
import logging
import json

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer


def init():
    """
    This function is called when the container is initialized/started, typically after create/update of the deployment.
    You can write the logic here to perform init operations like caching the model in memory
    """
    global model
    global tokenizer
    # AZUREML_MODEL_DIR is an environment variable created during deployment.
    # It is the path to the model folder (./azureml-models/$MODEL_NAME/$VERSION)
    # Please provide your model's folder name if there is one
    #
    model_path = os.path.join(os.getenv("AZUREML_MODEL_DIR"), "model")
    tokenizer_path = os.path.join(
        os.getenv("AZUREML_MODEL_DIR"), "model", ".tokenizer"
    )
    
    # deserialize the model file back into a sklearn model
    tokenizer = AutoTokenizer.from_pretrained(tokenizer_path)
    model = AutoModelForSequenceClassification.from_pretrained(model_path)
    model.eval()
    logging.info("Init complete")


def run(raw_data):
    """
    This function is called for every invocation of the endpoint to perform the actual scoring/prediction.
    In the example we extract the data from the json input and call the scikit-learn model's predict()
    method and return the result back
    """
    logging.info("model 1: request received")

    pairs = json.loads(raw_data)["pairs"]
    with torch.no_grad():
        inputs = tokenizer(pairs, padding=True, truncation=True, return_tensors='pt', max_length=512)
        scores = model(**inputs, return_dict=True).logits.view(-1, ).float()

    logging.info("Request processed")
    return scores.tolist()
