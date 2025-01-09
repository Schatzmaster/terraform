output "alb_dns_name" {
  description = "The domain of the load balancer"
  value       = module.webserver_cluster.alb_dns_name
}