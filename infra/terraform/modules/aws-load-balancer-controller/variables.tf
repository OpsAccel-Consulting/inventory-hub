variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "chart_version" {
  description = "eks-charts/aws-load-balancer-controller chart version."
  type        = string
  default     = "3.6.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
