variable "region" {
  description = "Identity Center must be enabled in this region, and the region must stay the same."
  type        = string
  default     = "us-east-1"
}

variable "users" {
  description = "Identity Center users. Put real values in terraform.tfvars (git-ignored); see terraform.tfvars.example."
  type = map(object({
    given_name  = string
    family_name = string
    email       = string
    groups      = list(string)
  }))
  default = {}
}

variable "admin_session_duration" {
  description = "ISO 8601 duration for the PlatformAdmin permission set."
  type        = string
  default     = "PT4H"
}

variable "scientist_session_duration" {
  description = "ISO 8601 duration for the DataScientist permission set."
  type        = string
  default     = "PT1H"
}
