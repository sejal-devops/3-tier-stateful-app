//Create VPC
resource "aws_vpc" "vpc" {
cidr_block = var.vpc-cidr

tags = {
  Name = "SDK-vpc"
}
}
//Create IGW
resource "aws_internet_gateway" "sdk-igw" {
  vpc_id = aws_vpc.vpc.id
tags = {
  Name ="SDK-igw"
}
}
//route table pub
resource "aws_route_table" "sdk-pub-rt" {
  vpc_id = aws_vpc.vpc.id
  
  route {
    cidr_block ="0.0.0.0/0"
    gateway_id =aws_internet_gateway.sdk-igw.id
  }
tags = {
    Name ="SDK-pub-rt"
}
}
//dmz-pub-subnet
resource "aws_subnet" "dmz_subnet" {
    vpc_id = aws_vpc.vpc.id
    cidr_block = var.dmz_subnet_CIDR
    availability_zone = var.az
 
  tags = {
    Name =  "SDK-dmz-subnet}"
  }
}

//dmz association in pub rt
resource "aws_route_table_association" "sdk-pub-rt-association" {
 subnet_id = aws_subnet.dmz_subnet.id
 route_table_id = aws_route_table.sdk-pub-rt.id
}

//create NAT gateway 
resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat-eip.id
    subnet_id = aws_subnet.dmz_subnet.id
  

  tags = {
    Name ="SDK-nat-gw"
  }
 depends_on = [aws_internet_gateway.sdk-igw]
}
//create EIP for NAT    
resource "aws_eip" "nat-eip" {
    
  domain = "vpc" # Correctly specify that this is for a VPC
}


//app pri subnet
resource "aws_subnet" "app_subnet" {
 
  vpc_id = aws_vpc.vpc.id
  cidr_block = var.app_subnet_CIDR
  availability_zone = var.az
  tags = {
    Name ="SDK-app-subnet"
  }
}
//app-pri-rt
resource "aws_route_table" "sdk-pri-rt" {

  vpc_id = aws_vpc.vpc.id
  route{
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
//app-pri-rt-association
resource "aws_route_table_association" "sdk-app-pri-rt-association" {
  subnet_id = aws_subnet.app_subnet.id
  route_table_id = aws_route_table.sdk-pri-rt.id
}

resource "aws_subnet" "db-subnet" {
  vpc_id = aws_vpc.vpc.id
cidr_block = var.db_subnet_CIDR
availability_zone = var.az
tags = {
  Name = "SDK-db-subnet"
}
}
//DB-pri-rt-association
resource "aws_route_table_association" "sdk-db-pri-rt-association" {
  subnet_id = aws_subnet.db-subnet.id
  route_table_id = aws_route_table.sdk-pri-rt.id
}

resource "aws_security_group" "dmz-sg" {
  vpc_id = aws_vpc.vpc.id
  name = "dmz-sg"
  description = "dmz-sg"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
}
tags= {
Name= "dmz-sg"
}

  }


//dmz-NGINX server
resource "aws_instance" "nginx-server" {
    ami = var.ec2_ami
    instance_type = var.instance_type
    key_name = "tf-key"
      vpc_security_group_ids = [aws_security_group.dmz-sg.id]
associate_public_ip_address = true

    subnet_id = aws_subnet.dmz_subnet.id
    tags = {
      Name = "nginx-server"
    }
  
}
//-------------------------------------------------Part =2-application server---------------------------------------------------
//ecr repo
resource "aws_ecr_repository" "app-ecr-repo" {
  name = "app-ecr-repo"
    image_tag_mutability = "MUTABLE"
}
//ecs cluster
resource "aws_ecs_cluster" "app-ecs-cluster" {
  name = "app-ecs-cluster"

}
//ecs task defination
resource "aws_ecs_task_definition" "app-ecs-task-defination" {
  family = "app-ecs-task-defination"
  container_definitions = jsonencode([{
    name      = "python"
   image = "${aws_ecr_repository.app-ecr-repo.repository_url}:2"  # Update with your ECR URI"
    cpu       = 128
    memory    = 128
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80  
    }]
  }])
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
}

//app security group
resource "aws_security_group" "app-sg" {
    name        = "app-sg"
    vpc_id      = aws_vpc.vpc.id
    description = "Security group for the app"

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

    tags = {
        Name = "app-sg"
    }
}

//ecs service 

resource "aws_ecs_service" "app-ecs-service" {
name = "app-ecs-service"
cluster = aws_ecs_cluster.app-ecs-cluster.id
task_definition = aws_ecs_task_definition.app-ecs-task-defination.arn
desired_count = 1
launch_type = "FARGATE"
network_configuration {
  subnets = [aws_subnet.app_subnet.id]
  security_groups = [aws_security_group.app-sg.id]
  assign_public_ip = false
}

}


resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# // Launch Template
# resource "aws_launch_template" "ecs_launch_template" {
#   name_prefix = "ecs-launch-template"  // Using name_prefix instead of name
#   image_id    = var.ec2_ami
#   instance_type = var.instance_type
#   key_name      = "tf-key"
#   vpc_security_group_ids = [aws_security_group.app-sg.id]
#   // Security group IDs as a list
#   # security_group_names = [aws_security_group.app-sg.name]  

#   iam_instance_profile {
#     name = aws_iam_instance_profile.ecs_instance_profile.name
#   }

#  user_data = base64encode(<<EOF
# #!/bin/bash
# echo ECS_CLUSTER=app-ecs-cluster >> /etc/ecs/ecs.config
# EOF
# )
# }

# // Auto Scaling Group
# resource "aws_autoscaling_group" "ecs-asg" {
  


#   launch_template {
#     id      = aws_launch_template.ecs_launch_template.id
#   }

#   min_size            = 1
#   max_size            = 2
#   desired_capacity    = 1
#   vpc_zone_identifier = [aws_subnet.app_subnet.id]
#   tag {
#     key                 = "Name"
#     value               = "app-instance"
#     propagate_at_launch = true
#   }
# }

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance_role.name
}
