variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Check the EKS version calendar before changing."
  type        = string
  default     = "1.35"
}

variable "support_type" {
  description = "STANDARD (auto-upgrade at end of standard support) or EXTENDED (paid)."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control-plane ENIs and worker nodes."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Restrict to your office/VPN IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "admin_principal_arns" {
  description = "Extra IAM role/user ARNs granted cluster-admin via access entries."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
