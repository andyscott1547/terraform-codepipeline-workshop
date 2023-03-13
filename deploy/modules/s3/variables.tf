/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
   SPDX-License-Identifier: MIT-0 */

variable "bucket_name" {
  description = "Name of s3 bucket"
  type        = string
}

variable "bucket_logging_enabled" {
  description = "Enable bucket access logging or not"
  type        = bool
}