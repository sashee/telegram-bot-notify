resource "aws_dynamodb_table" "subscribers" {
  name         = "Subscribers-${random_id.id.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "chat_id"

  attribute {
    name = "chat_id"
    type = "S"
  }
}
