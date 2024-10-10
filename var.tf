variable "vpc-cidr" {
    description = "Vpc CIDR"
    default ="11.0.0.0/16"   
}
variable "az" {
  description = "AZs"
  type = string
  default = "ap-south-1a"
  
}

variable "dmz_subnet_CIDR" {
description ="public subnet CIDR"
type = string
default = "11.0.1.0/24"
  
}

variable "app_subnet_CIDR" {
    description ="private subnet CIDR"
    type = string
    default ="11.0.2.0/24"
}
variable "db_subnet_CIDR" {
  description = "db subnet"
  type = string
  default = "11.0.3.0/24"
  
}
variable "health_check" {
description = "health check"
type = object({
  path = string
  interval=number
  timeout=number
  healthy_threshold=number
  unhealthy_threshold=number
})
default = {
  path = "/"
  interval = 30
  timeout = 5
  healthy_threshold = 2
  unhealthy_threshold = 2


}
}

variable "ec2_ami" {
  description = "AMI for the EC2 instance"
  default = "ami-0dee22c13ea7a9a67"
}

variable "instance_type" {
  description = "EC2 instance type"
  default     = "t2.micro"
}

variable "desired_count" {
  description = "Desired no. of ECS instances"
  default     = 1
}

variable "max_size" {
  description = "Maximum no. of ECS instances"
  default     = 5
}
