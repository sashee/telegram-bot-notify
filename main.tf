provider "aws" {
}

resource "random_id" "id" {
  byte_length = 8
}

resource "random_id" "random_path" {
  byte_length = 16
}

variable "telegram_token" {
  type      = string
  sensitive = true
}

resource "aws_ssm_parameter" "bot-token" {
  name  = "bot-token"
  type  = "SecureString"
  value = var.telegram_token
}

data "external" "build" {
  program = ["bash", "-c", <<EOT
(make node_modules) >&2 && echo "{\"dest\": \".\"}"
EOT
  ]
  working_dir = "${path.module}/src"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "/tmp/lambda-${random_id.id.hex}.zip"
  source_dir  = "${data.external.build.working_dir}/${data.external.build.result.dest}"
}

resource "aws_sns_topic" "updates" {
}

resource "aws_sns_topic_subscription" "updates" {
  topic_arn = aws_sns_topic.updates.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.updates-lambda.arn
}

resource "aws_lambda_permission" "with_sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.updates-lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.updates.arn
}

output "topic_arn" {
	value = aws_sns_topic.updates.arn
}
