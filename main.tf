# First, terraform init to download the specified provider config files which leads to create the folder '.terraform' directory
# Use terraform state list to check all running resourses and terraform state show 'specific_resourse' to get details information about that resourse

# Use terraform apply/destroy --auto-approve instead of writing 'yes' everytime you apply/destroy and also before apply you may try 'terraform plan' to check your resourses before anything happens in real
# Target a specific resourse using cli args i.e terraform apply/destroy -target resourse

# If we define a variable in terraform tf config file but haven't assigned it anywhere in our tfvars or cli args then, it will ask it to us to enter that variable while applying or destroying those resourses
# Here, we define a variable but not assign it (use terraform.tfvars to assign it or using cli args i.e terraform -var "subnet_prefix=10.0.1.0/24")
variable "subnet_prefix" {
  description = "cidr block for the subnet"
# default = ""
# type = string
}

# resource "aws_instance" "prac_server" {
#   ami           = "ami-04bde106886a53080"
#   instance_type = "t2.micro"

#   tags = {
#     Name = "UbuntuPracServerInstance"
#   }
# }

# Create a VPC
resource "aws_vpc" "first-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "productionVpc"
  }
}

# Create a Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.first-vpc.id

  tags = {
    Name = "productionGw"
  }
}

# Create Custom Route Table
resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.first-vpc.id

  # IPv4
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  # IPv6
  route {
    ipv6_cidr_block        = "::/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "prodRouteTable"
  }
}

# Create a Subnet for the above VPC
resource "aws_subnet" "subnet-1" {
  vpc_id     = aws_vpc.first-vpc.id
  cidr_block = var.subnet_prefix[0].cidr_block
  availability_zone = "ap-south-1a"

  tags = {
    Name = var.subnet_prefix[0].name
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.prod-route-table.id
}

# Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.first-vpc.id

  ingress {
    description      = "HTTPS from VPC"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    # cidr_blocks      = [aws_vpc.main.cidr_block]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    # cidr_blocks      = [aws_vpc.main.cidr_block]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  ingress {
    description      = "SSH from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    # cidr_blocks      = [aws_vpc.main.cidr_block]
    # ipv6_cidr_blocks = [aws_vpc.main.ipv6_cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allowWebPorts"
  }
}

# Create a network interface with an ip in the subnet that was created
resource "aws_network_interface" "prod-nic" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

#   attachment {
#     instance     = aws_instance.test.id
#     device_index = 1
#   }
}

# Assign an elastic IP to the network interface created
resource "aws_eip" "eip-1" {
  vpc                       = true
  network_interface         = aws_network_interface.prod-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on = [aws_internet_gateway.gw]
}

# To showing multiple outputs we need to create multiple 'output blocks' like this below for having each separate individual output
# Showing a custom output of public elastic IP created for our help preference (use cli args instead of apply i.e terraform output)
output "server_public_IP" {
    value = aws_eip.eip-1.public_ip
}

# Create Ubuntu server and install/enable apache2
resource "aws_instance" "prod_server" {
  ami           = "ami-04bde106886a53080"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name = "experi"

  network_interface {
    network_interface_id = aws_network_interface.prod-nic.id
    device_index         = 0
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install apache2 -y
                sudo systemctl start apache2
                sudo bash -c 'echo my very first web server deploy > /var/www/html/index.html'
                EOF

  tags = {
    Name = "UbuntuProdServerInstance"
  }
}