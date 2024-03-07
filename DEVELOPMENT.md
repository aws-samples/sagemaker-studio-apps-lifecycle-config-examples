## Best practicies for developing Lifecycle Configuration scripts for SageMaker Studio applications

### SageMaker JupyterLab

1. You can test JupyterLab scripts in the JupyterLab **Terminal**. If the scripts are running without issues in terminals, you can safely assume it will run as an LCC script as well.

2. Always add the `set -eux` command to the beginning of your script. This command will print out the commands executed by your script line by line and will be visible in the logs as well. This helps you to troubleshoot your scripts faster.

3. The script will be running as `sagemaker-user`. Use `sudo` to run commands as `root`.

4. If you are installing Jupyter Lab or Jupyter Server extensions, ensure they're compatible with the Studio JupyterLab version.

5. Persistent EBS storage is mounted at `/home/sagemaker-user`; leverage persistent storage to avoid re-installing libraries or packages at each restart.
