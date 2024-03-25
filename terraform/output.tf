output "aws_eip_1" {
  value = aws_eip.nat["1"].public_ip
}

output "aws_eip_2" {
  value = aws_eip.nat["2"].public_ip
}
output "jump-public-ip" {
  description = "This is the IP address of the jump server"
  value       = aws_eip.ec2-jump.public_ip
}

output "load-balancer" {
  description = "This is the DNS of the load balancer"
  value       = aws_lb.public_lb.dns_name
}
