output "alb_dns_name" {
  description = "The domain name of the load balancer"
  value = aws_alb.Application_Load_Balancer.dns_name
}