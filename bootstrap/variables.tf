variable "region" {
  description = "Region for the state bucket and everything else in the lab."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository allowed to assume the CI roles."
  type        = string
  default     = "ashwinberyl"
}

variable "github_repo" {
  description = "Repository allowed to assume the CI roles."
  type        = string
  default     = "plat-platform-terraform"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if this account already has one (only one per URL is allowed)."
  type        = bool
  default     = true
}

variable "enable_ci_roles" {
  description = "Create the plan and apply roles that GitHub Actions assumes."
  type        = bool
  default     = true
}
