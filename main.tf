provider "aws" {
  region = "us-east-1"
}

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  default     = 8080
}

data "aws_availability_zones" "all" {}

resource "aws_launch_configuration" "launchconfig1" {
  image_id        = "ami-40d28157"
  instance_type   = "t2.micro"
  security_groups = ["${aws_security_group.http.id}"]

  user_data = <<-EOF
    #!/bin/bash
    echo "Hello, world" > index.html
    nohup busybox httpd -f -p "${var.server_port}" &
    EOF

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "http" {
  name = "terraform-example"

  ingress {
    from_port   = "${var.server_port}"
    to_port     = "${var.server_port}"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "http-elb-sg" {
  name = "http-elb-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_autoscaling_group" "asg1" {
  launch_configuration = "${aws_launch_configuration.launchconfig1.id}"
  min_size             = 2
  max_size             = 10
  availability_zones   = ["${data.aws_availability_zones.all.names}"]
  load_balancers       = ["${aws_elb.http-elb.name}"]
  health_check_type    = "ELB"

  tag {
    key                 = "Name"
    value               = "http-webgroup"
    propagate_at_launch = true
  }
}

resource "aws_elb" "http-elb" {
  name               = "http-elb1"
  availability_zones = ["${data.aws_availability_zones.all.names}"]
  security_groups    = ["${aws_security_group.http-elb-sg.id}"]

  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = "${var.server_port}"
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:${var.server_port}/"
    interval            = 30
  }
}

output "public_ip" {
  value = "${aws_elb.http-elb.dns_name}"
}
