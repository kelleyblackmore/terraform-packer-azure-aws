#!/bin/bash
set -x

ami_id="ami-0bb7c13ae5eb2b3ec"




# Launch an EC2 instance with the new AMI
instance_id=$(aws ec2 run-instances \
    --image-id $ami_id \
    --count 1 \
    --instance-type t2.micro \
    --key-name mac-test \
    --security-group-ids sg-059c7b30031c81f0d \
    --subnet-id subnet-085c6713c789edc91 \
    --associate-public-ip-address \
    --query 'Instances[0].InstanceId' \
    --output text)

# Wait for the instance to be in running state
aws ec2 wait instance-running --instance-ids $instance_id

# Get the public DNS of the instance
public_dns=$(aws ec2 describe-instances \
    --instance-ids $instance_id \
    --query 'Reservations[0].Instances[0].PublicDnsName' \
    --output text)

# Run tests via SSH (replace 'test_script.sh' with your actual test script)
ssh -o StrictHostKeyChecking=no -i ~/.ssh/mac-test.pem ec2-user@$public_dns 