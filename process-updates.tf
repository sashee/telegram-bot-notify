resource "aws_lambda_function" "updates-lambda" {
  function_name = "${random_id.id.hex}-updates-function"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      token_parameter = aws_ssm_parameter.bot-token.name
			subscribers_table = aws_dynamodb_table.subscribers.name,
    }
  }

  timeout = 30
  handler = "process-updates.handler"
  runtime = "nodejs14.x"
  role    = aws_iam_role.updates-lambda_exec.arn
}

data "aws_iam_policy_document" "updates-lambda_exec_role_policy" {
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
      "dynamodb:Scan",
    ]
    resources = [
			aws_dynamodb_table.subscribers.arn,
    ]
  }
}

resource "aws_cloudwatch_log_group" "updates-loggroup" {
  name              = "/aws/lambda/${aws_lambda_function.updates-lambda.function_name}"
  retention_in_days = 14
}

resource "aws_iam_role_policy" "updates-lambda_exec_role" {
  role   = aws_iam_role.updates-lambda_exec.id
  policy = data.aws_iam_policy_document.updates-lambda_exec_role_policy.json
}

resource "aws_iam_role" "updates-lambda_exec" {
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
