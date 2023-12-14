# AWS Self Hosted Runner GitHub Action

[![GitHub Super-Linter](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/linter.yml/badge.svg)](https://github.com/super-linter/super-linter)
![CI](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/pr.yml/badge.svg)

## Usage

Here's an example of how to use this action in a workflow file:

```yaml
name: Example Workflow

on:
  workflow_dispatch:
    inputs:
      ami_id:
        description: 'AWS Machine Image ID'
        required: false
        default: 'ami-0e4d0bb9670ea8db0'
      instance_type:
        description: 'AWS EC2 Instance Type'
        required: false
        default: 't2.micro'
      need_s3_bucket:
        description: 'Need S3 bucket?'
        required: false
        default: 'false'
jobs:
  setup-runner:
    name: setup self hosted runner
    runs-on: ubuntu-latest
    steps:
      - name: setup runner
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@main
        env:
          ACTION: "create"
          AWS_REGION: ${{ secrets.AWS_REGION }}
          GITHUB_TOKEN: ${{ secrets.MY_GITHUB_TOKEN }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          SECURITY_GROUP_ID: ${{ secrets.AWS_SECURITY_GROUP_ID }}
          GITHUB_REPO: ${{ github.repository }}
          AMI_ID: ${{ github.event.inputs.ami_id }}
          INSTANCE_TYPE: ${{ github.event.inputs.instance_type }
          CREATE_S3_BUCKET: ${{ github.event.inputs.need_s3_bucket }}
  
  run-tests:
    needs: setup-runner
    name: run tests
    runs-on: [self-hosted, linux, x64]
    steps:
    - name: Checkout
      uses: actions/checkout@v2

    - name: Run Tests
      run: |
        export INSTANCE_ID=${{ needs.setup-runner.outputs.instance_id }}
        echo "Running tests on self-hosted runner with instance $INSTANCE_ID"
        uname -a # or any other command

  destroy-runner:
    if: always()
    needs: [setup-runner, run-tests]
    runs-on: ubuntu-latest
    steps:
    - name: Unregister runner
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@main
        env:
          ACTION: "unregister"
          RUNNER_NAME: ${{ needs.setup-runner.outputs.runner_name }}
          GITHUB_TOKEN: ${{ secrets.MY_GITHUB_TOKEN }}
          GITHUB_REPO: ${{ github.repository }}
    - name: Terminate instance
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@main
        env:
          ACTION: "terminate"        
          INSTANCE_ID: ${{ needs.setup-runner.outputs.instance_id }}
          AWS_REGION: ${{ secrets.AWS_REGION }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          BUCKET_NAME: ${{ needs.setup-runner.outputs.bucket_name }}
```

## Inputs and Secrets

| Parameter            | Description                                                                                           | Default Value                            |
|----------------------|-------------------------------------------------------------------------------------------------------|------------------------------------------|
| SECURITY_GROUP_ID    | (Required) The ID of the AWS security group to associate with the instance.                                      |  Should be set in secrets. |
| GITHUB_TOKEN         | (Required) The GitHub token to authenticate with the GitHub API. Must have repository admin permission.          | Should be set in secrets. |
| AWS_ACCESS_KEY_ID    | (Required) The AWS access key ID to use for authentication.                                                      | Should be set in secrets. |
| AWS_SECRET_ACCESS_KEY| (Required) The AWS secret access key to use for authentication.                                                  | Should be set in secrets. |
| AMI_ID               | (Optional) The ID of the Amazon Machine Image (AMI) to use for the instance.                                     | "ami-0e4d0bb9670ea8db0" (Ubuntu Server 20.04 LTS) |
| INSTANCE_TYPE        | (Optional) The type of the instance to launch.                                                                   | "t2.micro"                               |
| GITHUB_REPO          | (Optional) The GitHub repository in the format "owner/repository" to clone and use.                              | "sustainable-computing-io/kepler-model-server" |
| AWS_REGION           | (Optional) The AWS region to launch the spot instance.                                                           | "us-east-2"                              |
| KEY_NAME             | (Optional) The name of the key pair to use for the instance.                                                     | Replace "YOUR_KEY_NAME" with the actual key pair name. |
| ROOT_VOLUME_SIZE     | (Optional) The size of the root volume in GB.                                                                    | 8                                      |
| SPOT_INASTANCE_ONLY  | (Optional) If true, only create a spot instance.                                                                 | "true"                                   |
| CREATE_S3_BUCKET     | (Optional) If true, create a S3 bucket to store the model.                                                       | "false"                                  |
| BUCKET_NAME          | (Optional) The name of the S3 bucket to store the model.                                                         | The bucket name is the same as the repository name with time date stamp. |

## Outputs

| Output | Description             |
| ------ | ----------------------- |
| `instance_id` | AWS EC2 instance ID |
| `runner_name` | GitHub self hosted runner name |
| `instance_ip` | AWS EC2 instance IP |
| `bucket_name` | AWS S3 bucket name |

