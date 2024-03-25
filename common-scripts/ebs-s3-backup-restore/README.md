# SageMaker Studio EBS Backup and Recovery

SageMaker Studio uses Elastic Block Storage (EBS) for persistent storage of users' files. See the blog [Boost productivity on Amazon SageMaker Studio: Introducing JupyterLab Spaces and generative AI tools](https://aws.amazon.com/blogs/machine-learning/boost-productivity-on-amazon-sagemaker-studio-introducing-jupyterlab-spaces-and-generative-ai-tools/) for a detailed look at Studio architecture.

Since the EBS volume is managed by SageMaker, customers want a mechanism to backup and restore files from users' spaces in the event of a disaster, or any other scenarios such as recreating a space or user profile.

When set as a Lifecycle Configuration, the `on-start.sh` shell script backs up the user's file in the space home directory (`/home/sagemaker-user`) into an S3 location. The S3 bucket and prefix are specified by the administrator through the script, and the script saves the files under `s3://<bucket>/<prefix>/<user-profile-name>/<space-name>/<timestamp>`. The admin can also choose to run the S3 sync at regular intervals, the default provided is 12 hours. We recommend not going less than 6 hours on the time interval, so that notebook performance is not affected by the background sync.

When the administrator needs to restore the files, the user profile simply needs to be tagged with the timestamp. If there is a timestamp tag on the user, the script will restore the files from the timestamp, in addition to backing up files to S3. 
*Note: Admins should remove the timestamp tag from the user profile, after the LCC is run. Otherwise, the script will continue to restore from S3.*

## Installation for SageMaker Studio User Profiles

### Prerequisites

- AWS CLI configured with appropriate permissions
- Access to the SageMaker Studio domain where the user profiles are located

### Installation for all user profiles in a SageMaker Studio domain

From a terminal appropriately configured with AWS CLI, run the following commands (replace fields as needed):

```
REGION=<aws_region>
DOMAIN_ID=<domain_id>
ACCOUNT_ID=<aws_account_id>
LCC_NAME=ebs-s3-backup-restore
LCC_CONTENT=`openssl base64 -A -in on-start.sh`

# replace CodeEditor with JupyterLab if setting this LCC for JupyterLab apps
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

2. After successful domain update, navigate to your space, and select the LCC when starting your default application.


### Configurations

The `on-start.sh` script can be customized by modifying:

* `ENABLE_SCHEDULED_SYNC` - set to 1 to enable scheduled syncs to S3 . Default value is `1` (enabled).
* `SYNC_INTERVAL` - if scheduled sync is enabled, the time interval in hours for syncing files to S3. Default value is `12`.