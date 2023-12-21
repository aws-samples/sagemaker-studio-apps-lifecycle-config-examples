# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#!/bin/bash
set -eux
VERSION=0.1.0

# OVERVIEW
# This script stops a SageMaker Studio JupyterLab app, once it's idle for more than X seconds, based on IDLE_TIME_IN_SECONDS configuration.
# Note that this script will fail if either condition is not met:
#   1. The JupyterLab app has internet connectivity to fetch the autostop idle Python script
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
PYTHON_EXECUTABLE=/opt/conda/bin/python
PYTHON_SCRIPT_FILE=/var/tmp/auto-stop-idle/auto_stop_idle.py
LOG_FILE=/var/log/apps/app_container.log # Writing to app_container.log delivers logs to CW logs.
STATE_FILE=/var/tmp/auto-stop-idle/auto_stop_idle.st

# Fixing invoke-rc.d: policy-rc.d denied execution of restart.
sudo /bin/bash -c "echo '#!/bin/sh
exit 0' > /usr/sbin/policy-rc.d"

# Installing cron.
echo "Installing cron..."
sudo apt install cron

# Downloading autostop idle Python script.
echo "Downloading autostop idle Python script..."
curl --create-dirs -LO --output-dir /var/tmp/ https://github.com/aws-samples/sagemaker-studio-jupyterlab-lifecycle-config-examples/releases/download/v$VERSION/auto-stop-idle-$VERSION.tar.gz
sudo tar -xzf /var/tmp/auto-stop-idle-$VERSION.tar.gz -C /var/tmp

# Setting container credential URI variable to /etc/environment to make it available to cron
sudo /bin/bash -c "echo 'AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI' >> /etc/environment"

# Add script to crontab for root.
echo "Adding autostop idle Python script to crontab..."
echo "*/2 * * * * /bin/bash -ic '$PYTHON_EXECUTABLE $PYTHON_SCRIPT_FILE --idle-time $IDLE_TIME_IN_SECONDS --hostname $JL_HOSTNAME \
--port $JL_PORT --base-url $JL_BASE_URL --ignore-connections $IGNORE_CONNECTIONS \
--skip-terminals $SKIP_TERMINALS --state-file-path $STATE_FILE >> $LOG_FILE'" | sudo crontab -
