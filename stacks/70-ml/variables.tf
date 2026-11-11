variable "region" {
  type    = string
  default = "us-east-1"
}

variable "studio_users" {
  description = "One SageMaker user profile per name (letters, digits, hyphens)."
  type        = set(string)
  default     = ["jim", "dave"]
}

variable "enable_studio" {
  description = "Create the Studio domain, its security group and the user profiles. Free until someone opens an app."
  type        = bool
  default     = true
}

variable "enable_endpoint" {
  description = "Create the real-time endpoint. Billed every hour. Also needs model_data_url."
  type        = bool
  default     = false
}

variable "model_data_url" {
  description = "s3:// URL of the model.tar.gz a training job produced (Post 13 lab)."
  type        = string
  default     = null
}

variable "inference_image" {
  description = "Container that serves the model. The default is the built-in XGBoost image for us-east-1."
  type        = string
  default     = "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-xgboost:1.7-1"
}

variable "endpoint_instance_type" {
  type    = string
  default = "ml.t2.medium"
}
