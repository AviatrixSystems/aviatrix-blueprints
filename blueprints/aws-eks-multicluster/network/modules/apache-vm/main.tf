terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}

resource "aws_security_group" "allow_all_private_db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Allow private traffic to ${var.name_prefix} database"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }
  ingress {
    description     = "SSH from EC2 Instance Connect Endpoint"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = var.eice_security_group_ids
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

data "aws_ami" "amzn-linux-2023-ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "~> 2.1"

  key_name           = "${var.name_prefix}-db-key"
  create_private_key = true
}

## Deploy Linux Test Hosts in VPC1, All AZs running Gatus for connectivity testing
module "db_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.1"

  name = "${var.name_prefix}-db"

  ami                         = data.aws_ami.amzn-linux-2023-ami.image_id
  instance_type               = "t3.micro"
  key_name                    = module.key_pair.key_pair_name
  monitoring                  = true
  vpc_security_group_ids      = [aws_security_group.allow_all_private_db.id]
  subnet_id                   = var.subnet_id
  user_data                   = file("${path.module}/init.sh")
  user_data_replace_on_change = true
  ignore_ami_changes          = true

}

output "vm_private_ip" {
  value = module.db_instance.private_ip
}