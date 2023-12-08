# AWS Self Hosted Runner GitHub Action

[![GitHub Super-Linter](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/linter.yml/badge.svg)](https://github.com/super-linter/super-linter)
![CI](https://github.com/sustainable-computing-io/aws_ec2_self_hosted_runner/actions/workflows/ci.yml/badge.svg)

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
        with:
          ACTION: "create"
        env:
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
        with:
          ACTION: "unregister"
        env:
          RUNNER_NAME: ${{ needs.setup-runner.outputs.runner_name }}
          GITHUB_TOKEN: ${{ secrets.MY_GITHUB_TOKEN }}
          GITHUB_REPO: ${{ github.repository }}
    - name: Terminate instance
        uses: sustainable-computing-io/aws_ec2_self_hosted_runner@main
        with:
          ACTION: "terminate"
        env:
          INSTANCE_ID: ${{ needs.setup-runner.outputs.instance_id }}
          AWS_REGION: ${{ secrets.AWS_REGION }}
          GITHUB_TOKEN: ${{ secrets.MY_GITHUB_TOKEN }}
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          BUCKET_NAME: ${{ needs.setup-runner.outputs.bucket_name }}
```

## Inputs

| Parameter            | Description                                                                                           | Default Value                            |
|----------------------|-------------------------------------------------------------------------------------------------------|------------------------------------------|
| AMI_ID               | The ID of the Amazon Machine Image (AMI) to use for the instance.                                      | "ami-0e4d0bb9670ea8db0" (Ubuntu Server 20.04 LTS) |
| INSTANCE_TYPE        | The type of the instance to launch.                                                                   | "t2.micro"                               |
| SECURITY_GROUP_ID    | The ID of the security group to associate with the instance.                                           | Replace "YOUR_SECURITY_GROUP_ID" with the actual security group ID. |
| GITHUB_TOKEN         | The GitHub token to authenticate with the GitHub API. Must have repository admin permission.                | Replace "YOUR_TOKEN" with the actual GitHub token. |
| GITHUB_REPO          | The GitHub repository in the format "owner/repository" to clone and use.                                     | "sustainable-computing-io/kepler-model-server" |
| REGION               | The AWS region to launch the spot instance.                                                            | "us-east-2"                              |
| DEBUG                | Enable or disable debug mode.                                                                         | "false"                                  |
| KEY_NAME             | The name of the key pair to use for the instance.                                                      | Replace "YOUR_KEY_NAME" with the actual key pair name. |
| GITHUB_OUTPUT        | The name of the file to output the instance ID to. ***This is only for local test use. Don't set it in the workflow file.*** | "github_output.txt"                      |
| ROOT_VOLUME_SIZE     | The size of the root volume in GB.                                                                    | 200                                      |
| SPOT_INASTANCE_ONLY  | If true, only create a spot instance.                                                                 | "true"                                   |
| CREATE_S3_BUCKET     | If true, create a S3 bucket to store the model.                                                        | "false"                                  |
| BUCKET_NAME          | The name of the S3 bucket to store the model.                                                          | The bucket name is the same as the repository name with time date stamp. |

## Outputs

| Output | Description             |
| ------ | ----------------------- |
| `instance_id` | AWS EC2 instance ID |
| `runner_name` | GitHub self hosted runner name |
| `instance_ip` | AWS EC2 instance IP |
| `bucket_name` | AWS S3 bucket name |

## Test Locally

After you've cloned the repository to your local machine or codespace, you'll
need to perform some initial setup steps before you can test your action.

> [!NOTE]
>
> You'll need to have a reasonably modern version of
> [Docker](https://www.docker.com/get-started/) handy (e.g. docker engine
> version 20 or later).

1. :hammer_and_wrench: Build the container

   Make sure to replace `actions/aws_ec2_self_hosted_runner` with an appropriate
   label for your container.

   ```bash
   docker build -t actions/aws_ec2_self_hosted_runner .
   ```

1. :white_check_mark: Test the container

   You can pass individual environment variables using the `--env` or `-e` flag.

   ```bash
   
   ```

   Or you can pass a file with environment variables using `--env-file`.

   ```bash
   ```
