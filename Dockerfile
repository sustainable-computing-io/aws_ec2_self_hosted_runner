# Set the base image to use for subsequent instructions
FROM alpine:3.21.0

# hadolint ignore=DL3018
RUN apk add --no-cache aws-cli bash curl jq

# Set the working directory inside the container
WORKDIR /usr/src

# Copy any source file(s) required for the action
COPY entrypoint.sh .

# Configure the container to be run as an executable
ENTRYPOINT ["/usr/src/entrypoint.sh"]
