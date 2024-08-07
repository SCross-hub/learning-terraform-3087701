# Data Sources
data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["979382823631"] # Bitnami
}

data "aws_vpc" "default" {
  default = true
}

# VPC Module
module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "dev"
  cidr   = "10.0.0.0/16"
  azs    = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Security Group Module
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.2"
  name    = "blog"
  vpc_id  = module.blog_vpc.vpc_id
  ingress_rules = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

# Application Load Balancer Module
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 6.0"
  name    = "blog-alb"
  load_balancer_type = "application"
  vpc_id          = module.blog_vpc.vpc_id
  subnets         = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]
  access_logs = {
    bucket = "my-alb-logs-us-west-2"  # Ensure this bucket exists in the same region
  }
  target_groups = [
    {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  ]
  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]
  tags = {
    Environment = "dev"
  }
}

# Launch Template for Auto Scaling
resource "aws_launch_template" "example" {
  name_prefix   = "example-"
  image_id       = data.aws_ami.app_ami.id
  instance_type  = var.instance_type
  key_name        = var.key_name

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "example" {
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }
  
  min_size               = 1
  max_size               = 3
  desired_capacity       = 1
  vpc_zone_identifier    = module.blog_vpc.public_subnets
  tag {
    key                 = "Name"
    value               = "example-instance"
    propagate_at_launch = true
  }
  health_check_type          = "EC2"
  health_check_grace_period = 300
}

# Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example.name
}

# CloudWatch Alarms
resource "aws_cloudwatch_alarm" "cpu_high" {
  alarm_name                = "cpu_high"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "70"
  alarm_description         = "Triggers if CPU utilization exceeds 70%."
  alarm_actions             = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
}

resource "aws_cloudwatch_alarm" "cpu_low" {
  alarm_name                = "cpu_low"
  comparison_operator       = "LessThanThreshold"
  evaluation_periods        = "2"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "30"
  alarm_description         = "Triggers if CPU utilization drops below 30%."
  alarm_actions             = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.example.name
  }
}
