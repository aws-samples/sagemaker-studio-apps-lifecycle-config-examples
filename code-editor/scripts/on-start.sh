#!/bin/bash
set -ex
ASI_VERSION=0.1.0

# PARAMETERS 
IDLE_TIME=120  # in seconds, change this to desired idleness time before app shuts down

# (private) PUBLIC FILE_URL (uncomment line below when public) this is from a public repo
AUTOSTOP_FILE_URL="https://github.com/aws-spenceng/assets/releases/download/v$ASI_VERSION/sm-ce-auto-shut-down-$ASI_VERSION.tar.gz"

# (public) PUBLIC FILE_URL (uncomment line below when public) this is from a public repo
# AUTOSTOP_FILE_URL="https://github.com/aws-spenceng/sm-ce-auto-shut-down/releases/download/v$ASI_VERSION/sm-ce-auto-shut-down-$ASI_VERSION.zip"

# (private) enter in ASSET_ID in terminal command to setup, see README
# ASSET_ID=your_static_asset_id
# ASSET_NAME="sm-ce-auto-shut-down-$ASI_VERSION.tar.gz"
# AUTOSTOP_FILE_URL="https://api.github.com/repos/aws-spenceng/sm-ce-auto-shut-down/releases/assets/$ASSET_ID"

echo "Fetching the autostop script"
echo "Downloading the autostop script package"

# (private) this is using the public asset above
curl -L -o sm-ce-auto-shut-down-$ASI_VERSION.tar.gz $AUTOSTOP_FILE_URL

echo "Extracting the package"
tar -xvzf "sm-ce-auto-shut-down-$ASI_VERSION.tar.gz"


# Moving the autostop.py to the current directory
# Adjust the path according to the structure inside the tar.gz file
echo "Moving the autostop.py to the current directory"
mv sm-ce-auto-shut-down/python-package/src/sagemaker_code_editor_auto_shut_down/autostop.py ./

echo "Detecting Python install with boto3 install"
sudo apt-get update -y
sudo apt-get install -y vim
sudo sh -c 'printf "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d'
sudo apt-get install -y cron
sudo service cron start

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

echo "Starting the SageMaker autostop script in cron"
echo "*/5 * * * * export AWS_CONTAINER_CREDENTIALS_RELATIVE_URI=$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI; $PYTHON_DIR $PWD/autostop.py --time $IDLE_TIME --region $AWS_DEFAULT_REGION > /home/sagemaker-user/autoshutdown.log" | crontab -
