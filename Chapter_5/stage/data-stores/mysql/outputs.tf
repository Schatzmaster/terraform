output "db_address" {
  value       = aws_db_instance.example.address
  description = "Connect to DB at this endpoint"
}

output "port" {
  value       = aws_db_instance.example.port
  description = "The port the database is listening on"
}