# terraform_repo
#the code will create infra with following resources
vpc -prime (us-east-2)
public subnet - public_subnet(us-east-2a)
private subnet - private_subnet(us-east-2a)
Internet gateway - Internet_gateway
Routing table
1. public_route_table
2. private
NAT Gateway
Security group
1.public security group
2.private security group
EC2 instance into private subnet

#two create two vpc in different regions and AZs we need to run this file again by specifying variable 
vpc_region
subnet_public_az
subnet_private_01_az
