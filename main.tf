provider "aws" {
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

#create aws vpc
resource "aws_vpc" "main" {
  cidr_block       = "192.169.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "main-vpc"
  }
}

#create 2 public subnet in two different avaliability zone
resource "aws_subnet" "public_subnet_01" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.169.3.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"

  tags = {
    Name = "public_subnet_01"
  }
}

resource "aws_subnet" "public_subnet_02" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "192.169.4.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1f"

  tags = {
    Name = "public_subnet_02"
  }
}

#create internet gateway
resource "aws_internet_gateway" "myigw2" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "myigw2"
  }
}

#create route-table
resource "aws_route_table" "new_public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myigw2.id
  }


  tags = {
    Name = "new_public_route_table"
  }
}

#create a route table association
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet_01.id
  route_table_id = aws_route_table.new_public_route_table.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_subnet_02.id
  route_table_id = aws_route_table.new_public_route_table.id
}

# create load balancer security group
resource "aws_security_group" "load_balancer_sg" {
  name        = "load-balancer-sg"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#create security group
resource "aws_security_group" "secure_group2" {
  name        = "secure_group2"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  ingress {
    description     = "HTTPS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    security_groups = [aws_security_group.load_balancer_sg.id]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure_group2"
  }
  }


# create ec2 instance
resource "aws_instance" "web1" {
    ami = "ami-06878d265978313ca"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "new_pair_key"
    subnet_id      = aws_subnet.public_subnet_01.id
    security_groups = [aws_security_group.secure_group2.id]

  tags = {
    Name = "web1"
  }
}

resource "aws_instance" "web2" {
    ami = "ami-06878d265978313ca"
    instance_type = "t2.micro"
    availability_zone = "us-east-1a"
    key_name = "new_pair_key"
    subnet_id      = aws_subnet.public_subnet_01.id
    security_groups = [aws_security_group.secure_group2.id]

  tags = {
    Name = "web2"
  }
}
resource "aws_instance" "web3" {
    ami = "ami-06878d265978313ca"
    instance_type = "t2.micro"
    availability_zone = "us-east-1f"
    key_name = "new_pair_key"
    subnet_id      = aws_subnet.public_subnet_02.id
    security_groups = [aws_security_group.secure_group2.id]

  tags = {
    Name = "web3"
  }
}

# create target-group
resource "aws_lb_target_group" "public-target-group" {
  name     = "public-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
# create a load balancer
resource "aws_lb" "apache-load-balancer" {
  name            = "apache-loadbalancer"
  internal        = false
  security_groups = [aws_security_group.load_balancer_sg.id]
  subnets         = [aws_subnet.public_subnet_01.id, aws_subnet.public_subnet_02.id]

  enable_deletion_protection = false
  depends_on                 = [aws_instance.web1, aws_instance.web2, aws_instance.web3]
}

# Create the listener
resource "aws_lb_listener" "apache-lb-listener" {
  load_balancer_arn = aws_lb.apache-load-balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public-target-group.arn
  }
}
# Create the listener rule
resource "aws_lb_listener_rule" "terraform-listener-rule" {
  listener_arn = aws_lb_listener.apache-lb-listener.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public-target-group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

# Attach the target group to the load balancer

resource "aws_lb_target_group_attachment" "target-group-attachment1" {
  target_group_arn = aws_lb_target_group.public-target-group.arn
  target_id        = aws_instance.web1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "target-group-attachment2" {
  target_group_arn = aws_lb_target_group.public-target-group.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "target-group-attachment-terraform3" {
  target_group_arn = aws_lb_target_group.public-target-group.arn
  target_id        = aws_instance.web3.id
  port             = 80
}

# Export IP addresses of the 3 instances to host-inventory file

resource "local_file" "ip_address" {
  filename = "/vagrant/anisble/inventory"
  content  = <<EOT
  ${aws_instance.web1.public_ip}
  ${aws_instance.web1.public_ip}
  ${aws_instance.web1.public_ip}
    EOT
}

# Route 53 and sub-domain name setup

resource "aws_route53_zone" "domain-name" {
  name = "rasheedapampa.me"
}

resource "aws_route53_zone" "sub-domain-name" {
  name = "terraform-test.rasheedapampa.me"

  tags = {
    Environment = "sub-domain-name"
  }
}

resource "aws_route53_record" "record" {
  zone_id = aws_route53_zone.domain-name.zone_id
  name    = "terraform-test.rasheedapampa.me"
  type    = "A"

  alias {
    name                   = aws_lb.apache-load-balancer.dns_name
    zone_id                = aws_lb.apache-load-balancer.zone_id
    evaluate_target_health = true
  }
  depends_on = [
    aws_lb.apache-load-balancer
  ]
}