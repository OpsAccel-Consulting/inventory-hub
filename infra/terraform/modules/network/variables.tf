variable "name" {
  description = "Name prefix for all network resources."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block. Must be a /16 for the default subnet math."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across (2 or 3)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "Provide 2 or 3 availability zones."
  }
}

variable "cluster_name" {
  description = "EKS cluster name, used for subnet discovery tags."
  type        = string
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper, non-HA). Set false for production."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send rejected-traffic VPC flow logs to CloudWatch."
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  type    = number
  default = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}
