# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#!/bin/bash
set -eux
ASI_VERSION=0.3.1

# User variables [update as needed]
IDLE_TIME_IN_SECONDS=3600  # in seconds, change this to desired idleness time before app shuts down

# System variables [do not change if not needed]
CONDA_HOME=/opt/conda/bin
LOG_FILE=/var/log/apps/app_container.log # Writing to app_container.log delivers logs to CW logs.
SOLUTION_DIR=/var/tmp/auto-stop-idle # Do not use /home/sagemaker-user
PYTHON_PACKAGE=sagemaker_code_editor_auto_shut_down-$ASI_VERSION.tar.gz
PYTHON_SCRIPT_PATH=$SOLUTION_DIR/sagemaker_code_editor_auto_shut_down/auto_stop_idle.py

# Installing cron
sudo apt-get update -y

# Issue - https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/issues/12
# SM Distribution image 1.6 is not starting cron service by default https://github.com/aws/sagemaker-distribution/issues/354

# Check if cron needs to be installed  ## Handle scenario where script exiting("set -eux") due to non-zero return code by adding true command.
status="$(dpkg-query -W --showformat='${db:Status-Status}' "cron" 2>&1)" || true 
if [ ! $? = 0 ] || [ ! "$status" = installed ]; then
	# Fixing invoke-rc.d: policy-rc.d denied execution of restart.
	sudo /bin/bash -c "echo '#!/bin/sh
	exit 0' > /usr/sbin/policy-rc.d"

	# Installing cron.
	echo "Installing cron..."
	sudo apt install cron
else
	echo "Package cron is already installed."
        # Start/restart the service.
	sudo service cron restart
fi

# Creating solution directory.
sudo mkdir -p $SOLUTION_DIR

# Downloading autostop idle Python package.
echo "Downloading autostop idle Python package..."
curl -LO --output-dir /var/tmp/ https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/$PYTHON_PACKAGE
sudo $CONDA_HOME/pip install -U -t $SOLUTION_DIR /var/tmp/$PYTHON_PACKAGE

# Touch file to ensure idleness timer is reset to 0
echo "Touching file to reset idleness timer"
touch /opt/amazon/sagemaker/sagemaker-code-editor-server-data/data/User/History/startup_timestamp

# Setting container credential URI variable to /etc/environment to make it available to cron
sudo /bin/bash -c "echo 'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI' >> /etc/environment"

# Add script to crontab for root.
echo "Adding autostop idle Python script to crontab..."
echo "*/2 * * * * /bin/bash -ic '$CONDA_HOME/python $PYTHON_SCRIPT_PATH --time $IDLE_TIME_IN_SECONDS --region $AWS_DEFAULT_REGION >> $LOG_FILE'" | sudo crontab -