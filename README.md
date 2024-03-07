# SageMaker Studio Lifecycle Configuration examples

## Overview
A collection of sample scripts customizing SageMaker Studio applications using lifecycle configurations.

Lifecycle Configurations (LCCs) provide a mechanism to customize SageMaker Studio applications via shell scripts that are executed at application bootstrap. For further information on how to use lifecycle configurations with SageMaker Studio applications, please refer to the AWS documentation:

- [Using Lifecycle Configurations with JupyterLab](https://docs.aws.amazon.com/sagemaker/latest/dg/jl-lcc.html)
- [Using Lifecycle Configurations with Code Editor](https://docs.aws.amazon.com/sagemaker/latest/dg/code-editor-use-lifecycle-configurations.html)

> **Warning**
> The sample scripts in this repository are designed to work with SageMaker Studio JupyterLab and Code Editor applications. If you are using SageMaker Studio Classic, please refer to https://github.com/aws-samples/sagemaker-studio-lifecycle-config-examples

## Sample Scripts

### [SageMaker JupyterLab](https://docs.aws.amazon.com/sagemaker/latest/dg/studio-updated-jl.html)
- [auto-stop-idle](jupyterlab/auto-stop-idle/) - Automatically shuts down JupyterLab applications that have been idle for a configurable time.

### [SageMaker Code Editor](https://docs.aws.amazon.com/sagemaker/latest/dg/code-editor.html)
- [auto-stop-idle](code-editor/auto-stop-idle/) - Automatically shuts down Code Editor applications that have been idle for a configurable time.

## Developing LLCs for SageMaker Studio applications
For best practices, please check [DEVELOPMENT](DEVELOPMENT.md).

## License
This project is licensed under the [MIT-0 License](LICENSE).

## Authors
[Giuseppe A. Porcelli](https://www.linkedin.com/in/giuporcelli/) - Principal, ML Specialist Solutions Architect - Amazon SageMaker
<br />Spencer Ng - Software Development Engineer - Amazon SageMaker