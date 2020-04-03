variable "subnet1" {
    default = ""
}

variable "subnet2" {
    default = ""
}

variable "internal" {
    default = ""
}


##########################################################
# AWS ECS-CLUSTER & CLOUDWATCH
#########################################################

resource "aws_ecs_cluster" "cluster" {
  name = "Test-cluster"
  }

resource "aws_cloudwatch_log_group" "log_group" {
  name = "test-cluster-cw"
}


###########################################################
# AWS ECS-EC2
###########################################################
resource "aws_instance" "ec2_instance" {
  ami                    = "ami-ID"
  subnet_id              =  "subnet-ID" #CHANGE THIS
  instance_type          = "t2.medium"
  iam_instance_profile   = "ecsInstanceRole" #CHANGE THIS
  vpc_security_group_ids = ["sg-id"] #CHANGE THIS
  key_name               = "Key-test" #CHANGE THIS
  ebs_optimized          = "false"
  source_dest_check      = "false"
  user_data              = "${data.template_file.user_data.rendered}"
  root_block_device = {
    volume_type           = "gp2"
    volume_size           = "30"
    delete_on_termination = "true"
  }

  tags {
    Name                   = "test-ecs"
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
  family                   = "Test-task-defination"                                                                      # task name
  network_mode             = "awsvpc"                                                                                      # network mode awsvpc, brigde
  memory                   = "2048"
  cpu                      = "1024"
  requires_compatibilities = ["EC2"]                                                                                       # Fargate or EC2
  task_role_arn            = "EcsRole"  #CHANGE THIS                                                                     # TASK running role
} 

data "template_file" "task_definition_json" {
  template = "${file("${path.module}/task_definition.json")}"
}


##############################################################
# AWS ECS-SERVICE
##############################################################

resource "aws_ecs_service" "service" {
  cluster                = "${aws_ecs_cluster.cluster.id}"                                 # ecs cluster id
  desired_count          = 1                                                         # no of task running
  launch_type            = "EC2"                                                     # Cluster type ECS OR FARGATE
  name                   = "Test-service"                                         # Name of service
  task_definition        = "${aws_ecs_task_definition.task_definition.arn}"        # Attaching Task to service
  load_balancer {
    container_name       = "Test-ecs-container"                                  #"container_${var.component}_${var.environment}"
    container_port       = "8080"
    target_group_arn     = "${aws_lb_target_group.lb_target_group.arn}"         # attaching load_balancer target group to ecs
 }
  network_configuration {
    security_groups       = ["sg-ID"] #CHANGE THIS
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
  security_groups     = ["sg-ID"] #CHANGE THIS
}


resource "aws_lb_target_group" "lb_target_group" {
  name        = "Test-target-alb-name"
  port        = "80"
  protocol    = "HTTP"
  vpc_id      = "vpc-ID" # CHNAGE THIS
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


  load_balancer_arn = "${aws_lb.loadbalancer.arn}"
  port              = "80"
  protocol          = "HTTP"
}
