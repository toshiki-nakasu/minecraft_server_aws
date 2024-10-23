# ----------------------------------------
# 可変パラメータ
# ----------------------------------------
locals {
  PUBLIC_KEY_PATH = "../pem/ec2_key.pub"
  EC2_DOMAIN_NAME = "${var.SERVER_NAME}.${var.DOMAIN_NAME}"
}


# ----------------------------------------
# 基本環境の設定
# ----------------------------------------
module "vpc" {
  source                  = "terraform-aws-modules/vpc/aws"
  name                    = "${var.SERVER_NAME}_vpc_ec2"
  cidr                    = "10.0.0.0/16"
  azs                     = ["ap-northeast-1a"]
  public_subnets          = ["10.0.1.0/24"]
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = true
}


# ----------------------------------------
# インスタンス構築
# ----------------------------------------
data "aws_iam_policy_document" "instance_policy" {
  version = "2012-10-17"
  statement {
    sid    = ""
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]
    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com",
      ]
    }
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
# 存在しないのに「already exists」と言われたらコレ↓
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
  # ingress {
  #   description = "${var.SERVER_NAME}_bluemap"
  #   from_port   = 8100
  #   to_port     = 8100
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }
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

resource "aws_key_pair" "ec2_key" {
  key_name   = "ec2_key"
  public_key = file(local.PUBLIC_KEY_PATH)
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = [var.EC2_VOLUME_IMAGE]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "instance_setup" {
  template = file("./shell/instance_setup.sh")
  vars = {
    docker_compose_version = var.DOCKER_COMPOSE_VERSION
  }
}

resource "aws_instance" "minecraft" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.INSTANCE_TYPE
  vpc_security_group_ids      = [aws_security_group.server.id]
  subnet_id                   = module.vpc.public_subnets[0]
  key_name                    = aws_key_pair.ec2_key.id
  associate_public_ip_address = true
  disable_api_termination     = true
  iam_instance_profile        = aws_iam_instance_profile.instance_role.id
  user_data                   = data.template_file.instance_setup.rendered
  tags = {
    Name     = var.SERVER_NAME
    AutoStop = "true"
  }
  root_block_device {
    volume_size           = 80
    delete_on_termination = false
  }
  credit_specification {
    cpu_credits = "standard"
  }
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name                = "cpu_utilization"
  comparison_operator       = "GreaterThanOrEqualToThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "120" #seconds
  statistic                 = "Average"
  threshold                 = "80"
  alarm_description         = "This metric monitors ec2 cpu utilization"
  insufficient_data_actions = []
  dimensions = {
    InstanceId = aws_instance.minecraft.id
  }
}


# ----------------------------------------
# サブドメインでIP指定
# ----------------------------------------
data "aws_route53_zone" "host_domain" {
  name         = var.DOMAIN_NAME
  private_zone = false
}

resource "aws_route53_zone" "minecraft_domain" {
  name = local.EC2_DOMAIN_NAME
}

resource "aws_route53_record" "subdomain_route" {
  zone_id = aws_route53_zone.minecraft_domain.zone_id
  name    = local.EC2_DOMAIN_NAME
  type    = "A"
  ttl     = 300
  records = [
    aws_instance.minecraft.public_ip,
  ]
}

resource "aws_route53_record" "ns_record" {
  zone_id = data.aws_route53_zone.host_domain.zone_id
  name    = local.EC2_DOMAIN_NAME
  type    = "NS"
  ttl     = 172800
  records = aws_route53_zone.minecraft_domain.name_servers
}


# ----------------------------------------
# EC2インスタンスの停止/再起動
# ----------------------------------------
data "aws_iam_policy_document" "instance_role_policy" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:*",
      "ssm:*",
    ]
    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:Get*",
      "route53:List*",
    ]
    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "*",
    ]
  }
}

data "aws_iam_policy_document" "assume_lambda_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "control_ec2_instance" {
  name               = "control_ec2_instance"
  path               = "/system/"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_role_policy.json
  inline_policy {
    name   = "instance_role_policy"
    policy = data.aws_iam_policy_document.instance_role_policy.json
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "instance_role_policy"
  policy = data.aws_iam_policy_document.instance_role_policy.json
}

resource "aws_iam_policy_attachment" "lambda_iam_attach" {
  name       = "lambda_iam_attachment"
  policy_arn = aws_iam_policy.lambda_policy.arn
  roles = [
    aws_iam_role.control_ec2_instance.name,
  ]
}

data "archive_file" "lambda_control_ec2_instance" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_control_ec2_instance.py"
  output_path = "lambda_control_ec2_instance.zip"
}

resource "aws_lambda_function" "control_ec2_instance" {
  function_name    = "control_ec2_instance"
  handler          = "lambda_control_ec2_instance.lambda_handler"
  role             = aws_iam_role.control_ec2_instance.arn
  filename         = data.archive_file.lambda_control_ec2_instance.output_path
  source_code_hash = data.archive_file.lambda_control_ec2_instance.output_base64sha256
  runtime          = "python3.9"
  timeout          = 600 # seconds
  environment {
    variables = {
      "REGION"                = var.REGION
      "INSTANCE_ID"           = aws_instance.minecraft.id
      "HOST_NAME"             = local.EC2_DOMAIN_NAME
      "HOSTED_ZONE_ID"        = aws_route53_zone.minecraft_domain.zone_id
      "SERVER_CONTAINER_NAME" = var.SERVER_CONTAINER_NAME
      "BACKUP_CONTAINER_NAME" = var.BACKUP_CONTAINER_NAME
    }
  }
}

resource "aws_cloudwatch_log_group" "control_ec2_instance_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.control_ec2_instance.function_name}"
  retention_in_days = 3
  skip_destroy      = false
}

resource "aws_cloudwatch_event_rule" "dayry_stop" {
  name                = "dayry_stop"
  schedule_expression = "cron(0 19 * * ? *)"
}

resource "aws_cloudwatch_event_target" "dayry_stop" {
  target_id = "dayry_stop"
  rule      = aws_cloudwatch_event_rule.dayry_stop.name
  arn       = aws_lambda_function.control_ec2_instance.arn
  input = jsonencode({
    "Action" : "Stop"
  })
}

resource "aws_lambda_permission" "dayry_stop" {
  statement_id  = "AllowExecutionFromCloudWatch_stop"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control_ec2_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dayry_stop.arn
}


resource "aws_cloudwatch_event_rule" "dayry_start" {
  # 5分前を指定
  name                = "dayry_start"
  schedule_expression = "cron(55 2 * * ? *)"
}

resource "aws_cloudwatch_event_target" "dayry_start" {
  target_id = "dayry_start"
  rule      = aws_cloudwatch_event_rule.dayry_start.name
  arn       = aws_lambda_function.control_ec2_instance.arn
  input = jsonencode({
    "Action" : "Start"
  })
}

resource "aws_lambda_permission" "dayry_start" {
  statement_id  = "AllowExecutionFromCloudWatch_start"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control_ec2_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dayry_start.arn
}
