variable "subnet1" {
    default = ""
}

variable "subnet2" {
    default = ""
}

variable "internal" {
    default = ""
}

variable "oidc_provider_metadata_url" {
    default = ""
}

variable "oidc_redirect_uri" {
    default = ""
}
variable "oidc_client_secret" {
    default = ""
}
variable "oidc_client_id" {
    default = ""
}
variable "oidc_client_scope" {
    default = ""
}
variable "oidc_crypto_passphrase" {
    default = ""
}

##########################################################
# AWS ECS-CLUSTER & CLOUDWATCH
#########################################################

resource "aws_ecs_cluster" "cluster" {
  name = "openapi-devl-cluster"
  }

resource "aws_cloudwatch_log_group" "log_group" {
  name = "openapi-devl-cw"
}


###########################################################
# AWS ECS-EC2
###########################################################
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-08935252a36e25f85"
  subnet_id              =  "subnet-087e48d4db31e442d" #CHANGE THIS
  instance_type          = "t2.medium"
  iam_instance_profile   = "ecsInstanceRole" #CHANGE THIS
  vpc_security_group_ids = ["sg-01849003c4f9203ca"] #CHANGE THIS
  key_name               = "pnl-test" #CHANGE THIS
  ebs_optimized          = "false"
  source_dest_check      = "false"
  user_data              = "${data.template_file.user_data.rendered}"
  root_block_device = {
    volume_type           = "gp2"
    volume_size           = "30"
    delete_on_termination = "true"
  }

  tags {
    Name                   = "openapi-ecs-ec2_instance"
}

  lifecycle {
    ignore_changes         = ["ami", "user_data", "subnet_id", "key_name", "ebs_optimized", "private_ip"]
  }
}

data "template_file" "user_data" {
  template = "${file("${path.module}/user_data.tpl")}"
}

############################################################
# AWS ECS-TASK
############################################################

resource "aws_ecs_task_definition" "task_definition" {
  container_definitions    = "${data.template_file.task_definition_json.rendered}"                                         # task defination json file location
  execution_role_arn       = "EcsTaskExecutionRole" #CHANGE THIS                                                                      # role for executing task
  family                   = "openapi-task-defination"                                                                      # task name
  network_mode             = "awsvpc"                                                                                      # network mode awsvpc, brigde
  memory                   = "2048"
  cpu                      = "1024"
  requires_compatibilities = ["EC2"]                                                                                       # Fargate or EC2
  task_role_arn            = "EcsTaskExecutionRole"  #CHANGE THIS                                                                     # TASK running role
} 

data "template_file" "task_definition_json" {
  template = "${file("${path.module}/task_definition.json")}"
    vars {
    oidc_provider_metadata_url  = "${var.oidc_provider_metadata_url}"
    oidc_redirect_uri           = "${var.oidc_redirect_uri}"
    oidc_client_secret          = "${var.oidc_client_secret}"
    oidc_client_id              = "${var.oidc_client_id}"
    oidc_client_scope           = "${var.oidc_client_scope}"
    oidc_crypto_passphrase      = "${var.oidc_crypto_passphrase}"
  }
}


##############################################################
# AWS ECS-SERVICE
##############################################################

resource "aws_ecs_service" "service" {
  cluster                = "${aws_ecs_cluster.cluster.id}"                                 # ecs cluster id
  desired_count          = 1                                                         # no of task running
  launch_type            = "EC2"                                                     # Cluster type ECS OR FARGATE
  name                   = "openapi-service"                                         # Name of service
  task_definition        = "${aws_ecs_task_definition.task_definition.arn}"        # Attaching Task to service
  load_balancer {
    container_name       = "openapi-ecs-container"                                  #"container_${var.component}_${var.environment}"
    container_port       = "8080"
    target_group_arn     = "${aws_lb_target_group.lb_target_group.arn}"         # attaching load_balancer target group to ecs
 }
  network_configuration {
    security_groups       = ["sg-01849003c4f9203ca"] #CHANGE THIS
    subnets               = ["${var.subnet1}", "${var.subnet2}"]
    assign_public_ip      = "false"
  }
  depends_on              = ["aws_lb_listener.lb_listener"]
}

####################################################################
# AWS ECS-ALB
#####################################################################

resource "aws_lb" "loadbalancer" {
  internal            = "${var.internal}"
  name                = "openapi-alb-name"
  subnets             = ["${var.subnet1}", "${var.subnet2}"]
  security_groups     = ["sg-01849003c4f9203ca"] #CHANGE THIS
}


resource "aws_lb_target_group" "lb_target_group" {
  name        = "openapi-target-alb-name"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "vpc-000851116d62e0c13" # CHNAGE THIS
  target_type = "ip"


#STEP 1 - ECS task Running
  health_check {
    healthy_threshold   = "3"
    interval            = "10"
    port                = "8080"
    path                = "/index.html"
    protocol            = "HTTP"
    unhealthy_threshold = "3"
  }
}

resource "aws_lb_listener" "lb_listener" {
  "default_action" {
    target_group_arn = "${aws_lb_target_group.lb_target_group.id}"
    type             = "forward"
  }

  #certificate_arn   = "arn:aws:acm:us-east-1:689019322137:certificate/9fcdad0a-7350-476c-b7bd-3a530cf03090"
  load_balancer_arn = "${aws_lb.loadbalancer.arn}"
  port              = "80"
  protocol          = "HTTP"
}

###############################################################
# AWS ECS-ROUTE53
###############################################################
data "aws_route53_zone" "r53_private_zone" {
  name         = "vpn-devl.us.e10.c01.johndeerecloud.com."
  private_zone = false
}

resource "aws_route53_record" "dns" {
  zone_id = "${aws_route53_zone.r53_private_zone.zone_id}"
  name    = "openapi-editor-devl"
  type    = "A"

  alias {
    evaluate_target_health = false
    name                   = "${aws_lb.loadbalancer.dns_name}"
    zone_id                = "${aws_lb.loadbalancer.zone_id}"
  }
}