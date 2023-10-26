module "catalogue_instance" {  ##creatin instance
  source  = "terraform-aws-modules/ec2-instance/aws"
  ami = data.aws_ami.devops_ami.id
  instance_type = "t3.medium"
  vpc_security_group_ids = [data.aws_ssm_parameter.catalogue_sg_id.value]
  # it should be in Roboshop DB subnet
  subnet_id = element(split(",",data.aws_ssm_parameter.private_subnet_ids.value), 0)
  iam_instance_profile = "catalogue_profile"
  //user_data = file("catalogue.sh")
  tags = merge(
    {
        Name = "Catalogue-DEV-AMI"
    },
    var.common_tags
  )
}

resource "null_resource" "cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    instance_id = module.catalogue_instance.id
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
      type     = "ssh"
      user     = "centos"
      password = "DevOps321"
      host     = module.catalogue_instance.id

  }
  ## copying the file in same provisioner
  provisioner "file"{
     source = "catalogue.sh"
     destination = "/tmp/catalogue.sh"
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the cluster
    inline = [
      "chmod +x /tmp/catalouge.sh",
       "sudo sh /tmp/catalogue.sh ${var.app_version}"
# calling script i am passing application version
    ]
  }
}
#stop instance to take ami
resource "aws_ec2_instance_state" "catalogue_instance" {
  instance_id = module.catalogue_instance.id
  state       = "stopped"
}
resource "aws_ami_from_instance" "catalogue_ami"{
  name = "${var.common_tags.componnet}-${locals.current_time}"  #module.catalogue_instance.id and u can easily refer when ami is created
  source_instance_id = module.catalogue_instance.id
} #deletion of instance
# resource "aws_ec2_instance_state" "catalogue_instance_delete" {
#   instance_id = module.catalogue_instance.id
#   state       = "terminated"
#   depends_on = [aws_ami_from_instance.aws_ami_from_instance.catalogue_ami ]
# } #terminate instances
resource "null_resource" "delete_instance" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    ami_id = aws_ami_from_instance.catalogue_ami.id
  }
provisioner "local-exec" {
    # Bootstrap script called with private_ip of each node in the cluster
    command = "aws ec2 terminate_instances --instances_ids ${module.catalogue_instance.id}"
  }
}
#ntg but creting group
resource "aws_lb_target_group" "catalogue" {
  name        = "${var.project_name}-${var.common_tags.component}-${var.env}-${locals.current_time}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value
  deregistration_delay = 60
  health_check {  #it is ntg but it has responding specific skills or nnot
    enabled = true
    healthy_threshold = 2 #consider as health if 2 health checks sucess here health is instance
    interval = 15 # every 15secs check the health checkup
    matcher = "200-299"  #considerd as a sucess.
    path = "/health" #developers enabled this u will get response if the componnet is healthy
    port = 8080
    protocol = "HTTP"
    timeout = 5  #within 5sec u should get response otherwise it is unhealthy threshold
    unhealthy_threshold = 3 #3 times consecutive apply 

  }
}

resource "aws_launch_template" "catalogue" {
  name = "${var.project_name}-${var.common_tags.component}-${var.env}"

#here ami id is should be the one we just created.
  image_id = aws_ami_from_instance.catalogue_ami.id

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t2.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.catalogue_sg_id.value]
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "catalogue"
    }
  }
#we dont need since  we already configured ami completely
#   user_data = filebase64("${path.module}/catalogue.sh")
}
##creating autoscalling to catalogue component
resource "aws_autoscaling_group" "catalogue" {
  name                      = "${var.project_name}-${var.common_tags.component}-${var.env}"
  max_size                  = 5
  min_size                  = 2
  health_check_grace_period = 300 #install user data in instances iy takes time ryt so it si 300sec
  health_check_type         = "ELB" #check instance health by alb, lb responsbility 
  desired_capacity          = 2
  target_group_arns = [aws_lb_target_group.catalogue.arn] #u should add target group to autoscalling
  launch_template {
    id       = aws_launch_template.catalogue.id
    version = "$latest"
  }
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.private_subnet_ids.value )
                       #for HA we are giving 2subnet

  tag {
    key                 = "Name"
    value               = "catalogue"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
lifecycle {
  create_before_destroy = true
}
}
#creating autoscalingpolicy 
resource "aws_autoscaling_policy" "example" {
  # .which group autoscaling is here ...
  autoscaling_group_name = aws_autoscaling_group.catalogue.name
  name                   = "cpu"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}
#condition for add a rule for call one componnet to other
resource "aws_lb_listener_rule" "catalogue" {
  listener_arn = data.aws_ssm_parameter.app_lb_listener_arn.value
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.catalogue.arn
  }


  condition {
    host_header {
      #for dev instances it should be app.dev, and PROD instances it should be app.prod 
      values =["${var.common_tags.component}.app-${var.env}-${var.domain_name}"] 
      # ["catalogue.app.joindevops.xyz"]--before reference.

    }

  }
}
##example user componnet call catalogue through catalouge.app.joindevops.xyz this request go to lb so lb have entry of that rule and send to catalouge target group.

output "app_version"{
  value = var.app_version
#printing version o/p in terraform 
}
