#!/usr/bin/env bash
#
# This file is part of the Kepler project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2023 The Kepler Contributors
#

# This script creates a spot instance request and waits for it to become ready.
# It then outputs the instance ID of the created instance.
#
# The script requires the AWS CLI to be installed and configured.

# shellcheck disable=SC1000-SC9999

set -o pipefail

# Define instance parameters
AMI_ID="${AMI_ID:-ami-0e4d0bb9670ea8db0}" # Ubuntu Server 20.04 LTS (HVM), SSD Volume Type, x86_64
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}" # c6i.metal: c is for compute, 6 is 6th geneneration, i is for Intel, metal is for bare metal
SECURITY_GROUP_ID="${SECURITY_GROUP_ID:-YOUR_SECURITY_GROUP_ID}"
GITHUB_TOKEN="${GITHUB_TOKEN:-YOUR_TOKEN}"
GITHUB_REPO="${GITHUB_REPO:-"sustainable-computing-io/kepler-model-server"}"
REGION="${REGION:-us-east-2}"          # Region to launch the spot instance
DEBUG="${DEBUG:-false}"                # Enable debug mode
KEY_NAME="${KEY_NAME:-}"  # Name of the key pair to use for the instance
ROOT_VOLUME_SIZE="${ROOT_VOLUME_SIZE:-8}" # Size of the root volume in GB
SPOT_INSTANCE_ONLY="${SPOT_INSTANCE_ONLY:-true}" # If true, only create spot instance
CREATE_S3_BUCKET="${CREATE_S3_BUCKET:-false}" # Wehther to create a S3 bucket to store the model
BUCKET_NAME="${BUCKET_NAME:-}"         # Name of the S3 bucket
INSTANCE_ID="${INSTANCE_ID:-}"         # ID of the created instance
KEY_NAME_OPT=""                        # Option to pass to the AWS CLI to specify the key pair
[ "$DEBUG" == "true" ] && set -x

# get the organization name from the github repo
ORG_NAME=$(echo "$GITHUB_REPO" | cut -d'/' -f1)
# get the repo name from the github repo
REPO_NAME=$(echo "$GITHUB_REPO" | cut -d'/' -f2)

debug() {
    [ "$DEBUG" == "true" ] &&  echo "DEBUG: $*" 1>&2
}

# check if key name is set
if [ -z "$KEY_NAME" ]; then
    debug "KEY_NAME is not set"
else
    KEY_NAME_OPT="--key-name $KEY_NAME"    # Option to pass to the AWS CLI to specify the key pair
fi


get_github_runner_token () {
    # fail if github token is not set
    if [ -z "$GITHUB_TOKEN" ]; then
        debug "GITHUB_TOKEN is not set"
        exit 1
    fi

    # create a github runner registration token using the github token
    # https://docs.github.com/en/actions/hosting-your-own-runners/adding-self-hosted-runners#adding-a-self-hosted-runner-to-a-repository-using-an-invitation-url
    # https://docs.github.com/en/rest/reference/actions#create-a-registration-token-for-an-organization

    # get the token
    RUNNER_TOKEN=$(curl -s -XPOST -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/actions/runners/registration-token" | jq -r '.token')

    debug "runner token: " "$RUNNER_TOKEN"
    # fail if then length of runner token is less than 5
    if [ ${#RUNNER_TOKEN} -lt 5 ]; then
        debug "Failed to get runner token"
        exit 1
    fi
}

prep () {
    # fail if security group id is not set
    if [ -z "$SECURITY_GROUP_ID" ]; then
        debug "SECURITY_GROUP_ID is not set"
        exit 1
    fi

    # github runner name
    if [ -z "$RUNNER_NAME" ]; then
        RUNNER_NAME="self-hosted-runner-"$(date +"%Y%m%d%H%M%S")
    fi
    # set s3 bucket name if not set and create s3 bucket flag is set to true
    if [ -z "$BUCKET_NAME" ] && [ "$CREATE_S3_BUCKET" == "true" ]; then
        BUCKET_NAME=$REPO_NAME"-"$INSTANCE_TYPE"-"$(date +"%Y%m%d%H%M%S")
    fi

    get_github_runner_token
}

# create the user data script
create_uesr_data () {
    # Encode user data so it can be passed as an argument to the AWS CLI
    # FIXME: it appears that the user data is not passed to the instance
    # ENCODED_USER_DATA=$(echo "$USER_DATA" | base64 | tr -d \\n)
    cat <<EOF > user_data.sh
#!/bin/bash
apt-get update
apt-get install -y curl jq
# install the latest kernel modeules and enable rapl. it doesn seem uname -r works in user data script...
# export KERNEL_VERSION=$(apt list --installed 2>&1 | grep 'linux-image-' | awk -F'/' '{print $1}' |grep "\." | cut -d'-' -f3-) 
# echo "installing kernel modules for version $KERNEL_VERSION"
# apt install linux-modules-${KERNEL_VERSION} linux-modules-extra-${KERNEL_VERSION} -y
# modprobe intel_rapl_common
# Create a folder
mkdir /tmp/actions-runner && cd /tmp/actions-runner
# Download the latest runner package
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L "https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz"
# Optional: Validate the hash
# echo "29fc8cf2dab4c195bb147384e7e2c94cfd4d4022c793b346a6175435265aa278  actions-runner-linux-x64-2.311.0.tar.gz" | shasum -a 256 -c
# Extract the installer
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz
# Create the runner and start the configuration experience
# there is a bug in the github instruction. The config script does not work with sudo unless we set RUNNER_ALLOW_RUNASROOT=true
export RUNNER_ALLOW_RUNASROOT=true
./config.sh --replace --unattended --name ${RUNNER_NAME} --url "https://github.com/${GITHUB_REPO}" --token ${RUNNER_TOKEN}
# Last step, run it!
./run.sh
EOF
}

get_bid_price () {
    BID_PRICE=$(aws ec2 describe-spot-price-history --instance-types "$INSTANCE_TYPE" \
        --product-descriptions "Linux/UNIX" --region "${REGION}" \
        --query 'SpotPriceHistory[0].SpotPrice' --output text)
}

run_spot_instance () {
    INSTANCE_JSON=$(aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type $INSTANCE_TYPE \
    --security-group-ids $SECURITY_GROUP_ID --region ${REGION}  --region ${REGION} \
    --instance-market-options '{"MarketType":"spot", "SpotOptions": {"MaxPrice": "'${BID_PRICE}'" }}' \
    --block-device-mappings '[{"DeviceName": "/dev/sda1","Ebs": { "VolumeSize": '${ROOT_VOLUME_SIZE}', "DeleteOnTermination": true } }]'\
    $KEY_NAME_OPT \
    --user-data file://user_data.sh)
}

run_on_demand_instance() {
    INSTANCE_JSON=$(aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type $INSTANCE_TYPE \
    --security-group-ids $SECURITY_GROUP_ID --region ${REGION} \
    --block-device-mappings '[{"DeviceName": "/dev/sda1","Ebs": { "VolumeSize": '${ROOT_VOLUME_SIZE}', "DeleteOnTermination": true } }]'\
    $KEY_NAME_OPT \
    --user-data file://user_data.sh)
}

create_s3_bucket () {
    # Create S3 bucket
    if [ "$CREATE_S3_BUCKET" == "true" ]; then
       aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" --create-bucket-configuration LocationConstraint="${REGION}"
    fi
}

delete_s3_bucket () {
    # Delete S3 bucket if BUCKET_NAME is set
    if [ -z "$BUCKET_NAME" ]; then
        return
    fi
    aws s3api delete-bucket --bucket "${BUCKET_NAME}" --region "${REGION}"
}

terminate_instance () {
    # Terminate instance   
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "${REGION}" 
    # Delete S3 bucket
    delete_s3_bucket
}

get_instance_ip () {
    # Get instance IP
    INSTANCE_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "${REGION}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
}

create_runner () {
    # GitHub Runner setup script
    create_uesr_data

    # we use spot instance, the bid price is determined by the spot price history, simply use the last price for now
    # Fetching spot price history
    debug "Fetching spot price history..."
    get_bid_price
    # Creating a spot instance request
    debug "Creating a spot instance with an initial bid of ${BID_PRICE}"
    # try 2 times, each time increase the bid price by 10%
    for i in {1..2}
    do
        run_spot_instance
        # Extract instance ID
        INSTANCE_ID=$(echo -n "$INSTANCE_JSON" | jq -r '.Instances[0].InstanceId')

        # Check if instance creation failed
        if [ -z "$INSTANCE_ID" ]; then
            debug "Failed to create instance with bid price ${BID_PRICE}"
            BID_PRICE=$(echo "$BID_PRICE * 1.1" | bc)
            debug "Creating a spot instance with a new bid of ${BID_PRICE}"
            continue
        else
            break
        fi
    done

    # if instance id is still empty, then we failed to create a spot instance
    # create on-demand instance instead
    if [ -z "$INSTANCE_ID" ]; then
        if [ "$SPOT_INSTANCE_ONLY" == "true" ]; then
            debug "SPOT_INSTANCE_ONLY is set to true, exiting"
            exit 1
        fi
        debug "Failed to create spot instance, creating on-demand instance instead"
        run_on_demand_instance

        # Extract instance ID
        INSTANCE_ID=$(echo "$INSTANCE_JSON" | jq -r '.Instances[0].InstanceId')

        # Check if instance creation failed
        if [ -z "$INSTANCE_ID" ]; then
            debug "Failed to create on-demand instance"
            exit 1
        fi
    fi
    rm user_data.sh
    # Wait for instance to become ready
    aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID" --region "${REGION}" 

    # Check if wait command succeeded
    if [ $? -ne 0 ]; then
        debug "Instance failed to become ready. Terminating instance."
        terminate_instance
        exit 1
    fi

    create_s3_bucket
    get_instance_ip

    # Output the instance ID to github output
    echo "instance_id=$INSTANCE_ID"
    echo "runner_name=$RUNNER_NAME"
    echo "instance_ip=$INSTANCE_IP"
    echo "bucket_name=$BUCKET_NAME"
}

list_runner () {
    # list all the runners
    # https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28
    curl -s -X GET -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/actions/runners" | jq -r '.runners[] | .name'
}

unregister_runner () {
    # unregister the runner from github
    # https://docs.github.com/en/rest/reference/actions#delete-a-self-hosted-runner-from-an-organization
    # cannot delete by runner name, need to get the runner id first
    RUNNERS=$(curl -s -X GET -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/actions/runners")
    RUNNER_ID=$(echo "$RUNNERS" | jq -r '.runners[] | select(.name=="'$RUNNER_NAME'") | .id ')
    debug "runner id: " "$RUNNER_ID"
    curl -L -X DELETE -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${ORG_NAME}/${REPO_NAME}/actions/runners/${RUNNER_ID}"
}

# Get ACTION from env var passed by workflow. 
# If not set, use the command line arguments and run the matching function. This is for local testing.
ACTION=${ACTION:-$1}
if [ -z "$ACTION" ]; then
    debug "ACTION is not set"
    exit 1
fi

case $ACTION in
    create)
        INSTANCE_ID=""
        RUNNER_NAME=""
        prep
        create_runner
        ;;
    terminate)
        if [ -z "${INSTANCE_ID}" ]; then
            debug "Instance ID is not set"
            exit 1
        fi
        terminate_instance
        ;;
    unregister)
        if [ -z "${RUNNER_NAME}" ]; then
            debug "Runner name is not set"
            exit 1
        fi
        unregister_runner
        ;;
    list)
        list_runner 
        ;;
    *)
        debug "Invalid action:"${ACTION}
        debug "Usage: $0 {create|terminate|unregister|list}"
        exit 1
esac