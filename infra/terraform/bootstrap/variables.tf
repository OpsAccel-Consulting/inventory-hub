variable "project" {
  description = "Project name, used as the bucket name prefix."
  type        = string
  default     = "inventory-hub"
}

variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "ap-south-1"
}
