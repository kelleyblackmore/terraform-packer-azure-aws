#!/bin/bash
set -e

# Variables
AMI_ID="ami-011ab8f738f4443f1"
KEY="mac.pem"
INSTANCE_TYPE="t2.micro"
KEY_NAME="your-key-pair"
SECURITY_GROUP_ID="your-security-group-id"
SUBNET_ID="your-subnet-id"
TAG_NAME="Packer Test Instance"

# Function to handle errors
error_exit() {
    echo "$1" 1>&2
    exit 1
}

# Run tests on AMI
echo "Running tests on AMI ${AMI_ID}..."
INSTANCE_ID=$(aws ec2 run-instances --image-id ${AMI_ID} --instance-type ${INSTANCE_TYPE} --key-name ${KEY_NAME} --security-group-ids ${SECURITY_GROUP_ID} --subnet-id ${SUBNET_ID} --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG_NAME}}]" --query 'Instances[0].InstanceId' --output text) || error_exit "Failed to run instance."

# Wait for instance to be ready
echo "Waiting for instance to be ready..."
aws ec2 wait instance-status-ok --instance-ids ${INSTANCE_ID} || error_exit "Instance did not reach status OK."

# Run tests
echo "Running tests..."
PUBLIC_DNS=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --query 'Reservations[].Instances[].PublicDnsName' --output text) || error_exit "Failed to get public DNS."
ssh -i ${KEY} ec2-user@${PUBLIC_DNS} 'uname -a && sudo systemctl is-active amazon-ssm-agent' || error_exit "Tests failed."

# Terminate instance
echo "Tests completed. Terminating instance..."
aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} || error_exit "Failed to terminate instance."
echo "Instance terminated successfully."