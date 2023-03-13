# /locals.tf

locals {
  tags = {
    Product     = "DevOps_Workshop"
    Owner       = "BJSS"
    BillingID   = "Notts-12345"
    ProjectCode = "12345"
    Automation  = "True"
  }
  codebuild_roles = ["codebuild_execution_role", "codebuild_validate_role"]

  execution_role = lookup(aws_iam_role.this, "codebuild_execution_role")
  validate_role  = lookup(aws_iam_role.this, "codebuild_validate_role")
  name           = "${var.name}-tf-state-${data.aws_caller_identity.current.account_id}"
}
