# 可変パラメータ
locals {
  DOMAIN_NAME       = "tosix13.com"
  REGION            = "ap-northeast-1"
  TASK_CPU          = "4096"
  TASK_MEMORY       = "8192"
  TASK_IMAGE_BASE   = "itzg/minecraft-server"
  TASK_IMAGE_TAG    = "java20"
  MINECRAFT_VERSION = "1.20.1"
}

# 基本環境の設定
provider "aws" {
  region = local.REGION
}

module "vpc" {
  source         = "terraform-aws-modules/vpc/aws"
  name           = "minecraft_vpc"
  cidr           = "10.0.0.0/16"
  azs            = ["ap-northeast-1a"]
  public_subnets = ["10.0.1.0/24"]
  # azs            = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]
  # public_subnets = ["10.0.1.0/24", "10.0.3.0/24", "10.0.4.0/24"]
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# 動的IPのドメイン名解決 (まだできてない)
resource "aws_service_discovery_public_dns_namespace" "dns" {
  name = "dns.tosix13.com"
}

resource "aws_service_discovery_service" "minecraft_server" {
  name = "minecraft"
  dns_config {
    namespace_id = aws_service_discovery_public_dns_namespace.dns.id
    dns_records {
      ttl  = 30
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  health_check_custom_config {
    failure_threshold = 1
  }
}

# ECS
resource "aws_security_group" "efs" {
  name        = "efs-sg"
  description = "for EFS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.0.0/16"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token = "minecraft_data"
}

resource "aws_efs_mount_target" "minecraft_data" {

  file_system_id = aws_efs_file_system.efs.id
  subnet_id      = module.vpc.public_subnets[0]
  security_groups = [
    aws_security_group.efs.id
  ]
}

resource "aws_efs_backup_policy" "policy" {
  file_system_id = aws_efs_file_system.efs.id

  backup_policy {
    status = "ENABLED"
  }
}

resource "aws_ecs_cluster" "minecraft_server" {
  name = "minecraft_server"
}

resource "aws_security_group" "minecraft_server" {
  name        = "minecraft_server"
  description = "minecraft_server"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "minecraft_server"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
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

resource "aws_cloudwatch_log_group" "minecraft_server" {
  name              = "/aws/ecs/container/minecraft_server"
  retention_in_days = 3
}

resource "aws_ecs_task_definition" "minecraft_server" {
  cpu                      = local.TASK_CPU
  memory                   = local.TASK_MEMORY
  family                   = "minecraft_server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_tasks_execution_role.arn
  container_definitions = jsonencode([
    {
      name       = "minecraft_server"
      image      = "${local.TASK_IMAGE_BASE}:${local.TASK_IMAGE_TAG}"
      essential  = true
      tty        = true
      stdin_open = true
      restart    = "unless-stopped"
      portMappings = [
        {
          containerPort = 25565
          hostPort      = 25565
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "EULA"
          value = "TRUE"
        },
        {
          name : "VERSION",
          value : local.MINECRAFT_VERSION
        }
      ]
      mountPoints = [
        {
          containerPath = "/data"
          sourceVolume  = "minecraft_data"
        }
      ]
      HealthCheck = {
        Command = [
          "CMD-SHELL",
          "exit 0"
        ],
        Interval = 30
        Timeout  = 2
        Retries  = 3
      },
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-region        = "ap-northeast-1",
          awslogs-stream-prefix = "minecraft_server",
          awslogs-group         = aws_cloudwatch_log_group.minecraft_server.name
        }
      },
    }
  ])
  volume {
    name = "minecraft_data"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.efs.id
    }
  }
}

resource "aws_ecs_service" "minecraft_server" {
  name                   = "minecraft_server"
  cluster                = aws_ecs_cluster.minecraft_server.id
  task_definition        = aws_ecs_task_definition.minecraft_server.arn
  enable_execute_command = true
  desired_count          = 1
  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.minecraft_server.id]
    assign_public_ip = true
  }
  launch_type = "FARGATE"
  service_registries {
    registry_arn = aws_service_discovery_service.minecraft_server.arn
  }
}

data "aws_iam_policy_document" "ecs_tasks_execution_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_tasks_execution_role" {
  name               = "ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_execution_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_tasks_execution_role" {
  role       = aws_iam_role.ecs_tasks_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 実行タスクを変更する設定
resource "aws_cloudwatch_log_group" "desiredCnt" {
  name              = "/aws/lambda/change_desiredCnt"
  retention_in_days = 1
}

resource "aws_iam_role" "change_desiredCnt" {
  name = "change_desiredCnt"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
  inline_policy {
    name = "policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "ecs:DescribeServices",
            "ecs:UpdateService",
          ]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
          Effect   = "Allow"
          Resource = "${aws_cloudwatch_log_group.desiredCnt.arn}:*"
        }
      ]
    })
  }
}

data "archive_file" "lambda_change_desiredCnt" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_change_desiredCnt.py"
  output_path = "change_desiredCnt.zip"
}

resource "aws_lambda_function" "start_servicetask" {
  function_name    = "start_servicetask"
  handler          = "lambda_change_desiredCnt.start_service_task"
  memory_size      = 128
  role             = aws_iam_role.change_desiredCnt.arn
  filename         = data.archive_file.lambda_change_desiredCnt.output_path
  source_code_hash = data.archive_file.lambda_change_desiredCnt.output_base64sha256
  runtime          = "python3.9"
  timeout          = 10
  environment {
    variables = {
      "cluster" = aws_ecs_cluster.minecraft_server.id
      "service" = aws_ecs_service.minecraft_server.id
    }
  }
  depends_on = [aws_cloudwatch_log_group.desiredCnt]
}

resource "aws_lambda_function" "stop_servicetask" {
  function_name    = "stop_servicetask"
  handler          = "lambda_change_desiredCnt.stop_service_task"
  memory_size      = 128
  role             = aws_iam_role.change_desiredCnt.arn
  filename         = data.archive_file.lambda_change_desiredCnt.output_path
  source_code_hash = data.archive_file.lambda_change_desiredCnt.output_base64sha256
  runtime          = "python3.9"
  timeout          = 10
  environment {
    variables = {
      "cluster" = aws_ecs_cluster.minecraft_server.id
      "service" = aws_ecs_service.minecraft_server.id
    }
  }
  depends_on = [aws_cloudwatch_log_group.desiredCnt]
}

# APIトリガーの設定
resource "aws_apigatewayv2_api" "apigateway" {
  name          = "myAPIGateway"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "apiGatewayLG" {
  name              = "/aws/apigateway/myAPIGateway"
  retention_in_days = 1
}

resource "aws_apigatewayv2_stage" "main" {
  name        = "stage1"
  api_id      = aws_apigatewayv2_api.apigateway.id
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apiGatewayLG.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errMsg         = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_integration" "start_integration" {
  api_id             = aws_apigatewayv2_api.apigateway.id
  connection_type    = "INTERNET"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.start_servicetask.invoke_arn
  integration_type   = "AWS_PROXY"
}

resource "aws_apigatewayv2_integration" "stop_integration" {
  api_id             = aws_apigatewayv2_api.apigateway.id
  connection_type    = "INTERNET"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.stop_servicetask.invoke_arn
  integration_type   = "AWS_PROXY"
}

resource "aws_apigatewayv2_route" "route1" {
  api_id    = aws_apigatewayv2_api.apigateway.id
  route_key = "GET /start"
  target    = "integrations/${aws_apigatewayv2_integration.start_integration.id}"
}

resource "aws_apigatewayv2_route" "route2" {
  api_id    = aws_apigatewayv2_api.apigateway.id
  route_key = "GET /stop"
  target    = "integrations/${aws_apigatewayv2_integration.stop_integration.id}"
}

# APIGatewayにLambda関数へのアクセスを許可
resource "aws_lambda_permission" "start_servicetask" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_servicetask.function_name
  principal     = "apigateway.amazonaws.com"
}

resource "aws_lambda_permission" "stop_servicetask" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_servicetask.function_name
  principal     = "apigateway.amazonaws.com"
}
