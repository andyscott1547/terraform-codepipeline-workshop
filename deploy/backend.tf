/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
   SPDX-License-Identifier: MIT-0 */

# https://www.terraform.io/language/settings/backends/configuration

# HTTP backend

# terraform {
#   backend "http" {}
# }

#Consul backend

# terraform {
#   backend "consul" {}
# }

# s3 + DynamoDB

# terraform {
#   backend "s3" {
#     bucket         = ""
#     key            = "deploy/terraform.tfstate"
#     region         = "eu-west-2"
#     encrypt        = true
#     dynamodb_table = ""
#   }
# }