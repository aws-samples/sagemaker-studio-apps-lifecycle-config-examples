# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from datetime import datetime
import os
import getopt, sys
import json
import boto3
import botocore
import requests

from urllib.parse import urljoin

DATE_FORMAT = "%Y-%m-%dT%H:%M:%S.%fz"

def log_message(message):
    """
    Logs a message.
    """
    print(f"{datetime.now().strftime(DATE_FORMAT)} - {message}")

def get_json_medatada():
    """
    Gets the metadata of the current instance, which include Studio domain identifier and app information.
    """
    metadata_path = '/opt/ml/metadata/resource-metadata.json'
    with open(metadata_path, 'r') as metadata:
        json_metadata = json.load(metadata)
    return json_metadata

def delete_app():
    """
    Deletes the JupyterLab app.
    """
    metadata = get_json_medatada();
    domain_id = metadata["DomainId"] 
    app_type = metadata["AppType"]
    app_name = metadata["ResourceName"]
    space_name = metadata["SpaceName"]
    resource_arn = metadata["ResourceArn"]
    aws_region = resource_arn.split(":")[3]

    log_message(f"[auto-stop-idle] - Deleting app {app_type}-{app_name}. Domain ID: {domain_id}. Space name: {space_name}. Resource ARN: {resource_arn}.")

    try:
        client = boto3.client('sagemaker', region_name=aws_region)
        client.delete_app(
            DomainId=domain_id,
            AppType=app_type,
            AppName=app_name,
            SpaceName=space_name
        )
    except botocore.exceptions.ClientError as client_error:
        error_code = client_error.response['Error']['Code']
        if error_code == 'AccessDeniedException' or error_code == 'NotAuthorized':
            log_message(f"[auto-stop-idle] - The current execution role does not allow executing the DeleteApp() operation. Please check IAM policy configurations. Exception: {client_error}")
        else:
            log_message(f"[auto-stop-idle] - An error accurred while deleting app. Exception: {client_error}")
    except Exception as e:
        log_message(f"[auto-stop-idle] - An error accurred while deleting app. Exception: {e}")

def create_state_file(state_file_path):
    """
    Creates a file to store the state for the auto-stop-idle script, only if it does not exist.
    Stores the current date in the state file.
    """
    if not os.path.exists(state_file_path):
        with open(state_file_path, 'w') as f:
            current_date_as_string = datetime.now().strftime(DATE_FORMAT)
            f.write(current_date_as_string)

def get_state_file_contents(state_file_path):
    """
    Gets the contents of the state file, consisting of the computed last modified date.
    """
    with open(state_file_path) as f:
        contents = f.readline()
    return contents

def update_state_file(sessions, terminals, state_file_path):
    """
    Updates the state file with the max last_activity date found in sessions or terminals
    """
    max_last_activity = datetime.min
    if sessions is not None and len(sessions) > 0:
        for notebook_session in sessions:
            notebook_kernel = notebook_session["kernel"]
            last_activity = notebook_kernel["last_activity"]
            last_activity_date = datetime.strptime(last_activity, DATE_FORMAT)
            if last_activity_date > max_last_activity:
                max_last_activity = last_activity_date
    if terminals is not None and len(terminals) > 0:
        for terminal in terminals:
            last_activity = terminal["last_activity"]
            last_activity_date = datetime.strptime(last_activity, DATE_FORMAT)
            if last_activity_date > max_last_activity:
                max_last_activity = last_activity_date
    
    if max_last_activity > datetime.min:
        with open(state_file_path, 'w') as f:
            date_as_string = max_last_activity.strftime(DATE_FORMAT)
            log_message(f"[auto-stop-idle] - Updating state with last activity date {date_as_string}.")
            f.write(date_as_string)

def is_idle(idle_time, last_activity):
    """
    Compares the last_activity date with the current date, to check if idle_time has elapsed.
    """
    last_activity_date = datetime.strptime(last_activity, DATE_FORMAT)
    return ((datetime.now() - last_activity_date).total_seconds() > idle_time)

def get_terminals(app_url, base_url):
    """
    Gets the running terminals. 
    """
    api_url = urljoin(urljoin(app_url, base_url), "api/terminals")
    response = requests.get(api_url, verify=False)
    return response.json()

def get_sessions(app_url, base_url):
    """
    Gets the running notebook sessions. 
    """
    api_url = urljoin(urljoin(app_url, base_url), "api/sessions")
    response = requests.get(api_url, verify=False)
    return response.json()

def check_idle(app_url, base_url, idle_time, ignore_connections, skip_terminals, state_file_path):
    """
    Checks if all terminals or notebook sessions are idle. 
    """
    idle = True

    # Create state file.
    create_state_file(state_file_path)

    terminals = get_terminals(app_url, base_url)
    sessions = get_sessions(app_url, base_url)

    terminal_count = len(terminals) if terminals is not None else 0
    session_count = len(sessions) if sessions is not None else 0

    # Check sessions.
    if session_count > 0:
        for notebook_session in sessions:
            session_name = notebook_session["name"]
            session_id = notebook_session["id"]

            notebook_kernel = notebook_session["kernel"]
            kernel_name = notebook_kernel["name"]
            kernel_id = notebook_kernel["id"]

            if notebook_kernel["execution_state"] == "idle":
                connections = int(notebook_kernel["connections"])
                last_activity = notebook_kernel["last_activity"]

                if ignore_connections or connections <= 0:
                    idle = is_idle(idle_time, last_activity)
                    if not idle:
                        reason = f"kernel not idle based on last activity. Last activity: {last_activity}"
                else:
                    reason = "kernel has active connections"
                    idle = False
            else:
                reason = "kernel execution state is not idle"
                idle = False
            
            if not idle:
                log_message(f"[auto-stop-idle] - Notebook session {session_name} (ID: {session_id}), with kernel {kernel_name} (ID: {kernel_id}) is not idle. Reason: {reason}.")
                break

    # Check terminals.
    if idle and terminal_count > 0 and not skip_terminals:
        for terminal in terminals:
            terminal_name = terminal["name"]
            last_activity = terminal["last_activity"]

            idle = is_idle(idle_time, last_activity)
            if not idle:
                reason = f"terminal not idle based on last activity. Last activity: {last_activity}"

            if not idle:
                log_message(f"[auto-stop-idle] - Terminal {terminal_name} is not idle. Reason: {reason}.")
                break
    
    # Check last activity date from state.
    if idle and session_count <= 0 and (terminal_count <= 0 or skip_terminals):
        state_file_contents = get_state_file_contents(state_file_path)
        idle = is_idle(idle_time, state_file_contents)
        if not idle:
            log_message(f"[auto-stop-idle] - App not idle based on last activity state. Last activity: {state_file_contents}")

    # Update state file.
    update_state_file(sessions, terminals, state_file_path)

    return idle

if __name__ == '__main__':

    # Usage info
    usage_info = """Usage:
    This scripts checks if Studio JupyterLab is idle for X seconds. If it does, it'll stop it:
    python auto_stop_idle.py --idle-time <time_in_seconds> [--port <jupyter_port>] [--hostname <jupyter_hostname>] 
    [--base-url <jupyter_base_url>] [--ignore-connections <True|False>] [--skip-terminals <True|False>] [--state-file-path <state_file_path>]
    Type "python auto_stop_idle.py -h" for the available options.
    """
    # Help info
    help_info = """    -t, --idle-time
        idle time in seconds
    -p, --port
        jupyter port
    -k, --hostname
        jupyter hostname
    -u, --base-url
        jupyter base URL
    -c --ignore-connections
        ignoring users connected to idle notebook sessions
    -s --skip-terminals
        skip checks on terminals
    -a --state-file-path
        path to a file where to save the state
    -h, --help
        help information
    """

    # Setting default values.
    idle_time = 3600
    hostname = "0.0.0.0"
    base_url = "/jupyterlab/default/"
    port = 8888
    ignore_connections = True
    skip_terminals = False
    state_file_path = "/var/tmp/auto_stop_idle.st"

    # Read in command-line parameters
    try:
        opts, args = getopt.getopt(sys.argv[1:], "ht:p:k:u:c:s:a:", ["help","idle-time=","port=","hostname=","base-url=","ignore-connections=", "skip-terminals=", "state-file-path="])
        if len(opts) == 0:
            raise getopt.GetoptError("No input parameters!")
        for opt, arg in opts:
            if opt in ("-h", "--help"):
                print(help_info)
                exit(0)
            elif opt in ("-t", "--idle-time"):
                idle_time = int(arg)
            elif opt in ("-p", "--port"):
                port = str(arg)
            elif opt in ("-k", "--hostname"):
                hostname = str(arg)
            elif opt in ("-u", "--base-url"):
                base_url = str(arg)
            elif opt in ("-c", "--ignore-connections"):
                ignore_connections = False if arg == "False" else True
            elif opt in ("-s", "--skip-terminals"):
                skip_terminals = True if arg == "True" else False
            elif opt in ("-a", "--state-file-path"):
                state_file_path = str(arg)
    except getopt.GetoptError:
        print(usage_info)
        exit(1)

    try:
        if not idle_time:
            log_message("[auto-stop-idle] - Missing '-t' or '--idle_time'")
            exit(2)
        else:
            app_url = f"http://{hostname}:{port}"
            idle = check_idle(app_url, base_url, idle_time, ignore_connections, skip_terminals, state_file_path)

            if idle:
                log_message("[auto-stop-idle] - Detected JupyterLab idle state. Stopping notebook.")
                delete_app()
            else:
                log_message("[auto-stop-idle] - JupyterLab is not idle. Passing check.")
            exit(0)
    except Exception as e:
        log_message(f"[auto-stop-idle] - An error accurred while checking idle state. Exception: {e}")
