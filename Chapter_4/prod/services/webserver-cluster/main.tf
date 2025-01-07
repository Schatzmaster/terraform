provider "aws" {
  region = "us-east-2"
}

module "webserver_cluster" {
  source = "../../../modules/services/webserver-cluster"

  cluster_name           = "webservers-prod"
  db_remote_state_bucket = "jaspis-terraform-up-and-running-state"
  db_remote_state_key    = "prod/data-stores/mysql/terraform.tfstate"

  instance_type = "t2.micro"
  min_size      = 2
  max_size      = 10
}

# Right now I do have the problem, that all names in the webserver-cluster module are hardcoded. That means I will get
# conflict errors with the names, if I use the module more than once, because the names in the AWS account are not unique.
# Same goes for the terraform-remote-state data source, as the state file is hardcoded for stage, means it gets the data
# just from the stage state file.
# To solve this I need to add configurable inputs like parameters in python functions to specify values regarding to the
# environment I am using. This happens through input variables in terraform (variables.tf in webserver-cluster module)

resource "aws_autoscaling_schedule" "scale_out_during_business_hours" {
  scheduled_action_name  = "scale-out-during-business-hours"
  min_size = 2
  max_size = 10
  desired_capacity = 10
  recurrence = "0 9 * * *"

  autoscaling_group_name = module.webserver_cluster.asg_name
}

resource "aws_autoscaling_schedule" "scale_in_at_night" {
  scheduled_action_name  = "scale-in-during-night"
  min_size = 2
  max_size = 10
  desired_capacity = 2
  recurrence = "0 17 * * *"

  autoscaling_group_name = module.webserver_cluster.asg_name
}