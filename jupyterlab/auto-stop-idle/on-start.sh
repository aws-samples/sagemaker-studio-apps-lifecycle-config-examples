# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#!/bin/bash
set -eux
ASI_VERSION=0.2.0

# OVERVIEW
# This script stops a SageMaker Studio JupyterLab app, once it's idle for more than X seconds, based on IDLE_TIME_IN_SECONDS configuration.
# Note that this script will fail if either condition is not met:
#   1. The JupyterLab app has internet connectivity to fetch the autostop idle Python package
#   2. The Studio Domain or User Profile execution role has permissions to SageMaker:DeleteApp to delete the JupyterLab app

# User variables [update as needed]
IDLE_TIME_IN_SECONDS=3600       # The max time (in seconds) the JupyterLab app can stay idle before being terminated.

# User variables - advanced [update only if needed]
IGNORE_CONNECTIONS=True         # Set to False if you want to consider idle JL sessions with active connections as not idle.
SKIP_TERMINALS=False            # Set to True if you want to skip any idleness check on Jupyter terminals.

# System variables [do not change if not needed]
JL_HOSTNAME=0.0.0.0
JL_PORT=8888
JL_BASE_URL=/jupyterlab/default/
CONDA_HOME=/opt/conda/bin
LOG_FILE=/var/log/apps/app_container.log # Writing to app_container.log delivers logs to CW logs.
SOLUTION_DIR=/var/tmp/auto-stop-idle # Do not use /home/sagemaker-user
STATE_FILE=$SOLUTION_DIR/auto_stop_idle.st
PYTHON_PACKAGE=sagemaker_studio_jlab_auto_stop_idle-$ASI_VERSION.tar.gz
PYTHON_SCRIPT_PATH=$SOLUTION_DIR/sagemaker_studio_jlab_auto_stop_idle/auto_stop_idle.py

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
    # start/restart the service.
	sudo service cron restart
fi

# Creating solution directory.
sudo mkdir -p $SOLUTION_DIR

# Downloading autostop idle Python package.
echo "Downloading autostop idle Python package..."
curl -LO --output-dir /var/tmp/ https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/$PYTHON_PACKAGE
sudo $CONDA_HOME/pip install -U -t $SOLUTION_DIR /var/tmp/$PYTHON_PACKAGE

# Setting container credential URI variable to /etc/environment to make it available to cron
sudo /bin/bash -c "echo 'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI' >> /etc/environment"

# Add script to crontab for root.
echo "Adding autostop idle Python script to crontab..."
echo "*/2 * * * * /bin/bash -ic '$CONDA_HOME/python $PYTHON_SCRIPT_PATH --idle-time $IDLE_TIME_IN_SECONDS --hostname $JL_HOSTNAME \
--port $JL_PORT --base-url $JL_BASE_URL --ignore-connections $IGNORE_CONNECTIONS \
--skip-terminals $SKIP_TERMINALS --state-file-path $STATE_FILE >> $LOG_FILE'" | sudo crontab -
