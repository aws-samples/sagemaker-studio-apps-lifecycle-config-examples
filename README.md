# SageMaker Studio JupyterLab Lifecycle Configuration examples

## Overview
A collection of sample scripts customizing SageMaker Studio JupyterLab applications using lifecycle configurations.

Lifecycle Configurations (LCCs) provide a mechanism to customize JupyterLab application instances via shell scripts that are executed at application bootstrap. For further information on how to use lifecycle configurations with SageMaker Studio JupyterLab applications, please refer to the [AWS documentation](https://docs.aws.amazon.com/sagemaker/latest/dg/jl-lcc.html).

> **Warning**
> The sample scripts in this repository are designed to work with SageMaker Studio JupyterLab applications. If you are using SageMaker Studio Classic, please refer to https://github.com/aws-samples/sagemaker-studio-lifecycle-config-examples

## Sample Scripts
- [auto-stop-idle](scripts/auto-stop-idle/) - Automatically shuts down JupyterLab applications that have been idle for a configurable time.

## Developing LLCs for SageMaker Studio JupyterLab
For best practices, please check [DEVELOPMENT](DEVELOPMENT.md).

## License
This project is licensed under the [MIT-0 License](LICENSE).

## Authors
[Giuseppe A. Porcelli](https://www.linkedin.com/in/giuporcelli/) - Principal, ML Specialist Solutions Architect - Amazon SageMaker
