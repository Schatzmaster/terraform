# BACKEND

#terraform {
#  backend "s3" {
#    bucket         = "jaspis-terraform-up-and-running-state"
#    key            = "stage/service/webserver-cluster/terraform.tfstate"
#    region         = "us-east-2"
#
#    dynamodb_table = "terraform-up-and-running-locks"
#    encrypt        = true
#  }
#}

# LOCALS

locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"] # Stands for all ip addresses
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

# ------------------------------------------------ EC2 INSTANCES ------------------------------------------------

# For Auto Scaling (Deploying new servers if traffic goes to high or deleting if needed) use Auto Scaling Group (ASG)
# First step would be creating a launch template (replaces the instance from above)


resource "aws_launch_template" "example" {
  name          = "${var.cluster_name}-example-launch-template"
  image_id      = "ami-0fb653ca2d3203ac1"
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.instance.id]
# This user data script is getting longer and longer. To externalize this, I can use tf templatefile function. Page 190.
# The templatefile function takes the relative path. This relativ path is relativ to the current working directory. So,
# that works only if I run 'terraform apply' in the same directory where I call the templatefile function
#  (so I have to run apply in the module main.tf file).
# I can solve this by using a 'path reference' which is of form of path.<TYPE> (p. 218)
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.db_address
    db_port     = data.terraform_remote_state.db.outputs.port
  } ))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.cluster_name}-example-launch-template"
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

  max_size = var.max_size
  min_size = var.max_size

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "${var.cluster_name}-terraform-asg-example"
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
  name = "${var.cluster_name}-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

# Define listener for ALB. Listens for protocol on given port

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_alb.Application_Load_Balancer.arn
  port = local.http_port
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
  name = "${var.cluster_name}-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/index.html"
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
  name = "${var.cluster_name}-instance"
}

resource "aws_security_group_rule" "https-inbound" {
  type = "ingress"
  security_group_id = aws_security_group.instance.id

  from_port         = var.server_port
  protocol          = local.tcp_protocol
  to_port           = var.server_port
  cidr_blocks       = local.all_ips
}

resource "aws_security_group_rule" "https-inbound-alb" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port         = var.server_port
  protocol          = local.tcp_protocol
  to_port           = var.server_port
  cidr_blocks       = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.instance.id

  from_port         = local.any_port
  protocol          = local.any_protocol
  to_port           = local.any_port
  cidr_blocks       = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound_alb" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port         = local.any_port
  protocol          = local.any_protocol
  to_port           = local.any_port
  cidr_blocks       = local.all_ips
}
# By default AWS does not allow any incoming or outgoing traffic for all resources. So I need to set up a specific.
# security group for ALB.

resource aws_security_group "alb" {
  name = "${var.cluster_name}-alb"

  # Allow HTTP requests to access ALB.
  ingress {
    from_port = local.http_port
    to_port = local.http_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
  }

  # Allow all outbound requests, so ALB can perform health checks.
  egress {
    from_port = local.any_port
    to_port = local.any_port
    protocol = local.any_protocol
    cidr_blocks = local.all_ips
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

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key    = var.db_remote_state_key
    region = "us-east-2"
  }
}



