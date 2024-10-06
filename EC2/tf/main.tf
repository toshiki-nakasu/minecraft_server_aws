# 可変パラメータ
locals {
  PUBLIC_KEY_PATH = "../pem/ec2_key.pub"
  EC2_DOMAIN_NAME = "${var.SERVER_NAME}.${var.DOMAIN_NAME}"
}

# 基本環境の設定
provider "aws" {
  region = var.REGION
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "${var.SERVER_NAME}_vpc_ec2"
  cidr   = "10.0.0.0/16"
  azs    = ["ap-northeast-1a"]
  # azs            = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  public_subnets = ["10.0.1.0/24"]
  # public_subnets = ["10.0.1.0/24", "10.0.3.0/24", "10.0.4.0/24"]
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true
}

data "aws_iam_policy_document" "instance_policy" {
  version = "2012-10-17"
  statement {
    sid = ""
    actions = [
      "sts:AssumeRole",
    ]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    effect = "Allow"
  }
}

resource "aws_iam_role" "instance_role" {
  name               = "instance_role"
  assume_role_policy = data.aws_iam_policy_document.instance_policy.json
}

resource "aws_iam_instance_profile" "instance_role" {
  name = "sgw_instance_role"
  role = aws_iam_role.instance_role.name
}
# 存在しないのに「already exists」と言われたらコレ
# aws iam delete-instance-profile --instance-profile-name <profile-name>

resource "aws_security_group" "server" {
  name        = var.SERVER_NAME
  description = var.SERVER_NAME
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "${var.SERVER_NAME}_bedrock_ipv4"
    from_port   = 19132
    to_port     = 19132
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "${var.SERVER_NAME}_bedrock_ipv6"
    from_port   = 19133
    to_port     = 19133
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "${var.SERVER_NAME}_java"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "${var.SERVER_NAME}_mcrcon"
    from_port   = 25575
    to_port     = 25575
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/aws/ec2/${var.SERVER_NAME}"
  retention_in_days = 3
}

resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2_key"
  public_key = file(local.PUBLIC_KEY_PATH)
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.EC2_VOLUME_IMAGE]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.INSTANCE_TYPE
  vpc_security_group_ids      = [aws_security_group.server.id]
  subnet_id                   = module.vpc.public_subnets[0]
  key_name                    = aws_key_pair.ec2_key.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.instance_role.id
  root_block_device {
    volume_size = 15
  }
  user_data = <<-EOF
    #!/bin/bash
    # Install docker-compose
    sudo apt update -y
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update -y
    sudo apt -y install docker-ce docker-ce-cli containerd.io
    sudo gpasswd -a ubuntu docker
    sudo -i
    curl -L "https://github.com/docker/compose/releases/download/${var.DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  EOF
  tags = {
    Name = var.SERVER_NAME
  }
}

# サブドメインでIP指定
data "aws_route53_zone" "host_domain" {
  name         = var.DOMAIN_NAME
  private_zone = false
}

resource "aws_route53_record" "ns_record" {
  zone_id = data.aws_route53_zone.host_domain.zone_id
  name    = local.EC2_DOMAIN_NAME
  type    = "NS"
  ttl     = 172800
  records = data.aws_route53_zone.host_domain.name_servers
}

resource "aws_route53_record" "subdomain_route" {
  zone_id = data.aws_route53_zone.host_domain.zone_id
  name    = local.EC2_DOMAIN_NAME
  type    = "A"
  ttl     = 300
  records = [
    aws_instance.minecraft.public_ip
  ]
}
