/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
   SPDX-License-Identifier: MIT-0 */

variable "environment_variables" {
  description = "Env vars for build project"
  type        = map(string)
}

variable "build_timeout" {
  description = "How long to wait before timing out the the build"
  type        = number
  default     = 10
}

variable "build_spec" {
  description = "Build spec yaml"
  type        = string
}

variable "codebuild_name" {
  description = "Name of codebuild project"
  type        = string
}

variable "codebuild_role" {
  description = "Execution role for codebuild projects"
  type        = string
}

variable "codebuild_cmk" {
  description = "KMS key to encrypt the codebuild project"
  type        = string
}