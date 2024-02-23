# SageMaker Code Editor Auto-Stop for Idle Instances

The `autostop.py` Python script, coupled with the `on-start.sh` shell script, is designed to automatically shut down idle SageMaker Code Editor applications after a configurable time of inactivity. This solution is intended to help manage costs by ensuring that resources are not left running when not in use.

## Installation for SageMaker Studio User Profiles

### Prerequisites

- AWS CLI configured with appropriate permissions
- Access to the SageMaker Studio domain where the user profiles are located

### Steps 

1. From a terminal appropriately configured with AWS CLI, run the following commands:

Note: If the repo is `private`, please add the following params (and contact `aws-spenceng` for the access token)
- `ACCESS_TOKEN=<your access token>`
- `ASSET_ID=<your asset ID>`

```
ASI_VERSION=0.1.0
# (private param) ACCESS_TOKEN=<your access token>
# (private param) ASSET_ID=<your asset ID>
curl -H "Authorization: Bearer $ACCESS_TOKEN" -H "Accept: application/octet-stream" -L "https://api.github.com/repos/aws-spenceng/sm-ce-auto-shut-down/releases/assets/$ASSET_ID" -o "sm-ce-auto-shut-down-$ASI_VERSION.tar.gz"
tar -xvzf sm-ce-auto-shut-down-$ASI_VERSION.tar.gz

cd sm-ce-auto-shut-down

REGION=<aws_region>
DOMAIN_ID=<domain_id>
ACCOUNT_ID=<aws_account_id>
LCC_NAME=code-editor-auto-shut-down
LCC_CONTENT=`openssl base64 -A -in on-start.sh`

aws sagemaker create-studio-lifecycle-config \
    --studio-lifecycle-config-name $LCC_NAME \
    --studio-lifecycle-config-content $LCC_CONTENT \
    --studio-lifecycle-config-app-type CodeEditor \
    --query 'StudioLifecycleConfigArn'

aws sagemaker update-domain \
    --region "$REGION" \
    --domain-id "$DOMAIN_ID" \
    --default-user-settings \
    '{
      "CodeEditorAppSettings": {
        "DefaultResourceSpec": {
          "LifecycleConfigArn": "arn:aws:sagemaker:'"$REGION"':'"$ACCOUNT_ID"':studio-lifecycle-config/'"$LCC_NAME"'",
          "InstanceType": "ml.t3.medium"
        },
        "LifecycleConfigArns": [
          "arn:aws:sagemaker:'"$REGION"':'"$ACCOUNT_ID"':studio-lifecycle-config/'"$LCC_NAME"'"
        ]
      }
    }'

```

2. After successful domain update, navigate to Code Editor, and select the LCC when starting your Code Editor application.