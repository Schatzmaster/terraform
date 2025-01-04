# --------------------------------------------------- VARIABLES ---------------------------------------------------

# For vars in detail : page 119 in Terraform Up and Running
variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}