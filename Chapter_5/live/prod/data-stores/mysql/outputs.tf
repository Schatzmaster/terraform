output "db_address" {
  description = "Connect to db by this endpoint"
  value       = aws_db_instance.example.address
}

output "port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.example.port
}