#!/bin/bash

# Variables
INSTANCE_TYPE="t3.medium"          # Instance type
AMI_ID="ami-0866a3c8686eaeeba"    # AMI ID for Amazon Machine Image
KEY_NAME="kube_master_1"          # Dynamic key pair name
TAG_NAME_BASE="kube_master"       # Base name tag for instances

# Fetch default AWS region
echo "Fetching default AWS region..."
DEFAULT_REGION=$(aws configure get region)

if [ -z "$DEFAULT_REGION" ]; then
    echo "Default region is not configured. Set it using 'aws configure set region <region-name>' or export AWS_REGION."
    exit 1
fi
echo "Default region: $DEFAULT_REGION"

# Create Key Pair
echo "Creating a new key pair..."
KEY_FILE="${KEY_NAME}.pem"
aws ec2 create-key-pair \
    --key-name $KEY_NAME \
    --query 'KeyMaterial' \
    --output text > $KEY_FILE

if [ $? -eq 0 ]; then
    chmod 400 $KEY_FILE
    echo "Key pair created successfully: $KEY_FILE"
else
    echo "Failed to create key pair."
    exit 1
fi

# Fetch VPC ID (assuming the first VPC is the default one)
echo "Fetching VPC ID..."
VPC_ID=$(aws ec2 describe-vpcs \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ $? -eq 0 ]; then
    echo "VPC ID fetched successfully: $VPC_ID"
else
    echo "Failed to fetch VPC ID."
    exit 1
fi

# Fetch Subnet ID (using the first available subnet in the VPC)
echo "Fetching Subnet ID..."
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ $? -eq 0 ]; then
    echo "Subnet ID fetched successfully: $SUBNET_ID"
else
    echo "Failed to fetch Subnet ID."
    exit 1
fi

# Configure Storage Volumes (using gp3)
BLOCK_DEVICE_MAPPINGS='[
    {
        "DeviceName": "/dev/xvda",
        "Ebs": {
            "VolumeSize": 10,
            "DeleteOnTermination": true,
            "VolumeType": "gp3"
        }
    },
    {
        "DeviceName": "/dev/xvdb",
        "Ebs": {
            "VolumeSize": 12,
            "DeleteOnTermination": true,
            "VolumeType": "gp3"
        }
    },
    {
        "DeviceName": "/dev/xvdc",
        "Ebs": {
            "VolumeSize": 18,
            "DeleteOnTermination": true,
            "VolumeType": "gp3"
        }
    }
]'

# Create Security Group
echo "Creating security group..."
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name aws_test_sg \
    --description "Security group for SSH, HTTP, HTTPS access" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

if [ $? -eq 0 ]; then
    echo "Security group created successfully. Group ID: $SECURITY_GROUP_ID"
else
    echo "Failed to create security group."
    exit 1
fi

# Add Rules to Security Group
echo "Adding rules to the security group..."
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 22 --cidr 0.0.0.0/0   # SSH
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 80 --cidr 0.0.0.0/0   # HTTP
aws ec2 authorize-security-group-ingress --group-id $SECURITY_GROUP_ID --protocol tcp --port 443 --cidr 0.0.0.0/0  # HTTPS

if [ $? -eq 0 ]; then
    echo "Rules added to the security group successfully."
else
    echo "Failed to add rules to the security group."
    exit 1
fi

# Create EC2 Instances
echo "Creating EC2 instances..."
INSTANCE_IDS=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type $INSTANCE_TYPE \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --subnet-id $SUBNET_ID \
    --block-device-mappings "$BLOCK_DEVICE_MAPPINGS" \
    --count 2 \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${TAG_NAME_BASE}_1},{Key=Name,Value=${TAG_NAME_BASE}_2}]" \
    --query 'Instances[*].InstanceId' \
    --output text)

if [ $? -eq 0 ]; then
    echo "EC2 Instances created successfully. Instance IDs: $INSTANCE_IDS"
else
    echo "Failed to create EC2 instances."
    exit 1
fi

# Retrieve Public IPs
echo "Retrieving public IP addresses of the instances..."
INSTANCE_IDS_ARRAY=($INSTANCE_IDS)
for ID in "${INSTANCE_IDS_ARRAY[@]}"; do
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $ID \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    echo "Instance ID: $ID, Public IP: $PUBLIC_IP"
done
