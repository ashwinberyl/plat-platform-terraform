variable "name" {
  description = "Bucket name (globally unique)."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed key for SSE-KMS. Null means SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "versioning" {
  description = "Keep old versions of overwritten and deleted objects."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete a non-empty bucket. Lab convenience, never for real data."
  type        = bool
  default     = false
}

variable "prefixes" {
  description = "Zero-byte 'folder' marker objects to create, each ending in a slash."
  type        = list(string)
  default     = []
}

variable "lifecycle_rules" {
  description = "Lifecycle rules. Leave a field out to skip it."
  type = list(object({
    id                                 = string
    prefix                             = optional(string, "")
    noncurrent_expiration_days         = optional(number)
    abort_incomplete_multipart_days    = optional(number)
    transition_days                    = optional(number)
    transition_storage_class           = optional(string, "STANDARD_IA")
    expiration_days                    = optional(number)
    expired_object_delete_marker_clean = optional(bool, false)
  }))
  default = []
}
