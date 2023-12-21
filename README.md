# AWS Self Hosted Runner GitHub Action

[![GitHub Super-Linter](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/linter.yml/badge.svg)](https://github.com/super-linter/super-linter)
![CI](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/CI.yml/badge.svg)

## Usage

Here's an example of how to use this action in a workflow file:

```yaml
name: Test Self-hosted Runner

on:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  setup-runner:
    name: Test-Setup Self Hosted Runner
    runs-on: ubuntu-latest
    outputs:
      instance_id: ${{ steps.create-runner.outputs.instance_id }}
      runner_name: ${{ steps.create-runner.outputs.runner_name }}

    steps:
      - name: Create Runner
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@v1
        id: create-runner
        with:
            action: "create"
            aws_region: ${{ secrets.AWS_REGION }}
            github_token: ${{ secrets.GH_SELF_HOSTED_RUNNER_TOKEN }}
            aws_access_key_id: ${{ secrets.AWS_ACCESS_KEY_ID }}
            aws_secret_access_key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
            security_group_id: ${{ secrets.AWS_SECURITY_GROUP_ID }}
            github_repo: ${{ github.repository }}
            ami_id: "ami-0e4d0bb9670ea8db0"
            instance_type: "t2.micro"
            create_s3_bucket: "false"
            spot_instance_only: "true"

      - name: Print Output
        id: output
        run: |
          echo "instance_id ${{ steps.create-runner.outputs.instance_id }}"
          echo "instance_ip ${{ steps.create-runner.outputs.instance_ip }}"
          echo "runner_name ${{ steps.create-runner.outputs.runner_name }}"
          echo "bucket_name ${{ steps.create-runner.outputs.bucket_name }}"
    
  test-runner:
    needs: setup-runner
    name: GitHub Self Hosted Runner Tests
    runs-on: [self-hosted, linux, x64]

    steps:
      - name: Checkout
        id: checkout
        uses: actions/checkout@v4

      - name: Run Tests
        run: |
          export INSTANCE_ID="${{ needs.setup-runner.outputs.instance_id }}"
          echo "Running tests on self-hosted runner with instance ${INSTANCE_ID}"
          uname -a # or any other command
          cat /etc/os-release 
          cat /proc/cpuinfo 
  
  destroy-runner:
    if: always()
    needs: [setup-runner, test-runner]
    name: Destroy Self Hosted Runner
    runs-on: ubuntu-latest
    steps:
      - name: unregister runner
        id: unregister
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@v1
        with:
          action: "unregister"
          runner_name: ${{ needs.setup-runner.outputs.runner_name }}
          github_token: ${{ secrets.GH_SELF_HOSTED_RUNNER_TOKEN }}
          github_repo: ${{ github.repository }}

      - name: terminate instance
        id: terminate
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@v1
        with:
          action: "terminate"
          aws_access_key_id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws_secret_access_key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          instance_id: ${{ needs.setup-runner.outputs.instance_id }}
```

## Inputs

| Parameter            | Description                                                                                           | Default Value                            |
|----------------------|-------------------------------------------------------------------------------------------------------|------------------------------------------|
| github_token         | (Required) The GitHub token to authenticate with the GitHub API. Must have repository admin permission.          | Should be set in secrets, e.g. GH_SELF_HOSTED_RUNNER_TOKEN |
| aws_access_key_id    | (Required) The AWS access key ID to use for authentication.                                                      | Should be set in secrets. |
| aws_secret_access_key| (Required) The AWS secret access key to use for authentication.                                                  | Should be set in secrets. |
| security_group_id    | (Required) The ID of the AWS security group to associate with the instance.                                      | Should be set in secrets. |
| ami_id               | (Optional) The ID of the Amazon Machine Image (AMI) to use for the instance.                                     | "ami-0e4d0bb9670ea8db0" (Ubuntu Server 20.04 LTS) |
| instance_type        | (Optional) The type of the instance to launch.                                                                   | "t2.micro"                               |
| github_repo          | (Optional) The GitHub repository in the format "owner/repository" to clone and use.                              | "sustainable-computing-io/kepler-model-server" |
| aws_region           | (Optional) The AWS region to launch the spot instance.                                                           | "us-east-2"                              |
| key_name             | (Optional) The name of the key pair to use for the instance.                                                     | Empty. |
| root_volume_size     | (Optional) The size of the root volume in GB.                                                                    | 8                                      |
| spot_inastance_only  | (Optional) If true, only create a spot instance.                                                                 | "true"                                   |
| create_s3_bucket     | (Optional) If true, create a S3 bucket to store the model.                                                       | "false"                                  |
| bucket_name          | (Optional) The name of the S3 bucket to store the model.                                                         | The bucket name is the same as the repository name with time date stamp. |

## Outputs

| Output | Description             |
| ------ | ----------------------- |
| `instance_id` | AWS EC2 instance ID |
| `runner_name` | GitHub self hosted runner name |
| `instance_ip` | AWS EC2 instance IP |
| `bucket_name` | AWS S3 bucket name |
