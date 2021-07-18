#--------------------------------------------------------------
# variable
#--------------------------------------------------------------
variable "cidr" {
  description = "The CIDR block for the VPC."
}
variable "public_subnets" {
  description = "Comma separated list of subnets"
}
variable "private_subnets" {
  description = "Comma separated list of subnets"
}
variable "name" {
  description = "Name tag, e.g stack"
  default     = "Stack"
}
variable "region" {
}
variable "tag_purpose" {
}
variable "image" {
}
variable "root_volume_size" {
}
variable "root_volume_type" {
}
variable "type" {
}
#--------------------------------------------------------------
# AWS VPC
#--------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name        = var.name
    Purpose     = var.tag_purpose
  }
}
#--------------------------------------------------------------
# AWS Gateways
#--------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name        = var.name
    Purpose     = var.tag_purpose
    Function    = "Gateway"
  }
}
resource "aws_eip" "nat_gateway" {
  vpc = true
}
resource "aws_nat_gateway" "nat_gw_main" {
  allocation_id = aws_eip.nat_gateway.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "nat-gw"
    Purpose     = var.tag_purpose
    Function    = "Gateway"
  }
}
#--------------------------------------------------------------
# AWS Subnets
#--------------------------------------------------------------
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets
  availability_zone       = "us-east-1b"
  tags = {
    Name        = "${var.name}-private_subnet"
    Purpose     = var.tag_purpose
    Function    = "Subnet"
  }
}
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.name}-public_subnet"
    Purpose     = var.tag_purpose
    Function    = "Subnet"
  }
}
#--------------------------------------------------------------
# AWS Routing Tables
#--------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name        = "${var.name}-public"
    Purpose     = var.tag_purpose
  }
  lifecycle {
    ignore_changes = all
  }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gw_main.id
  }
  tags = {
    Name        = "${var.name}-private"
    Purpose     = var.tag_purpose
  }
  lifecycle {
    ignore_changes = all
  }
}
#--------------------------------------------------------------
# AWS Routing Table Associations
#--------------------------------------------------------------
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private.id
}
#--------------------------------------------------------------
# AWS SG
#--------------------------------------------------------------
resource "aws_security_group" "peak" {
  name        = "peak-sg"
  vpc_id      = aws_vpc.main.id
  
  
  tags = {
    Name        = "peak-sg"
    Purpose     = var.tag_purpose
  }
}
resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.peak.id
}
resource "aws_security_group_rule" "allow_all_inbound" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.peak.id
}
#--------------------------------------------------------------
# AWS EC2 instance
#--------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "ssh" {
  key_name = "peak-test"
  public_key = tls_private_key.ssh.public_key_openssh
}
resource "aws_instance" "public_machine" {
  ami                  = "${var.image}"
  instance_type        = "${var.type}"
  ebs_optimized        = "false"
  subnet_id            = aws_subnet.public_subnet.id
  key_name             = aws_key_pair.ssh.key_name
  user_data            = "${file("${path.module}/scripts/userdata.sh")}"
  vpc_security_group_ids = [aws_security_group.peak.id]
  tags = {
    Name        = "public_machine"
    Purpose     = "${var.tag_purpose}"
  }
  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
  }
  lifecycle {
    ignore_changes = [user_data, subnet_id, ebs_optimized]
  }
}
resource "aws_instance" "private_machine" {
  ami                  = "${var.image}"
  instance_type        = "${var.type}"
  ebs_optimized        = "false"
  subnet_id            = aws_subnet.private_subnet.id
  key_name             = aws_key_pair.ssh.key_name
  user_data            = "${file("${path.module}/scripts/userdata.sh")}"
  vpc_security_group_ids = [aws_security_group.peak.id]
  tags = {
    Name        = "private_machine"
    Purpose     = "${var.tag_purpose}"
  }
  root_block_device {
    volume_type = "${var.root_volume_type}"
    volume_size = "${var.root_volume_size}"
  }
  lifecycle {
    ignore_changes = [user_data, subnet_id, ebs_optimized]
  }
}
#--------------------------------------------------------------
# AWS NLB
#--------------------------------------------------------------
######### NETWORK LOAD BALANCER CONFIGURATION #########

resource "aws_lb" "peak" {
  name               = "peak-${var.env}"
  load_balancer_type = "network"
  idle_timeout       = 300

  subnets = "${public_subnets.id}"

  internal = true
  tags = {
    Name        = "peak-${var.env}"
    Group       = "${var.tag_group}"
    Environment = "${var.env}"
    Datacenter  = "${var.region}"
    Purpose     = "${var.tag_purpose}"
    datadog     = "${var.peak_monitoring == "true" ? "monitored" : "not_monitored"}"
    Objective   = "${var.tag_objective}"
    Continuity  = "${var.tag_continuity}"
    Function    = "${var.tag_function}"
    Team        = "${var.tag_team}"
    BU          = "${var.tag_bu}"
  }
}


data "aws_acm_certificate" "nlb_wildcard_info" {
  domain   = "*.peak.com"
  statuses = ["ISSUED"]
}
resource "aws_lb_listener" "peak" {
  load_balancer_arn = aws_lb.peak.arn
  port              = "443"
  protocol          = "TLS"
  certificate_arn   = "${data.aws_acm_certificate.nlb_wildcard_info.arn}"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  alpn_policy       = "HTTP2Optional"
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.internal_alb_target_peak.arn
  }
}
resource "aws_route53_record" "peak-lb-dns" {
  zone_id = "${var.root_zone_id}"
  name    = "peak-${var.env}.${var.services_domain}"
  type    = "CNAME"
  ttl     = "300"
  records = ["${aws_lb.peak.dns_name}"]
}
#--------------------------------------------------------------
# AWS ASG
#--------------------------------------------------------------
resource "aws_autoscaling_group" "peak" {
  name                = "peak-${var.env}"
  capacity_rebalance  = true
  force_delete        = true
  max_size            = "${var.asg_max}"
  min_size            = "${var.asg_min}"
  vpc_zone_identifier = "${public_subnets.id}"
  termination_policies = ["OldestInstance"]
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = "${var.mixed_instance_policy["asg_base_capacity"]}"
      on_demand_percentage_above_base_capacity = "${var.mixed_instance_policy["asg_on_demand_percentage"]}"
      spot_allocation_strategy                 = "capacity-optimized"
      spot_instance_pools                      = 0
    }
    launch_template {
      launch_template_specification {
        launch_template_id = "${aws_launch_template.peak.id}"
        version            = "$Latest"
      }
      dynamic "override" {
        for_each = "${var.mixed_instance_policy["asg_override_instances"]}"
        content {
          instance_type = lookup(override.value, "asg_override_instance_type", null)
        }
      }
    }
  }
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupMaxSize",
    "GroupMinSize",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
  tag {
    key                 = "Continuity"
    value               = "${var.tag_continuity}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Objective"
    value               = "${var.tag_objective}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Function"
    value               = "${var.tag_function}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Team"
    value               = "${var.tag_team}"
    propagate_at_launch = true
  }
  tag {
    key                 = "BU"
    value               = "${var.tag_bu}"
    propagate_at_launch = true
  }
  tag {
    key                 = "datadog"
    value               = "${var.peak_monitoring_asg_worker == "true" ? "monitored" : "not_monitored"}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Datacenter"
    value               = "${var.region}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Name"
    value               = "peak-worker"
    propagate_at_launch = true
  }
  tag {
    key                 = "Group"
    value               = "${var.tag_group}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Purpose"
    value               = "${var.tag_purpose}"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "${var.env}"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [load_balancers, target_group_arns]
  }
}
resource "aws_launch_template" "peak" {
  name                                 = "peak-${var.env}"
  ebs_optimized                        = true
  image_id                             = "${var.image}"
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "${var.asg_worker_type}"
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = ["${var.sg_internal}"]
    delete_on_termination       = true
  }
  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted   = "${var.asg_ebs_encryption}"
      volume_size = "${var.root_volume_size}"
      volume_type = "${var.root_volume_type}"
    }
  }
  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }
  iam_instance_profile {
    name = "${var.instance_profile}"
  }
  monitoring {
    enabled = true
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "peak-worker"
      Environment = "${var.env}"
      Purpose     = "${var.tag_purpose}"
      Group       = "${var.tag_group}"
      Continuity  = "${var.tag_continuity}"
      Objective   = "${var.tag_objective}"
      Function    = "${var.tag_function}"
      Team        = "${var.tag_team}"
      BU          = "${var.tag_bu}"
      datadog     = "${var.peak_monitoring_asg_worker == "true" ? "monitored" : "not_monitored"}"
      Datacenter  = "${var.region}"
    }
  }
  user_data            = base64encode("${file("${path.module}/scripts/userdata.sh")}")
}


