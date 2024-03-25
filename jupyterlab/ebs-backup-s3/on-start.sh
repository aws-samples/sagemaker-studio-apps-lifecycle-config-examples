#!/bin/bash
set -e

# OVERVIEW
# This script creates a snapshot of the current space's EBS volume /home/sagemaker-user/ to a S3 bucket specified by tag on the user profile.
#
# The snapshot can be download into a new instance using https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/jupyterlab/ebs-s3-restore/on-start.sh
# 
# Note that the execution is done with nohup to bypass the startup timeout set by SageMaker Notebook instance. Depending on the size of the source /home/sagemaker-user/, it may take more than 5 minutes. You would see a text file BACKUP_COMPLETE created in /home/sagemaker-user/.backup and in the S3 bucket to denote the completion. You need s3:CreateBucket, s3:GetObject, s3:PutObject, and s3:ListBucket in the execution role to perform aws s3 sync.
#
# Note if your notebook instance is in VPC mode without a direct internet access, please create a S3 VPC Gateway endpoint (https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html) and a SageMaker API VPC interface endpoint (https://docs.aws.amazon.com/sagemaker/latest/dg/interface-vpc-endpoint.html).
#

mkdir -p .backup

cat << "EOF" > /home/sagemaker-user/.backup/backup.sh
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

# check if bucket exists
# if not, create a bucket
echo "Checking if s3://${BUCKET} exists..."
aws s3api wait bucket-exists --bucket $BUCKET --region $REGION || (echo "s3://${BUCKET} does not exist, creating..."; aws s3 mb --region $REGION s3://${BUCKET})
TIMESTAMP=`date +%F-%H-%M-%S`
SNAPSHOT=${USER_PROFILE_NAME}/${SPACE_NAME}/${TIMESTAMP}
echo "Backup up /home/sagemaker-user to s3://${BUCKET}/${SNAPSHOT}/"
aws s3 sync --region $REGION --exclude "*/lost+found/*" /home/sagemaker-user s3://${BUCKET}/${SNAPSHOT}/
exitcode=$?
echo $exitcode
if [ $exitcode -eq 0 ] || [ $exitcode -eq 2 ]
then
    TIMESTAMP=`date +%F-%H-%M-%S`
    echo "Created s3://${BUCKET}/${SNAPSHOT}/" > /home/sagemaker-user/.backup/BACKUP_COMPLETE
    echo "Completed at $TIMESTAMP" >> /home/sagemaker-user/.backup/BACKUP_COMPLETE
    aws s3 cp /home/sagemaker-user/.backup/BACKUP_COMPLETE s3://${BUCKET}/${SNAPSHOT}/BACKUP_COMPLETE
fi
EOF

chmod +x /home/sagemaker-user/.backup/backup.sh

# nohup to bypass the notebook instance timeout at start
nohup /home/sagemaker-user/.backup/backup.sh >>  /home/sagemaker-user/.backup/nohup.out 2>&1 & 