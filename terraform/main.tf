provider "aws" {
  region = "ca-central-1"
}

locals {
  all_tags = {
    createdBy   = "Terraform"
    Application = "Demo Application"
  }
}
resource "aws_eip" "nat" {
  for_each = var.azs
  domain   = "vpc"
}
resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags             = merge(local.all_tags, tomap({ Name = "main" }))
}



resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.all_tags, tomap({ Name = "internet_gw" }))
}
resource "aws_nat_gateway" "public_nat_gw" {
  for_each          = var.azs
  connectivity_type = "public"
  allocation_id     = aws_eip.nat[each.key].allocation_id
  subnet_id         = aws_subnet.public_subnet[each.key].id

  tags = merge(local.all_tags, tomap({ Name = "public_nat_gw_1a" }))

  # To ensure proper ordering, it is recommended to add an explicit dependency
  # on the Internet Gateway for the VPC.
  depends_on = [aws_internet_gateway.gw]
}


resource "aws_subnet" "public_subnet" {
  for_each          = var.azs
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${each.key}.0/24"
  availability_zone = each.value
  tags              = merge(local.all_tags, tomap({ Name = "public_subnet" }))
}

resource "aws_subnet" "private_subnet" {
  for_each          = var.azs
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${sum([tonumber(each.key), 2])}.0/24"
  availability_zone = each.value
  tags              = merge(local.all_tags, tomap({ Name = "private_subnet" }))
}


resource "aws_route_table" "public_rt_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }
  tags = merge(local.all_tags, tomap({ Name = "public_rt_table" }))
}

resource "aws_route_table" "private_rt_table" {
  for_each = var.azs
  vpc_id   = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.public_nat_gw[each.key].id
  }

  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }
  tags = merge(local.all_tags, tomap({ Name = "private_subnet" }))
}


resource "aws_route_table_association" "public_association" {
  for_each       = var.azs
  subnet_id      = aws_subnet.public_subnet[each.key].id
  route_table_id = aws_route_table.public_rt_table.id
}

resource "aws_route_table_association" "private_association" {
  for_each       = var.azs
  subnet_id      = aws_subnet.private_subnet[each.key].id
  route_table_id = aws_route_table.private_rt_table[each.key].id
}

resource "aws_lb" "public_lb" {
  name                       = "public-lb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.allow_http_lb.id]
  subnets                    = [aws_subnet.public_subnet["1"].id, aws_subnet.public_subnet["2"].id]
  enable_deletion_protection = false
  tags                       = merge(local.all_tags, tomap({ Name = "public_lb" }))
}

resource "aws_lb_target_group" "public_lb_target_group" {
  target_type = "instance"
  name        = "public-lb-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  health_check {
    path                = "/"
    port                = 80
    healthy_threshold   = 5
    unhealthy_threshold = 3
    interval            = 60
    matcher             = "200"
  }
  tags = merge(local.all_tags, tomap({ Name = "public_lb_target_group" }))
}

resource "aws_lb_listener" "public_lb_listener" {
  load_balancer_arn = aws_lb.public_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_lb_target_group.arn
  }
  tags = merge(local.all_tags, tomap({ Name = "public_lb_listener" }))
}

resource "aws_security_group" "allow_http_lb" {
  name        = "allow-http-lb"
  description = "Allow http inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = -1
    to_port     = 0
  }
  tags = merge(local.all_tags, tomap({ Name = "allow_http_lb" }))
}

resource "aws_security_group" "allow_http_ec2" {
  name        = "allow-http-ec2"
  description = "Allow http inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 80
    protocol        = "tcp"
    to_port         = 80
    security_groups = [aws_security_group.allow_http_lb.id]
  }
  ingress {
    from_port       = 22
    protocol        = "tcp"
    to_port         = 22
    security_groups = [aws_security_group.jump_ec2.id]
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = -1
    to_port     = 0
  }
  tags = merge(local.all_tags, tomap({ Name = "allow_http_ec2" }))
}

resource "aws_launch_template" "ec2-template" {
  name_prefix            = "ec2-template"
  image_id               = "ami-0748249a1ffd1b4d2"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.allow_http_ec2.id]
  key_name               = aws_key_pair.key.key_name
  user_data              = filebase64("../script/user-data.sh")
}

resource "aws_autoscaling_group" "ec2-autoscaling" {
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.private_subnet["1"].id, aws_subnet.private_subnet["2"].id]
  launch_template {
    id      = aws_launch_template.ec2-template.id
    version = "$Latest"
  }
}
# Create a new ALB Target Group attachment
resource "aws_autoscaling_attachment" "ec2_attachment" {
  autoscaling_group_name = aws_autoscaling_group.ec2-autoscaling.name
  lb_target_group_arn    = aws_lb_target_group.public_lb_target_group.arn
}
resource "aws_eip" "ec2-jump" {
  domain   = "vpc"
  instance = aws_instance.ec2-jump.id
}


resource "aws_instance" "ec2-jump" {
  instance_type   = "t2.micro"
  ami             = "ami-0748249a1ffd1b4d2"
  key_name        = aws_key_pair.key.key_name
  subnet_id       = aws_subnet.public_subnet["1"].id
  security_groups = [aws_security_group.jump_ec2.id]
  provisioner "local-exec" {
    command = "chmod 600 ${local_file.private_key_pem.filename}"
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = tls_private_key.rsa-2046-jump.private_key_pem
      host        = self.public_ip
    }
  }
}

resource "aws_security_group" "jump_ec2" {
  name        = "jump-ec2"
  description = "Allow http inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = -1
    to_port     = 0
  }
  tags = merge(local.all_tags, tomap({ Name = "allow_http_ec2" }))
}

resource "aws_key_pair" "key" {
  public_key = tls_private_key.rsa-2046-jump.public_key_openssh
  key_name   = "AWSKey"
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-2046-jump" {
  algorithm = "RSA"
  rsa_bits  = 2046
}
resource "local_file" "private_key_pem" {
  content  = tls_private_key.rsa-2046-jump.private_key_pem
  filename = "AWSKey.pem"
}
