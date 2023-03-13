# /variables.tf

variable "region" {
  description = "region for deployment"
  type        = string
}

variable "bucket_logging_enabled" {
  description = "Enable bucket access logging or not"
  type        = bool
  default     = false
}

variable "pipeline_name" {
  description = "pipeline name"
  type        = string
}

variable "repo_name" {
  description = "repository name"
  type        = string
}

variable "branch_name" {
  description = "branch name"
  type        = string
  default     = "main"
}

variable "repo_description" {
  description = "Description for repository"
  type        = string
}

variable "subscribed_emails" {
  description = "List of emails to subscribe to sns codepipeline manual approval notifictaions"
  type        = list(string)
  default     = []
}

variable "environment_variables" {
  description = "Env vars for build project"
  type        = map(string)
}

variable "codebuild_execution_policy" {
  description = "custom IAM policy with perms to allow codebuild to plan and apply terraform"
  type        = string
  default     = <<EOL
{
  "Version" : "2012-10-17",
  "Statement" : [
    {
      "Effect": "Allow",
      "Resource": "*",
      "Action": [
        "sts:*",
        "s3:*",
        "dynamodb:*",
        "account:*",
        "organizations:*",
        "kms:*"
      ]
    }
  ]
}
EOL
}

variable "name" {
  description = "Name for the S3 bucket and DDB table used to store TF State"
  type        = string
}
