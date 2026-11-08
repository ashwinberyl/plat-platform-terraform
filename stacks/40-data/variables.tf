variable "region" {
  type    = string
  default = "us-east-1"
}

variable "force_destroy_bucket" {
  description = "Lab convenience: let destroy empty the bucket. Set false for real data."
  type        = bool
  default     = true
}

variable "enable_rds" {
  description = "RDS bills every hour. Off by default."
  type        = bool
  default     = false
}

variable "restore_snapshot_identifier" {
  description = "Restore plat-meta from this snapshot (for example plat-meta-final) instead of creating an empty database."
  type        = string
  default     = null
}

variable "rds_skip_final_snapshot" {
  description = "false keeps a final snapshot called plat-meta-final when the instance is destroyed."
  type        = bool
  default     = false
}

variable "jobs_table_deletion_protection" {
  type    = bool
  default = false
}
