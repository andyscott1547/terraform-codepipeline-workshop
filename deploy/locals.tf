# /locals.tf

locals {
  tags = {
    Product     = "CC Organization"
    Owner       = "CMDG"
    BillingID   = "CAS"
    ProjectCode = "PR008435"
    ServiceName = "Compliance Cloud Landing Zone"
    Env         = "Organization"
    Type        = "LZ"
    Automation  = "True"
  }
  codebuild_roles = ["codebuild_execution_role", "codebuild_validate_role"]

  execution_role = lookup(aws_iam_role.this, "codebuild_execution_role")
  validate_role  = lookup(aws_iam_role.this, "codebuild_validate_role")
  name           = "${var.name}-${data.aws_caller_identity.current.account_id}"
}
