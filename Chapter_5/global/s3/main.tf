provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "terraform-state" {
  bucket            = "jaspis-terraform-up-and-running-state"

  # Prevent accidental deletion of S3 bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so you can see the full revision history of your state files
resource "aws_s3_bucket_versioning" "enabled" {
  bucket   = aws_s3_bucket.terraform-state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption by default
resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket            = aws_s3_bucket.terraform-state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Explicitly block all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.terraform-state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Setting up a dynamodb to display state locks. If terraform is doing plan or apply, the table gets an entry 'locked'
# So no one else can change the state file
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-up-and-running-locks"
  hash_key     = "LockID" # This sets the primary key
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Now I have a S3 bucket, but Terraform still stores the state locally. To configure TF to store state in S3, I need to
# add a 'backend' configuration. As its for TF itself I need a 'terraform' block. That has this syntax:
#
# terraform {
#    backend "<BACKEND_NAME>" {
#      [CONFIG...]
#    }
# }

terraform {
  backend "s3" {
    bucket         = "jaspis-terraform-up-and-running-state"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-2"

    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}

