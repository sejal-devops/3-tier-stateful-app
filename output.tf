output "nat_gateway_ip" {
  value = aws_eip.nat-eip.public_ip
}