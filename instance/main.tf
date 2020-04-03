resource "aws_instance" "ec2_instance" {
  ami                    = "ami-ID"
  subnet_id              =  "subnet-ID" #CHANGE THIS
  instance_type          = "t2.medium"
  iam_instance_profile   = "ecsInstanceRole" #CHANGE THIS
  vpc_security_group_ids = ["sg-id"] #CHANGE THIS
  key_name               = "Key-test" #CHANGE THIS
  ebs_optimized          = "false"
  source_dest_check      = "false"
  user_data              = "${data.template_file.user_data.rendered}" # It is opional if you have any user-data you can use it
  root_block_device = {                # EBS Block storage value
    volume_type           = "gp2"
    volume_size           = "30"
    delete_on_termination = "true"
  }

  tags {
    Name                   = "test-ecs"
 }
}
