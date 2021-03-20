


resource "aws_vpc" "prime" {
  cidr_block = "${var.vpc_cidr_block}"

  tags {
    Name = "${var.vpc_name}"
  }
}
resource "aws_subnet" "public_subnet" {
  vpc_id            = "${var.vpc_id}"
  cidr_block        = "${var.subnet_cidr}"
  availability_zone = "${var.subnet_az}"

  tags {
    Name = "public_${var.subnet_name}"
  }
}
output "vpc_id" {
  value = "${aws_vpc.prime.id}"
}
## Internet gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${var.vpc_id}"

  tags {
    Name = "public_${var.subnet_name}"
  }
}

## Routing table
resource "aws_route_table" "public_route_table" {
  vpc_id = "${var.vpc_id}"

  tags {
    Name = "public_${var.subnet_name}"
  }
}

resource "aws_route" "gateway_route" {
  route_table_id         = "${aws_route_table.public_route_table.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.internet_gateway.id}"
}

## Associate the routing table to public subnet
resource "aws_route_table_association" "rt_assn" {
  subnet_id      = "${aws_subnet.public_subnet.id}"
  route_table_id = "${aws_route_table.public_route_table.id}"
}
## SSH key-pair to be used to access instances in public subnet
## The instances will ONLY be accessible from Bastion Host
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  key_name   = "public_${var.subnet_name}"
  public_key = "${tls_private_key.private_key.public_key_openssh}"
}

#PRIVATE subnet
resource "aws_subnet" "private" {
  vpc_id            = "${var.vpc_id}"
  cidr_block        = "${var.subnet_cidr}"
  availability_zone = "${var.subnet_az}"

  tags {
    Name = "private_${var.subnet_name}"
  }
}

# Routing table for private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = "${var.vpc_id}"

  tags {
    Name = "private_${var.subnet_name}"
  }
}

# Associate the routing table to private subnet
resource "aws_route_table_association" "rt_assn" {
  subnet_id      = "${aws_subnet.private.id}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}

## Create a private key that'll be used for access to Bastion host
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  key_name   = "private_${var.subnet_name}"
  public_key = "${tls_private_key.private_key.public_key_openssh}"
}

#NAT creation and association
resource "aws_security_group" "nat_sg" {
  name   = "nat_sg_${var.subnet_public}"
  vpc_id = "${var.vpc_id}"
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = "${var.subnet_private_cidr_ranges}"
  }

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  tags {
    Name = "sg_nat_${var.subnet_public}"
  }
}

## Create a private key that'll be used for access to Bastion host/NAT Gateway
resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "key_pair" {
  key_name   = "bastion_${var.subnet_public}"
  public_key = "${tls_private_key.private_key.public_key_openssh}"
}
## NAT Gateway.
## This will be needed by any private subnet(s) to connect to Internet
resource "aws_instance" "nat" {
  ami               = "${var.ami_id_nat}"
  availability_zone = "${var.subnet_public_az}"
  subnet_id         = "${var.subnet_public_id}"
  instance_type     = "${var.instance_type_nat}"
  key_name          = "${aws_key_pair.key_pair.key_name}"

  vpc_security_group_ids = [
    "${aws_security_group.nat_sg.id}",
  ]

  associate_public_ip_address = true
  source_dest_check           = false

  ## update the permissions of private key file needed to access bastion
  provisioner "local-exec" {
    command = "chmod -c 600 ${path.module}/id_rsa_bastion.pem"
  }
  ## Add the private key to access private instances in .ssh folder
  provisioner "file" {
    source      = "${path.module}/id_rsa_${var.subnet_private_01}.pem"
    destination = "/home/ec2-user/.ssh/id_rsa_${var.subnet_private_01}.pem"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.private_key.private_key_pem}"
    }
  }
  ## Update permissions on all the keys
  provisioner "remote-exec" {
    inline = [
      "chmod -c 600 /home/ec2-user/.ssh/id_rsa_${var.subnet_public}.pem",
      "chmod -c 600 /home/ec2-user/.ssh/id_rsa_${var.subnet_private_01}.pem",
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = "${tls_private_key.private_key.private_key_pem}"
    }
  }
  resource "aws_eip" "eip" {
  instance = "${aws_instance.nat.id}"
  vpc      = true
}

## Route the internet bound traffic for both public subnets via NAT instance to route table of private subnet
resource "aws_route" "subnet_private_01_route" {
  route_table_id         = "${var.subnet_private_01_rt_id}"
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = "${aws_instance.nat.id}"
}
resource "aws_security_group" "internal" {
  name        = "${var.sg_internal}"
  description = "Security group to access private ports"
  vpc_id      = "${var.vpc_id}"
}
 # allow all outgoing traffic from private subnet
  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  

  tags {
    Name = "${var.sg_internal}"
  }
}
# Public security group
resource "aws_security_group" "public" {
  name        = "${var.sg_public}"
  description = "Public access security group"
  vpc_id      = "${var.vpc_id}"

  # allow http traffic
  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  tags {
    Name = "${var.sg_public}"
  }
}
#creating instance in private subnet
resource "aws_instance" "my_instance" {
  ami           = "${var.ami.id}"
  instance_type = "t2.micro"
  subnet_id     = "${aws_subnet.private_subnet.id}"

  tags = {
    Name = "HelloWorld"
  }
}



    


