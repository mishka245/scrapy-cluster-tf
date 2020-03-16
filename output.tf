###################################
# Outputs
###################################
output "servers_ips" {
  value = module.ec2.public_ip[*]
}