# SageMaker Studio JupyterLab auto-stop idle notebooks
The `on-start.sh` script, designed to run as a [SageMaker Studio lifecycle configuration](https://docs.aws.amazon.com/sagemaker/latest/dg/jl-lcc.html), automatically shuts down idle JupyterLab applications after a configurable time of inactivity.

## Installation for all user profiles in a SageMaker Studio domain

From a terminal appropriately configured with AWS CLI, run the following commands:
  
    ASI_VERSION=0.3.1
    curl -LO https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/jupyterlab-lccs-$ASI_VERSION.tar.gz
    tar -xvzf jupyterlab-lccs-$ASI_VERSION.tar.gz

    cd auto-stop-idle

    REGION=<aws_region>
    DOMAIN_ID=<domain_id>
    ACCOUNT_ID=<aws_account_id>
    LCC_NAME=auto-stop-idle
    LCC_CONTENT=`openssl base64 -A -in on-start.sh`

    aws sagemaker create-studio-lifecycle-config \
        --studio-lifecycle-config-name $LCC_NAME \
        --studio-lifecycle-config-content $LCC_CONTENT \
        --studio-lifecycle-config-app-type JupyterLab \
        --query 'StudioLifecycleConfigArn'

    aws sagemaker update-domain \
        --region $REGION \
        --domain-id $DOMAIN_ID \
        --default-user-settings \
        "{
          \"JupyterLabAppSettings\": {
            \"DefaultResourceSpec\": {
              \"LifecycleConfigArn\": \"arn:aws:sagemaker:$REGION:$ACCOUNT_ID:studio-lifecycle-config/$LCC_NAME\",
              \"InstanceType\": \"ml.t3.medium\"
            },
            \"LifecycleConfigArns\": [
              \"arn:aws:sagemaker:$REGION:$ACCOUNT_ID:studio-lifecycle-config/$LCC_NAME\"
            ]
          }
        }"

Make sure to replace <aws_region>, <domain_id>, and <aws_account_id> in the previous commands with the AWS region, the Studio domain ID, and AWS Account ID you are using respectively.

## Definition of idleness
The implementation considers a JupyterLab application as idle when:
1. The running Jupyter kernels and terminals have been idle for more than `IDLE_TIME_IN_SECONDS` (see Configuration section), based on their execution state and last activity date
2. There are no running kernels and terminals, but the last activity date recorded for the last running kernel or terminal plus `IDLE_TIME_IN_SECONDS` is lower than the current date.

**Note**: if the JupyterLab application is started and no kernels or terminals are executed, idleness is computed based on the recorded last activity date. As a consequence, if users work with JupyterLab for more than `IDLE_TIME_IN_SECONDS` without running any Jupyter kernel or terminal, the application will be considered idle and shut down.

## Configuration
The `on-start.sh` script can be customized by modifying the following variables:

- `IDLE_TIME_IN_SECONDS` the time in seconds for which JupyterLab has to be idle before shutting down the application. **Default**: `3600`
- `IGNORE_CONNECTIONS` whether active Jupyter Notebook sessions on idle kernels should be ingored. **Default**: `True`
- `SKIP_TERMINALS` whether skipping any idleness check on Jupyter Terminals. **Default**: `False`

In addition, the following advanced configuration is available (do not change unless explicitly required by your setup):

- `ASI_VERSION` the version of the Auto Stop Idle (ASI) solution.
- `JL_HOSTNAME` the host name for the JupyterLab application. **Default**: `0.0.0.0`
- `JL_PORT` JupyterLab port. **Default**: `8888`
- `JL_BASE_URL` JupyterLab base URL. **Default**: `/jupyterlab/default/`
- `CONDA_HOME` Conda home directory. **Default**: `/opt/conda/bin`
- `LOG_FILE` Path to the file where logs are written; defaults to the location of the Studio app logs, that are automatically delivered to Amazon CloudWatch. **Default**: `/var/log/apps/app_container.log`
- `SOLUTION_DIR` The directory where the solution will be installed. **Default**: `/var/tmp/auto-stop-idle`
- `STATE_FILE` Path to a file that is used to save the state for the Python script (given it's execution is stateless). The location of this file has to be transient, i.e. not persisted across restarts of the Studio JupyterLab app; as a consequence, do not use EBS-backed directories like `/home/sagemaker-user/`. **Default**: `/var/tmp/auto-stop-idle/auto_stop_idle.st`
- `PYTHON_PACKAGE` The name (with version) of the auto stop idle Python package. **Default**: `sagemaker_studio_jlab_auto_stop_idle-$ASI_VERSION.tar.gz`


## Architecture considerations
- The `on-start.sh` lifecycle configuration script adds a `cron` job for `root` using `crontab`, that is configured to run every `2` minutes. The job runs the Python script at `PYTHON_SCRIPT_PATH` which checks for idleness. If the JupyterLab application is detected being idle, the Python script deletes the application by invoking the Amazon SageMaker `DeleteApp` API.
- This solution requires:
  1. internet access to download `PYTHON_PACKAGE`. 
  2. access to the Amazon SageMaker `DeleteApp` API. From the authorization perspective, the execution role associated to the Studio Domain or User Profile must have an associated IAM policy allowing the `sagemaker:DeleteApp` action. 
- Studio JupyterLab application is run as `sagemaker-user`, which has `sudo` privileges; as a consequence, users could potentially remove the cron task and stop any idleness checks. To prevent this behavior, you can modify the configuration in `/etc/sudoers` to remove sudo privileges to `sagemaker-user`.

### Installing in internet-free VPCs
To install the auto-stop-idle solution in an internet-free VPC configurtation you can use Amazon S3 and S3 VPC endpoints to download the auto stop idle Python package. In addition, you will need to configure SageMaker API VPC endpoints for the DeleteApp() operation.

Following are the instructions on how to modify the lifecycle configuration to support internet-free VPC configurations:

1. Download and extract the auto-stop-idle solution tarball:
  
    ```
    ASI_VERSION=0.3.1
    curl -LO https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/jupyterlab-lccs-$ASI_VERSION.tar.gz
    tar -xvzf jupyterlab-lccs-$ASI_VERSION.tar.gz
    ```

2. Download and copy the auto stop idle Python package to a location of choice in Amazon S3. The Execution Role associated to the Studio domain or user profiles must have IAM policies that allow read access to such S3 location.

    ```
    cd auto-stop-idle

    PYTHON_PACKAGE=sagemaker_studio_jlab_auto_stop_idle-$ASI_VERSION.tar.gz
    curl -LO https://github.com/aws-samples/sagemaker-studio-apps-lifecycle-config-examples/releases/download/v$ASI_VERSION/$PYTHON_PACKAGE
    aws s3 cp $PYTHON_PACKAGE s3://<your_bucket_name>/<your_prefix>/
    ```

3. Edit the `on-start.sh` file and replace line 56 with:

    ```
    sudo aws s3 cp s3://<your_bucket_name>/<your_prefix>/$PYTHON_PACKAGE /var/tmp/
    ```

4. Create the LCC and attach to the Studio domain:

    ```
    REGION=<aws_region>
    DOMAIN_ID=<domain_id>
    ACCOUNT_ID=<aws_account_id>
    LCC_NAME=auto-stop-idle
    LCC_CONTENT=`openssl base64 -A -in on-start.sh`

    aws sagemaker create-studio-lifecycle-config \
        --studio-lifecycle-config-name $LCC_NAME \
        --studio-lifecycle-config-content $LCC_CONTENT \
        --studio-lifecycle-config-app-type JupyterLab \
        --query 'StudioLifecycleConfigArn'

    aws sagemaker update-domain \
        --region $REGION \
        --domain-id $DOMAIN_ID \
        --default-user-settings \
        "{
          \"JupyterLabAppSettings\": {
            \"DefaultResourceSpec\": {
              \"LifecycleConfigArn\": \"arn:aws:sagemaker:$REGION:$ACCOUNT_ID:studio-lifecycle-config/$LCC_NAME\",
              \"InstanceType\": \"ml.t3.medium\"
            },
            \"LifecycleConfigArns\": [
              \"arn:aws:sagemaker:$REGION:$ACCOUNT_ID:studio-lifecycle-config/$LCC_NAME\"
            ]
          }
        }"
    ```
