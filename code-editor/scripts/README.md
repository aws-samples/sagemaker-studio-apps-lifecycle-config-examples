# SageMaker Code Editor Auto-Stop for Idle Instances

The `autostop.py` Python script, coupled with the `on-start.sh` shell script, is designed to automatically shut down idle SageMaker Code Editor applications after a configurable time of inactivity. This solution is intended to help manage costs by ensuring that resources are not left running when not in use.

## Installation for SageMaker Studio User Profiles

### Prerequisites

- AWS CLI configured with appropriate permissions
- Access to the SageMaker Studio domain where the user profiles are located

### Installation for all user profiles in a SageMaker Studio domain

From a terminal appropriately configured with AWS CLI, run the following commands (replace fields as needed):

```
ASI_VERSION=0.3.0

curl -LO https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/code-editor-start-$ASI_VERSION.tar.gz
tar -xvzf code-editor-start-$ASI_VERSION.tar.gz

cd auto_shut_down

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


### Definition of idleness

The current implementation of idleness (as of `v0.3.0`) includes the following criteria:

1. There are no file changes made in the Code Editor application for a time period greater than `IDLE_TIME`. File changes include adding new files, deleting files, and/or updating files.


### Configurations

The `on-start.sh` script can be customized by modifying:

* `IDLE_TIME` the time in seconds that the application is in "idle" state before being shut down. Default: `3600` seconds
* `ASI_VERSION` the version of the Auto Shut Down solution. Please note that Code Editor starts at `v0.3.0`.


### Acknowledgement

A special acknowledgement to Lavaraja Padala for his foundational work on Lifecycle Configuration (LCC) implementation. This extension is inspired by his insights shared in the blog post ["How to Configure Lifecycle Configuration for New Studio Code Editor"](https://guide.aws.dev/articles/ARyr07cC46Rj6n-RU20dk3mQ/how-to-configure-lifecycle-configuration-for-new-studio-code-editor). We're grateful for his contribution to the community!