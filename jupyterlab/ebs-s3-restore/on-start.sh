#!/bin/bash
set -e

# OVERVIEW
# This script downloads a snapshot specified by tags (BACKUP_DESTINATION_BUCKET, and TIMESTAMP) on the user profile into the space. 
# Note that this script is meant to be used if a space needs to be restored and its data is somehow lost. If you are copying over to a different space, update the SPACE_NAME value in this script to the source space name.
# The snapshot can be created from an existing space using https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/jupyterlab/ebs-backup-s3/on-start.sh.
# 
# Note that the execution is done with nohup to bypass the startup timeout set by SageMaker Notebook instance. Depending on the size of the source /home/sagemaker-user/, it may take more than 5 minutes. You would see a text file SYNC_COMPLETE created in /home/sagemaker-user/.restore to denote the completion. You need s3:GetObject, s3:PutObject, and s3:ListBucket for the S3 bucket in the execution role to perform aws s3 sync.
# 
# Note if your notebook instance is in VPC mode without a direct internet access, please create a S3 VPC Gateway endpoint (https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html) and a SageMaker API VPC interface endpoint (https://docs.aws.amazon.com/sagemaker/latest/dg/interface-vpc-endpoint.html).
#

mkdir -p .restore

cat << "EOF" > /home/sagemaker-user/.restore/restore.sh
#!/bin/bash
sudo apt-get install -y jq
# specify region
REGION=us-west-2
SPACE_NAME=$(cat /opt/ml/metadata/resource-metadata.json | jq -r '.SpaceName')
DOMAIN_ID=$(cat /opt/ml/metadata/resource-metadata.json | jq -r '.DomainId')
USER_PROFILE_NAME=$(aws sagemaker describe-space --domain-id=$DOMAIN_ID --space-name=$SPACE_NAME --region $REGION | jq -r '.OwnershipSettings.OwnerUserProfileName')
USER_PROFILE_ARN=$(aws sagemaker describe-user-profile --domain-id $DOMAIN_ID --user-profile-name $USER_PROFILE_NAME --region $REGION | jq -r '.UserProfileArn')

# replace the tag key if you are using a different key 
BUCKET=$(aws sagemaker list-tags --resource-arn $USER_PROFILE_ARN --region $REGION | jq -r '.Tags[] | select(.Key=="BACKUP_DESTINATION_BUCKET").Value')
TIMESTAMP=$(aws sagemaker list-tags --resource-arn $USER_PROFILE_ARN --region $REGION | jq -r '.Tags[] | select(.Key=="TIMESTAMP").Value')

# check if SNAPSHOT exists, if not, proceed without sync
echo "Checking if s3://${BUCKET}/${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP} exists..."
aws s3 ls s3://${BUCKET}/${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP} || (echo "Snapshot s3://${BUCKET}/${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP} does not exist. Proceed without the sync."; exit 0)
echo "Syncing s3://${BUCKET}/${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP} to /home/sagemaker-user/"
aws s3 sync s3://${BUCKET}/${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP} /home/sagemaker-user
exitcode=$?
echo $exitcode
if [ $exitcode -eq 0 ] || [ $exitcode -eq 2 ]
then
    TIMESTAMP=`date +%F-%H-%M-%S`
    echo "Completed at $TIMESTAMP" > /home/sagemaker-user/.restore/SYNC_COMPLETE
fi
EOF

chmod +x /home/sagemaker-user/.restore/restore.sh

# nohup to bypass the notebook instance timeout at start
nohup /home/sagemaker-user/.restore/restore.sh >> /home/sagemaker-user/.restore/nohup.out 2>&1 &
 