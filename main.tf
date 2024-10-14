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
        subnet_id = aws_subnet.dmz_subnet.id
  
allocation_id = aws_eip.nat-eip.id
  tags = {
    Name ="SDK-nat-gw"
  }
 depends_on = [aws_internet_gateway.sdk-igw]
}
//create EIP for NAT    
resource "aws_eip" "nat-eip" {
    
  domain = "vpc"
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

# resource "aws_subnet" "db-subnet" {
#   vpc_id = aws_vpc.vpc.id
# cidr_block = var.db_subnet_CIDR
# availability_zone = var.az
# # tags = {
# #   Name = "SDK-db-subnet"
# # }
# }
# //DB-pri-rt-association
# resource "aws_route_table_association" "sdk-db-pri-rt-association" {
#   subnet_id = aws_subnet.db-subnet.id
#   route_table_id = aws_route_table.sdk-pri-rt.id
# }

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

 
# lifecycle {
#   prevent_destroy = true
# }
  tags = {
    Name = "NGINX-Server"
  }
}
  
//-------------------------------------------------Part =2-application server---------------------------------------------------
//ecr repo
resource "aws_ecr_repository" "app-ecr-repo" {
  name = "app-ecr-repository"
    image_tag_mutability = "MUTABLE"
}

//ecs cluster
resource "aws_ecs_cluster" "app-ecs-cluster" {
  name = "app-ecs-cluster"


}


// Launch Template
// Launch Template
resource "aws_launch_template" "ecs_launch_config" {
  name_prefix    = "ecs-launch-config"  // Using name_prefix instead of name
  image_id       = "ami-0d1622042e957c247"
  instance_type  = var.instance_type
  key_name       = "tf-key"

  iam_instance_profile { 
    name = aws_iam_instance_profile.ecs_instance_profile.name  // Correctly reference the instance profile
  }
  
  user_data = base64encode(<<EOF
#!/bin/bash
sudo apt update
sudo apt install -y ecs-init
echo ECS_CLUSTER=app-ecs-cluster >> /etc/ecs/ecs.config
sudo systemctl start ecs

EOF
)

  // Optional: Specify additional settings
  // network_interfaces {
  //   associate_public_ip_address = true  // If you need public IPs
  //   subnet_id = aws_subnet.public_subnet.id  // Specify your subnet
  // }
}
resource "aws_autoscaling_group" "ecs-asg" {
  desired_capacity = 1
  max_size = 2
  min_size = 1
  vpc_zone_identifier = [aws_subnet.app_subnet.id]
  launch_template {
    id = aws_launch_template.ecs_launch_config.id
    version = "$Latest"
  }
  tag {
    key = "Name"
    value = "app-instance"
    propagate_at_launch = true
  }
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecsInstanceRole-app"

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
  name = "ecsInstanceProfilenew"
  role = aws_iam_role.ecs_instance_role.name
}
//ecs task defination
resource "aws_ecs_task_definition" "app-ecs-task-defination" {
  family = "app-ecs-task-defination"
  container_definitions = jsonencode([{
    name      = "Nginx"
   image = "${aws_ecr_repository.app-ecr-repo.repository_url}:latest"  # Update with your ECR URI"
    cpu       = 256
    memory    = 512
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80  
    }]
  }])
  network_mode            = "awsvpc"
  requires_compatibilities = ["EC2"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
}
//ecs service 

resource "aws_ecs_service" "app-ecs-service" {
name = "app-ecs-service"
cluster = aws_ecs_cluster.app-ecs-cluster.id
task_definition = aws_ecs_task_definition.app-ecs-task-defination.arn
desired_count = 1
launch_type = "EC2"
network_configuration {
  subnets = [aws_subnet.app_subnet.id]
  security_groups = [aws_security_group.app-sg.id]

}

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
    
    ingress {
        from_port   = 22
        to_port     = 22
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
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "app-sg"
    }
}



resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-"

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


