provider "aws" {
  region = "us-east-1"
}

locals {
  function_name = "example-lambda"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_secretsmanager_secret" "binance_api_keys" {
  name = "binance-api-keys"
}

resource "aws_secretsmanager_secret_version" "binance_api_keys_version" {
  secret_id = aws_secretsmanager_secret.binance_api_keys.id

  secret_string = jsonencode({
    BINANCE_API_KEY    = "placeholder"
    BINANCE_SECRET_KEY = "placeholder"
  })
}

resource "aws_iam_policy" "lambda_secrets_manager_access" {
  name        = "lambda-secrets-manager-access"
  description = "Allow Lambda function to access Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.binance_api_keys.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_manager_access" {
  policy_arn = aws_iam_policy.lambda_secrets_manager_access.arn
  role       = aws_iam_role.lambda_role.name
}


resource "aws_lambda_function" "example_lambda" {
  function_name = local.function_name

  filename      = "../lambda_function_payload.zip"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs14.x"

  source_code_hash = filebase64sha256("../lambda_function_payload.zip")

  tags = {
    Terraform = "true"
  }
}

resource "aws_api_gateway_rest_api" "example_api" {
  name        = "example-api"
  description = "Example API for Lambda function"
}

resource "aws_api_gateway_resource" "example_resource" {
  rest_api_id = aws_api_gateway_rest_api.example_api.id
  parent_id   = aws_api_gateway_rest_api.example_api.root_resource_id
  path_part   = "example"
}

resource "aws_api_gateway_method" "example_method" {
  rest_api_id   = aws_api_gateway_rest_api.example_api.id
  resource_id   = aws_api_gateway_resource.example_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "example_integration" {
  rest_api_id             = aws_api_gateway_rest_api.example_api.id
  resource_id             = aws_api_gateway_resource.example_resource.id
  http_method             = aws_api_gateway_method.example_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.example_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "example_deployment" {
  depends_on = [
    aws_api_gateway_integration.example_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.example_api.id
  stage_name  = "prod"
}

resource "aws_lambda_permission" "example_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.example_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.example_api.execution_arn}/*/*"
}
