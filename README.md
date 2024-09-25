# Terraform Infrastructure Setup
This Terraform configuration sets up the necessary infrastructure for building images with Packer on both AWS and Azure. It includes modules for AWS and Azure, allowing you to manage resources across both cloud providers.

## Table of Contents

- [Terraform Infrastructure Setup](#terraform-infrastructure-setup)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [Directory Structure](#directory-structure)
  - [Usage Instructions](#usage-instructions)
    - [Initializing Terraform](#initializing-terraform)
    - [Planning the Deployment](#planning-the-deployment)
    - [Applying the Configuration](#applying-the-configuration)
    - [Running Only the AWS Module](#running-only-the-aws-module)
  - [Variables and Outputs](#variables-and-outputs)
    - [Variables](#variables)
    - [Outputs](#outputs)
  - [Authentication](#authentication)
    - [AWS Authentication](#aws-authentication)
    - [Azure Authentication](#azure-authentication)
  - [State Management](#state-management)
  - [Cleaning Up](#cleaning-up)
  - [License](#license)

## Overview

This Terraform project is designed to provision infrastructure on AWS and Azure required for Packer to build images. It includes:

- **AWS Module**: Sets up a VPC, subnet, Internet Gateway, route table, and security group allowing SSH access from your public IP.
- **Azure Module**: Creates a Resource Group, Virtual Network, Subnet, and Network Security Group with SSH access from your public IP.

## Prerequisites

- **Terraform**: Install Terraform version 0.12 or higher. Download from [https://www.terraform.io/downloads.html](https://www.terraform.io/downloads.html).
- **AWS Account**: An AWS account with permissions to create VPCs, subnets, security groups, etc.
- **Azure Account**: An Azure subscription with permissions to create resource groups, VNets, NSGs, etc.
- **AWS Credentials**: Configure AWS CLI or set environment variables for authentication.
- **Azure Credentials**: Set up Azure authentication using the Azure CLI or service principal.
- **Internet Access**: Required to retrieve your public IP and for Packer to access necessary resources.

## Directory Structure

The project is structured as follows:

```
terraform/
├── main.tf            # Root module
├── variables.tf       # Root variables
├── outputs.tf         # Root outputs
├── modules/
        ├── aws/
        │   ├── main.tf
        │   ├── variables.tf
        │   └── outputs.tf
        └── azure/
                ├── main.tf
                ├── variables.tf
                └── outputs.tf
```

- **main.tf**: The root module that calls the AWS and Azure modules.
- **modules/aws**: Contains Terraform code for AWS infrastructure.
- **modules/azure**: Contains Terraform code for Azure infrastructure.

## Usage Instructions

### Initializing Terraform

Navigate to the `terraform` directory and initialize Terraform:

```bash
cd terraform
terraform init
```

This command will download the necessary provider plugins for AWS and Azure.

### Planning the Deployment

Before applying changes, you can see what Terraform will create:

```bash
terraform plan
```

This will display the resources that will be created, modified, or destroyed.

### Applying the Configuration

To apply the configuration and create the resources:

```bash
terraform apply
```

Terraform will prompt for confirmation. Type `yes` to proceed.

### Running Only the AWS Module

If you want to run only the AWS module and not the Azure module, you can use the `-target` option with Terraform to target specific resources.

**Option 1: Using `-target`**

```bash
terraform apply -target=module.aws_infrastructure
```

This command tells Terraform to apply only the resources within the `module.aws_infrastructure`.

**Option 2: Comment Out Azure Module**

Alternatively, you can comment out the Azure module block in `main.tf`:

```hcl
# Comment out the Azure module
# module "azure_infrastructure" {
#   source = "./modules/azure"
#   location = var.azure_location
# }
```

Then run:

```bash
terraform apply
```

**Note**: Remember to uncomment the Azure module when you need to run it again.

## Variables and Outputs

### Variables

Variables are defined in `variables.tf` files in both the root module and submodules.

- **AWS Variables**:

    - `aws_region`: AWS region to deploy resources (default: `us-east-1`).

- **Azure Variables**:

    - `azure_location`: Azure region to deploy resources (default: `East US`).

You can override default variable values by providing them via command-line options or a `terraform.tfvars` file.

**Example**:

```bash
terraform apply -var="aws_region=us-west-2"
```

### Outputs

After applying, Terraform will output resource IDs and names that you can use in your Packer configuration.

- **AWS Outputs**:

    - `aws_subnet_id`
    - `aws_security_group_id`
    - `aws_vpc_id`

- **Azure Outputs**:

    - `azure_subnet_name`
    - `azure_virtual_network_name`
    - `azure_resource_group_name`
    - `azure_location`

## Authentication

### AWS Authentication

Ensure that your AWS credentials are configured. You can authenticate using:

- **Environment Variables**:

    ```bash
    export AWS_ACCESS_KEY_ID="your-access-key-id"
    export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
    ```

- **AWS CLI Configuration**:

    Run `aws configure` to set up your credentials.

### Azure Authentication

Authenticate with Azure using one of the following methods:

- **Azure CLI Authentication**:

    ```bash
    az login
    ```

- **Service Principal Authentication**:

    Set the following environment variables:

    ```bash
    export ARM_CLIENT_ID="your-service-principal-appid"
    export ARM_CLIENT_SECRET="your-service-principal-password"
    export ARM_SUBSCRIPTION_ID="your-subscription-id"
    export ARM_TENANT_ID="your-tenant-id"
    ```

## State Management

By default, Terraform stores the state file locally in `terraform.tfstate`. If you are working in a team or want to store the state file remotely, consider using a remote backend like AWS S3 or Azure Storage.

## Cleaning Up

To destroy the resources created by Terraform:

```bash
terraform destroy
```

Terraform will prompt for confirmation. Type `yes` to proceed.

**Note**: If you used `-target` to apply only the AWS module, you should also target it when destroying:

```bash
terraform destroy -target=module.aws_infrastructure
```

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.
