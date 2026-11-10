variable "name" {
  type = string
}

variable "max_image_count" {
  type    = number
  default = 30
}

variable "force_delete" {
  description = "Allow terraform destroy to delete a repository that still has images."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
