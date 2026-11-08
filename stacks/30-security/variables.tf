variable "region" {
  type    = string
  default = "us-east-1"
}

variable "secret_recovery_window_days" {
  description = "0 deletes the secret immediately on destroy (handy for labs). Use 7 to 30 for anything real."
  type        = number
  default     = 0
}

variable "enable_secretsmanager_endpoint" {
  description = "Interface endpoint for Secrets Manager. Billed per hour per AZ."
  type        = bool
  default     = false
}

variable "grant_demo_reader_decrypt" {
  description = "Give the plat-demo-reader role kms:Decrypt on the key. Leave false first to reproduce 'S3 allowed, KMS denied' (Post 05)."
  type        = bool
  default     = false
}
