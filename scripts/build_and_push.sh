#!/bin/bash
set -e

# This script builds the Docker image and pushes it to ECR to be ready for use by SageMaker.
# The argument to this script is the image name. This will be used as the image on the local
# machine and combined with the account and region to form the repository name for ECR.

echo "Inside build_and_push.sh file"

DOCKER_IMAGE_NAME=$1

if [ -z "$DOCKER_IMAGE_NAME" ]; then
    echo "Usage: $0 <image-name>"
    exit 1
fi

echo "Value of DOCKER_IMAGE_NAME is $DOCKER_IMAGE_NAME"

# Get the account number associated with the current IAM credentials
account=$(aws sts get-caller-identity --query Account --output text)

if [ $? -ne 0 ]; then
    echo "Failed to get AWS account ID"
    exit 255
fi

# Get the region defined in the current configuration (default to us-west-2 if none defined)
region=${AWS_REGION:-us-west-2}
echo "Region value is: $region"

# If the repository doesn't exist in ECR, create it.
ecr_repo_name="${DOCKER_IMAGE_NAME}-ecr-repo"
echo "Value of ecr_repo_name is $ecr_repo_name"

aws ecr describe-repositories --repository-names ${ecr_repo_name} > /dev/null 2>&1 || aws ecr create-repository --repository-name ${ecr_repo_name}

if [ $? -ne 0 ]; then
    echo "Failed to describe or create ECR repository"
    exit 255
fi

image_name="${DOCKER_IMAGE_NAME}-${CODEBUILD_BUILD_NUMBER}"

# Get the login command from ECR and execute docker login
aws ecr get-login-password | docker login --username AWS --password-stdin ${account}.dkr.ecr.${region}.amazonaws.com

if [ $? -ne 0 ]; then
    echo "Failed to login to ECR"
    exit 255
fi

fullname="${account}.dkr.ecr.${region}.amazonaws.com/${ecr_repo_name}:${image_name}"
echo "Fullname is $fullname"

# Build the docker image locally with the image name and then push it to ECR with the full name
docker build -t ${image_name} ${CODEBUILD_SRC_DIR}/python-docker/

if [ $? -ne 0 ]; then
    echo "Failed to build Docker image"
    exit 255
fi

echo "Image name is $image_name"

echo "Tagging of Docker Image in Progress"
docker tag ${image_name} ${fullname}

if [ $? -ne 0 ]; then
    echo "Failed to tag Docker image"
    exit 255
fi

echo "Tagging of Docker Image is Done"

docker images

echo "Docker Push in Progress"
docker push ${fullname}

if [ $? -ne 0 ]; then
    echo "Docker Push Event did not Succeed with Image ${fullname}"
    exit 1
else
    echo "Docker Push Event is Successful with Image ${fullname}"
fi
