provider "aws" {
  region = "us-east-2"
}

terraform {
  backend "s3" {
    bucket         = "jaspis-terraform-up-and-running-state"
    key            = "excercises/terraform.tfstate"
    region         = "us-east-2"

    dynamodb_table = "terraform-up-and-running-locks"
    encrypt        = true
  }
}

resource "aws_launch_template" "instances" {
  image_id = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"
  security_group_names = [aws_security_group.http-and-ssh.name]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo amazon-linux-extra install nginx1.12 -y
              sudo systemctl start nginx
              sudo systemctl enable nginx
              EOF
  )

  tag_specifications {
    resource_type = "instance"

    tags = {
      name = "example-launch-template"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "example" {
  target_group_arns    = [aws_alb_target_group.target_group_example.arn]
  max_size             = 5
  min_size             = 2
  vpc_zone_identifier  = data.aws_subnets.default.ids
  health_check_type    = "ELB"

  tag {
    key                 = "Name"
    propagate_at_launch = false
    value               = "terraform-asg-example"
  }

  launch_template {
    id      = aws_launch_template.instances.id
    version = "$Latest"
  }
}

# SECURITY GROUPS

resource "aws_security_group" "http-and-ssh" {
  name = "allow-http-and-ssh"
  vpc_id = data.aws_vpc.default.id

  # HTTP ingress
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH ingress
  ingress {
    from_port   = var.SSH_port
    to_port     = var.SSH_port
    protocol    = "tcp"
    cidr_blocks = var.my_ip
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# LOAD BALANCER

resource "aws_alb" "alb-example" {
  name = "app-load-balancer"
  load_balancer_type = "application"
  security_groups = [aws_security_group.http-and-ssh.id]
  subnets = data.aws_subnets.default.ids
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_alb.alb-example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: Page not found"
      status_code  = "404"
    }

  }
}

resource "aws_alb_target_group" "target_group_example" {
  name = "tf-example-alb-target-group"
  vpc_id = data.aws_vpc.default.id
  port = var.server_port
  protocol = "HTTP"

  health_check {
    path                = "/"
    interval            = 10
    matcher             = "200"
    port                = var.server_port
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
  }
}

# DATA SOURCES

data "aws_vpc" "default"{
  default = true
}

data "aws_subnets" "default" {
   filter {
     name   = "vpc-id"
     values = [data.aws_vpc.default.id]
   }
}

# VARIABLES

variable "server_port" {
  description   = "Port of the server"
  default       = 80
}

variable "SSH_port" {
  description   = "Port for SSH"
  default       = 22
}

variable "my_ip" {
  description   = "My IP Address"
  default       = ["192.168.178.27/32"]
}

output "public_dns_alb" {
  value = aws_alb.alb-example.dns_name
}