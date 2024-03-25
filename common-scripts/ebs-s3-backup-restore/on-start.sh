# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#!/bin/bash
set -eux

# User variables [update as needed]
export SM_BCK_BUCKET=studio-backup-bucket
export SM_BCK_PREFIX=studio-backups
ENABLE_SCHEDULED_SYNC=1 # If set to 1, the user home directory will be synched with Amazon S3 every SYNC_INTERVAL_IN_HOURS
SYNC_INTERVAL_IN_HOURS=12 # Determines how frequently synch the user home directory on Amazon S3

# System variables [do not change if not needed]
export SM_BCK_HOME=$HOME
LOG_FILE=/var/log/apps/app_container.log # Writing to app_container.log delivers logs to CW logs

if [ $ENABLE_SCHEDULED_SYNC -eq 1 ]
then
    echo "[EBS backup LCC] - Scheduled sync is enabled. Installing cron."

    # Installing cron
    sudo apt-get update -y
    sudo sh -c 'printf "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d'
    sudo apt-get install -y cron
fi

# Installing jq
sudo apt-get install -y jq

export SM_BCK_SPACE_NAME=$(cat /opt/ml/metadata/resource-metadata.json | jq -r '.SpaceName')
export SM_BCK_DOMAIN_ID=$(cat /opt/ml/metadata/resource-metadata.json | jq -r '.DomainId')
export SM_BCK_USER_PROFILE_NAME=$(aws sagemaker describe-space --domain-id=$SM_BCK_DOMAIN_ID --space-name=$SM_BCK_SPACE_NAME | jq -r '.OwnershipSettings.OwnerUserProfileName')
USER_PROFILE_ARN=$(aws sagemaker describe-user-profile --domain-id $SM_BCK_DOMAIN_ID --user-profile-name $SM_BCK_USER_PROFILE_NAME | jq -r '.UserProfileArn')
RESTORE_TIMESTAMP=$(aws sagemaker list-tags --resource-arn $USER_PROFILE_ARN| jq -r '.Tags[] | select(.Key=="SM_EBS_RESTORE_TIMESTAMP").Value')

# Creating backup script (if needed)
if ! [ -f $HOME/.backup/backup.sh ]; then
    echo "[EBS backup LCC] - Creating backup script."
    mkdir -p $HOME/.backup

    cat << "EOF" > $HOME/.backup/backup.tp
#!/bin/bash

BACKUP_TIMESTAMP=`date +%F-%H-%M-%S`
SNAPSHOT=${SM_BCK_USER_PROFILE_NAME}/${SM_BCK_SPACE_NAME}/${BACKUP_TIMESTAMP}
echo "[EBS backup LCC] - Backup up $SM_BCK_HOME to s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT}/"

# sync to S3 and skip files if they have been restored to avoid redundant copies and exclude hidden files
aws s3 sync --exclude "*/lost+found/*" --exclude "restored-files/*" --exclude ".*/*" $SM_BCK_HOME s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT}/ 

exitcode=$?
echo "[EBS backup LCC] - S3 sync result (backup): "
echo $exitcode

if [ $exitcode -eq 0 ] || [ $exitcode -eq 2 ]
then
    echo "[EBS backup LCC] - Created s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT}/" >> $SM_BCK_HOME/.backup/${BACKUP_TIMESTAMP}_BACKUP_COMPLETE
    CURRENT_TIMESTAMP=`date +%F-%H-%M-%S`
    echo "[EBS backup LCC] - Backup completed at $CURRENT_TIMESTAMP" >> $SM_BCK_HOME/.backup/${BACKUP_TIMESTAMP}_BACKUP_COMPLETE
    aws s3 cp $SM_BCK_HOME/.backup/${BACKUP_TIMESTAMP}_BACKUP_COMPLETE s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT}/${BACKUP_TIMESTAMP}_BACKUP_COMPLETE
fi
EOF
envsubst "$(printf '${%s} ' ${!SM_BCK_*})" < $HOME/.backup/backup.tp > $HOME/.backup/backup.sh

chmod +x $HOME/.backup/backup.sh
fi

# Creating restore script (if needed)
if ! [ -f $HOME/.restore/restore.sh ]; then
    echo "[EBS backup LCC] - Creating restore script."
    mkdir -p $HOME/.restore

    cat << "EOF" > $HOME/.restore/restore.tp
#!/bin/bash

RESTORE_TIMESTAMP_ARG=$1
SNAPSHOT=${SM_BCK_USER_PROFILE_NAME}/${SM_BCK_SPACE_NAME}/${RESTORE_TIMESTAMP_ARG}

# check if SNAPSHOT exists, if not, proceed without sync
echo "[EBS backup LCC] - Checking if s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT} exists..."
aws s3 ls s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT} || (echo "[EBS backup LCC] - Snapshot s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT} does not exist. Proceed without the sync."; exit 0)

# files are backed up to 'restored-files' to avoid overwriting
echo "[EBS backup LCC] - Syncing s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT} to $SM_BCK_HOME/restored-files"
aws s3 sync s3://${SM_BCK_BUCKET}/${SM_BCK_PREFIX}/${SNAPSHOT} $SM_BCK_HOME/restored-files/${RESTORE_TIMESTAMP_ARG}

exitcode=$?
echo "[EBS backup LCC] - S3 sync result (restore): "
echo $exitcode
if [ $exitcode -eq 0 ] || [ $exitcode -eq 2 ]
then
    CURRENT_TIMESTAMP=`date +%F-%H-%M-%S`
    echo "[EBS backup LCC] - Restore completed at $CURRENT_TIMESTAMP" >> $SM_BCK_HOME/.restore/${RESTORE_TIMESTAMP_ARG}_SYNC_COMPLETE
fi

EOF
envsubst "$(printf '${%s} ' ${!SM_BCK_*})" < $HOME/.restore/restore.tp > $HOME/.restore/restore.sh

chmod +x $HOME/.restore/restore.sh
fi

# Run backup (at least once at bootstrap)
echo "[EBS backup LCC] - Executing backup at bootstrap."
nohup $HOME/.backup/backup.sh >> $LOG_FILE 2>&1 & 

# Check if scheduled backup needs to be enabled.
if [ $ENABLE_SCHEDULED_SYNC -eq 1 ]
then
    echo "[EBS backup LCC] - Adding backup script to crontab..."
    sudo mkdir -p /var/tmp
    sudo rm -f /var/tmp/ebs_backup.sh
    cp $HOME/.backup/backup.sh /var/tmp/ebs_backup.sh
    sudo chown root:root /var/tmp/ebs_backup.sh
    sudo chmod +x /var/tmp/ebs_backup.sh
    echo "* */$SYNC_INTERVAL_IN_HOURS * * * /bin/bash -ic '/var/tmp/ebs_backup.sh >> $LOG_FILE'" | sudo crontab -
fi

# Check if restore timestamp is set.
if ! [ -z "$RESTORE_TIMESTAMP" ]
then
    echo "[EBS backup LCC] - User profile tagged with restore timestamp: ${RESTORE_TIMESTAMP}. Restoring files..."
    # nohup to bypass the LCC timeout at start
    nohup $HOME/.restore/restore.sh $RESTORE_TIMESTAMP >> $LOG_FILE 2>&1 &
fi
