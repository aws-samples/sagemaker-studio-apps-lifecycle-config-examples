#!/bin/bash
set -ex

# PARAMETERS
ASI_VERSION=0.3.0
IDLE_TIME=3600  # in seconds, change this to desired idleness time before app shuts down
LOG_FILE=/var/log/apps/app_container.log # Writing to app_container.log delivers logs to CW logs.
SOLUTION_DIR=/var/tmp/auto-stop-idle

AUTOSTOP_FILE_URL="https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/sagemaker_code_editor_auto_shut_down-$ASI_VERSION.tar.gz"

{
echo "Fetching the autostop script"
echo "Downloading the autostop script package"

# Download asset from corresponding repo release
curl -LO $AUTOSTOP_FILE_URL

echo "Extracting the package"
tar -xvzf "sagemaker_code_editor_auto_shut_down-$ASI_VERSION.tar.gz"

# Create solution directory
sudo mkdir -p $SOLUTION_DIR

# Moving the autostop.py to the SOLUTION_DIR
echo "Moving the autostop.py to the solution directory"
sudo mv sagemaker_code_editor_auto_shut_down/python-package/src/sagemaker_code_editor_auto_shut_down/autostop.py $SOLUTION_DIR/

echo "Detecting Python install with boto3 install"
sudo apt-get update -y
sudo sh -c 'printf "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d'
sudo apt-get install -y cron

# Redirect stderr as it is unneeded
CONDA_PYTHON_DIR=$(source /opt/conda/bin/activate base && which python)
if $CONDA_PYTHON_DIR -c "import boto3" 2>/dev/null; then
    PYTHON_DIR=$CONDA_PYTHON_DIR
elif /usr/bin/python -c "import boto3" 2>/dev/null; then
    PYTHON_DIR='/usr/bin/python'
else
    # If no boto3 just quit because the script won't work
    echo "No boto3 found in Python or Python3. Exiting..."
    exit 1
fi
echo "Found boto3 at $PYTHON_DIR"

# Touch file to ensure idleness timer is reset to 0
echo "Touching file to reset idleness timer"
touch /opt/amazon/sagemaker/sagemaker-code-editor-server-data/data/User/History/startup_timestamp

echo "Starting the SageMaker autostop script in cron"
echo "*/2 * * * * export AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=\$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI; $PYTHON_DIR $SOLUTION_DIR/autostop.py --time $IDLE_TIME --region \$AWS_DEFAULT_REGION > /home/sagemaker-user/autoshutdown.log" | crontab -

}
