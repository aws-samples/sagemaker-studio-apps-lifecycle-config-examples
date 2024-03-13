from datetime import datetime
import os
import time
import boto3
import json
import sys
import argparse

DATE_FORMAT = "%Y-%m-%dT%H:%M:%S.%fz"

def log_message(message):
    """
    Logs a message.
    """
    print(f"{datetime.now().strftime(DATE_FORMAT)} - {message}")

def check_user_activity(workspace_dir, idle_threshold):
    # Get the timestamp of the most recently modified file or folder
    recent_item = max(
        (os.path.join(root, file) for root, _, files in os.walk(workspace_dir) for file in files),
        key=lambda x: os.lstat(x).st_mtime,
        default=None
    )

    # Get the current time
    current_time = time.time()

    # Calculate the time difference
    time_diff = current_time - os.stat(recent_item).st_mtime if recent_item else float('inf')
    log_message(f"[auto-stop-idle] - Logging time difference between current time and time files were last changed {time_diff}.")

    # Check if the user is idle based on the idle time threshold
    if time_diff > idle_threshold:
        return "idle"
    else:
        return "active"

# Create an argument parser
parser = argparse.ArgumentParser(description='Check user activity and terminate SageMaker Studio app if idle.')
parser.add_argument('--time', type=int, help='Idle time threshold in seconds')
parser.add_argument('--region', type=str, help='AWS region')

# Parse the command-line arguments
args = parser.parse_args()

# Check if idle_threshold is provided
if args.time is None:
    parser.print_help()
    sys.exit(1)

if args.region is None:
    parser.print_help()
    sys.exit(1)

# Monitor workspace_dirs for changes to implement auto-shutdown, as these paths track updates to both unsaved and saved editor content, covering all user activity scenarios.
workspace_dirs = ["/opt/amazon/sagemaker/sagemaker-code-editor-server-data/data/User/History", "/opt/amazon/sagemaker/sagemaker-code-editor-server-data/data/User/Backups/empty-window/untitled"]
idle_threshold = args.time  # this is in seconds. for ex: 1800 seconds for 30 minutes
aws_region = args.region # get the region.

# Track the activity status for each directory
activity_status = [check_user_activity(directory, idle_threshold) for directory in workspace_dirs]

# Terminate the SageMaker Studio app if all directories are idle and no activity is observed.
if all(status == "idle" for status in activity_status):
    # Load the resource metadata from the file
    with open('/opt/ml/metadata/resource-metadata.json') as f:
        resource_metadata = json.load(f)

    # Extract the required details for deleting the app
    domain_id = resource_metadata['DomainId']
    space_name = resource_metadata['SpaceName']
    app_name = resource_metadata['ResourceName']
    app_type = resource_metadata['AppType']
    resource_arn = resource_metadata["ResourceArn"]

    # Use boto3 api call to delete the app. 
    sm_client = boto3.client('sagemaker',region_name=aws_region)
    response = sm_client.delete_app(
        DomainId=domain_id,
        AppType=app_type,
        AppName=app_name,
        SpaceName=space_name
    )
    log_message(f"[auto-stop-idle] - Deleting app {app_type}-{app_name}. Domain ID: {domain_id}. Space name: {space_name}. Resource ARN: {resource_arn}.")
    log_message("[auto-stop-idle] - SageMaker Code Editor app terminated due to being idle for given duration.")
else:
    log_message("[auto-stop-idle] - SageMaker Code Editor app is not idle. Passing check.")
