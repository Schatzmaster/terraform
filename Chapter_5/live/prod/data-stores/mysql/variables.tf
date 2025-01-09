# --------- REQUIRED PARAMETERS  ---------

variable "db_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Username for the database"
  type        = string
  sensitive   = true
}

# --------- OPTIONAL PARAMETERS  ---------

variable "db_name" {
  description = "Name of the database"
  default     = "prod-example-database"
}