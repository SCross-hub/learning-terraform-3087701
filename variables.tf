# variables.tf

variable "key_name" {
  description = "The name of the key pair to use for the instances"
  type        = string
}

variable "instance_type" {
  description = "The type of instance to start"
  type        = string
  default     = "t3.micro"  # Replace with your preferred instance type
}
