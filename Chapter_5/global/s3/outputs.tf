# Some output variables to display the action behind the scenes
output "s3_bucket_arn" {
  description = "The Amazon Resource Name (ARN) of the S3 bucket"
  value       = aws_s3_bucket.terraform-state.arn
}

output "dynamodb_table_name" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "dynamodb_table_arn" {
  description = "The name of the DynamoDB table"
  value       = aws_dynamodb_table.terraform_locks.arn
}