variable "region" {
  description = "AWS region where the instance is created"
  type        = string
  default     = "ap-southeast-2"
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS (noble) amd64 AMI ID"
  type        = string
  default     = "ami-048c1a9eb63a67eed"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "m7i-flex.large"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 40
}

variable "instance_name" {
  description = "Name tag for the instance"
  type        = string
  default     = "ubuntu-2404-server"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
  default     = "first-key"
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed to SSH (restrict to your IP, e.g. 203.0.113.10/32)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "subnet_id" {
  description = "Optional subnet ID. If null, the first default VPC subnet is used."
  type        = string
  default     = null
} 

variable "api_port" {
  description = "Port for the Kubernetes API (must match API_PORT in install.sh)"
  type        = number
  default     = 33893
}
