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
  name        = "allow_all_private_ccdb"
  description = "allow_all_private_ccdb"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/8"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_all_private"
  }
}

# resource "aws_instance" "cc-db" {
#   ami             = "ami-07d9b9ddc6cd8dd30" 
#   instance_type   = "t2.micro"
#   key_name        = "cc-db-key"
#   subnet_id       = var.subnet_id
#   security_groups = [aws_security_group.allow_all_private_db.id]

#   user_data = <<-EOF
#   #!/bin/bash
#   echo "*** Installing apache2"
#   sudo apt update -y
#   sudo apt install apache2 -y
#   echo "*** Completed Installing apache2"
#   EOF

#   tags = {
#     Name = "cc-db"
#   }

#   volume_tags = {
#     Name = "web_instance"
#   } 
# }

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

  key_name           = "k8s-dcf-demo"
  create_private_key = true
}

## Deploy Linux Test Hosts in VPC1, All AZs running Gatus for connectivity testing
module "db_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.1"

  name = "cc-db"

  ami                         = data.aws_ami.amzn-linux-2023-ami.image_id
  instance_type               = "t3.micro"
  key_name                    = "avtx-cmchenry-aws-useast2"
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