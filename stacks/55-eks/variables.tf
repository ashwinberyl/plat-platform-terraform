variable "region" {
  type    = string
  default = "us-east-1"
}

variable "enable_eks" {
  description = "Create the cluster and node group. The control plane bills about $0.10 per hour plus the nodes."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Null lets EKS choose its current default version."
  type        = string
  default     = null
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_desired" {
  type    = number
  default = 1
}

variable "service_account" {
  description = "Kubernetes service account that receives the pod role."
  type        = string
  default     = "plat-api"
}
