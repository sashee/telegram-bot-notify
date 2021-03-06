resource "random_id" "start_token" {
  byte_length = 16
}

resource "aws_lambda_function" "control-lambda" {
  function_name = "${random_id.id.hex}-control-function"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      domain            = aws_apigatewayv2_api.api.api_endpoint
      path_key          = random_id.random_path.hex
      token_parameter   = aws_ssm_parameter.bot-token.name
      subscribers_table = aws_dynamodb_table.subscribers.name,
      start_token       = random_id.start_token.b64_url
    }
  }

  timeout = 30
  handler = "telegram-control.handler"
  runtime = "nodejs14.x"
  role    = aws_iam_role.control-lambda_exec.arn
}

data "aws_lambda_invocation" "set_webhook" {
  function_name = aws_lambda_function.control-lambda.function_name

  input = <<JSON
{
	"setWebhook": true
}
JSON
}

data "aws_iam_policy_document" "control-lambda_exec_role_policy" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }
  statement {
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      aws_ssm_parameter.bot-token.arn
    ]
  }
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:DeleteItem",
      "dynamodb:PutItem",
    ]
    resources = [
      aws_dynamodb_table.subscribers.arn,
    ]
  }
}

resource "aws_cloudwatch_log_group" "control-loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.control-lambda.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "control-lambda_exec_role" {
  role   = aws_iam_role.control-lambda_exec.id
  policy = data.aws_iam_policy_document.control-lambda_exec_role_policy.json
}

resource "aws_iam_role" "control-lambda_exec" {
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

# api gw

resource "aws_apigatewayv2_api" "api" {
  name          = "api-${random_id.id.hex}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id           = aws_apigatewayv2_api.api.id
  integration_type = "AWS_PROXY"

  integration_method     = "POST"
  integration_uri        = aws_lambda_function.control-lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /${random_id.random_path.hex}/{proxy+}"

  target = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_stage" "api" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.control-lambda.arn
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

