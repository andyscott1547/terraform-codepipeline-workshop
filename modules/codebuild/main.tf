/* Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
   SPDX-License-Identifier: MIT-0 */

resource "aws_codebuild_project" "this" {
  name           = var.codebuild_name
  build_timeout  = var.build_timeout
  service_role   = var.codebuild_role
  encryption_key = var.codebuild_cmk

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:3.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    dynamic "environment_variable" {
      for_each = var.environment_variables
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }

  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${var.codebuild_name}"
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = var.build_spec
  }
}

