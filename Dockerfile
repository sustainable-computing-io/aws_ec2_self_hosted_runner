# Set the base image to use for subsequent instructions
FROM alpine:3.19

# hadolint ignore=DL3018
RUN apk add --no-cache aws-cli bash curl jq

# Set the working directory inside the container
WORKDIR /usr/src

RUN apt-get update
RUN apt-get install -y python3-pip bc
RUN pip3 install awscli

# Copy any source file(s) required for the action
COPY entrypoint.sh .

# Configure the container to be run as an executable
ENTRYPOINT ["/usr/src/entrypoint.sh", "$action"]
