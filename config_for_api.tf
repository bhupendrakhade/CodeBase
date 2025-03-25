provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "vpc_records" {
  name           = "VPCRecords"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_api_gateway_rest_api" "vpc_api" {
  name        = "vpc-api"
  description = "API Gateway for VPC Management"
}

resource "aws_api_gateway_resource" "vpc" {
  rest_api_id = aws_api_gateway_rest_api.vpc_api.id
  parent_id   = aws_api_gateway_rest_api.vpc_api.root_resource_id
  path_part   = "vpc"
}

resource "aws_api_gateway_method" "vpc_post" {
  rest_api_id   = aws_api_gateway_rest_api.vpc_api.id
  resource_id   = aws_api_gateway_resource.vpc.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_lambda_function" "vpc_lambda" {
  function_name    = "vpc_lambda"
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  role            = aws_iam_role.lambda_role.arn
  filename        = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
}

resource "aws_api_gateway_integration" "lambda_vpc" {
  rest_api_id = aws_api_gateway_rest_api.vpc_api.id
  resource_id = aws_api_gateway_resource.vpc.id
  http_method = aws_api_gateway_method.vpc_post.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.vpc_lambda.invoke_arn
}

resource "aws_cognito_user_pool" "user_pool" {
  name = "vpc-auth-pool"
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "vpc-app-client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
}

resource "aws_api_gateway_authorizer" "cognito" {
  name          = "cognito-authorizer"
  rest_api_id   = aws_api_gateway_rest_api.vpc_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy_attachment" "lambda_dynamodb" {
  name       = "lambda_dynamodb_policy"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vpc_lambda.function_name
  principal     = "apigateway.amazonaws.com"
}
