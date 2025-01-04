provider "aws" {
  region = "us-east-2"
}

# BACKEND

terraform {
  backend "s3" {
    bucket         = "jaspis-terraform-up-and-running-state"
    key            = "stage/service/webserver-cluster/terraform.tfstate"
    region         = "us-east-2"

    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}


# Everything in this code is deployed to the VPC (Virtual Private Cloud) on AWS. Every Account has one. Isolated with
# own IP Address spaces and virtual networks. Page 87 in Terraform Up And Running


#resource "aws_instance" "example" {
#  ami           = "ami-0fb653ca2d3203ac1"
#  instance_type = "t2.micro"
#  vpc_security_group_ids = [aws_security_group.instance.id]
#
## User data: Can pass a shell script or a cloud-init directive and the EC2 instance will execute it on first boot up
#  user_data = <<-EOF
#              #!/bin/bash
#              echo "Hello, World!" > index.html
#              nohup busybox httpd -f -p ${var.server_port} &
#              EOF
#
#  # When change to user 'data', terraform by default will update the parameter 'user_data'. But since user_data just gets
#  # executed on very first boot, the instance needs to be launched again. That happens if 'user_data_replace_on_change' is
#  # set to 'true'
#  user_data_replace_on_change = true
#
#  tags = {
#    Name = "my-first-ec2"
#  }
#}

# --------------------------------------- EC2 INSTANCES ---------------------------------------

# For Auto Scaling (Deploying new servers if traffic goes to high or deleting if needed) use Auto Scaling Group (ASG)
# First step would be creating a launch template (replaces the instance from above)


resource "aws_launch_template" "example" {
  name          = "example-launch-template"
  image_id      = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              echo "Hello, World!" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "example-launch-template"
    }
  }

# # Sets how Terraform destroy and replace. Default: Destroy then create. Right now this launch config can't be destroyed
# # (It's immutable, so if I change it will be replaced whole. This is not possible, because autoscaling group refers to
# # it in its config). Lifecycle block can change this.
  lifecycle {
    create_before_destroy = true
  }
}

# Now, I can create ASG itself. Each tagged with name 'terraform-asg-example'. Another parameter I have to add is subnet_ids.
# This specifies the VPC subnets the EC2 instances should be deployed. More on page 113.

resource "aws_autoscaling_group" "example" {
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  max_size = 10
  min_size = 2

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "terraform-asg-example"
  }

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }
}

#--------------------------------------------- LOAD BALANCER ---------------------------------------------

# To get a single IP address that clients can use (instead of multiple for each of the servers) I need to set up a Load Balancer.
# Distributes requests to the EC2s. I use an Application Load Balancer (ALB, Layer 7, takes http and https)

resource "aws_alb" "Application_Load_Balancer" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

# Define listener for ALB. Listens for protocol on given port

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.Application_Load_Balancer.arn
  port = 80
  protocol = "HTTP"

  # By default, return a simple 404 page, if no requests match any listener rules
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}



# Next I need to create a target group for my ASG

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}
# To tie everything up, I need to set up listeners rules for my ALB

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

# --------------------------------------------- SECURITY GROUPS ---------------------------------------------

# By default AWS does not allow any incoming or outgoing traffic from an EC2 instance. To allow this, I need to set up
# a security group resource

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Stands for all ip addresses.
  }
}

# By default AWS does not allow any incoming or outgoing traffic for all resources. So I need to set up a specific.
# security group for ALB.

resource aws_security_group "alb" {
  name = "terraform-example-alb"

  # Allow HTTP requests to access ALB.
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound requests, so ALB can perform health checks.
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------------------------------- DATA SOURCES ---------------------------------------------------

# Data sources represent a piece of read only information. They are received from the provider. It's a way to query the
# providers API and make the data available to Terraform. The parameters are essentially filters. Default must be true
# to receive the data

data "aws_vpc" "default" {
  default = true
}

# To get the data out of data source: data.<PROVIDER>_<TYPE>.<NAME>.<ATTRIBUTE>
# Example to get ID pof the VPC: data.aws_vpc.default.id. Can be combined with other data sources

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}





