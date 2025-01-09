output "alb_dns_name" {
  description = "The domain name of the load balancer"
  value       = aws_alb.Application_Load_Balancer.dns_name
}

output "asg_name" {
  value       = aws_autoscaling_group.example.name
  description = "The name of the Auto Scaling Group"
}

output "alb_security_group_id" {
  description = "The ID of the Security Group attached to the load balancer"
  value       = aws_security_group.alb.id
}