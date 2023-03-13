# /main.tf

resource "aws_codecommit_repository" "codecommit" {
  repository_name = var.repo_name
  description     = var.repo_description
  default_branch  = var.branch_name
}

resource "aws_kms_key" "codebuild" {
  description             = "KMS key to encrypt the codebuild project"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "kms-tf-codebuild",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }
POLICY
}

resource "aws_kms_alias" "codebuild" {
  name          = "alias/tf-state-codebuild-${var.name}"
  target_key_id = aws_kms_key.codebuild.key_id
}

resource "aws_dynamodb_table" "this" {
  name           = local.name
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.ddb.arn
  }
  tags = {
    "Name" = local.name
  }
}

resource "aws_kms_key" "ddb" {
  description             = "KMS key used to encrypt organization management account ddb"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "kms-tf-ddb",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }
POLICY
}

resource "aws_kms_alias" "ddb" {
  name          = "alias/tf-state-ddb-${var.name}"
  target_key_id = aws_kms_key.ddb.key_id
}

resource "aws_s3_bucket" "this" {
  bucket        = local.name
  force_destroy = true
}

resource "aws_kms_key" "s3" {
  description             = "KMS key used to encrypt organization management account s3"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "kms-tf-s3",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      }
    ]
  }
POLICY
}

resource "aws_kms_alias" "s3" {
  name          = "alias/tf-state-s3-${var.name}"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_s3_bucket_acl" "this" {
  bucket = aws_s3_bucket.this.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "this" {
  count         = var.bucket_logging_enabled ? 1 : 0
  bucket        = aws_s3_bucket.this.id
  target_bucket = "s3-access-logs-${data.aws_caller_identity.current.account_id}"
  target_prefix = "${local.name}/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.enforce_tls.json
}

data "aws_iam_policy_document" "enforce_tls" {
  statement {
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = [
      "s3:*",
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/*",
      "${aws_s3_bucket.this.arn}"
    ]

    condition {
      test     = "Bool"
      values   = ["false"]
      variable = "aws:SecureTransport"
    }
  }
}

resource "null_resource" "upload_buildspecs" {
  depends_on = [
    aws_codecommit_repository.codecommit
  ]
  provisioner "local-exec" {
    environment = {
      REPO   = aws_codecommit_repository.codecommit.repository_name
      BRANCH = aws_codecommit_repository.codecommit.default_branch
    }
    command = <<EOT
        aws codecommit put-file \
            --repository-name $REPO \
            --branch-name $BRANCH \
            --file-content buildspecs/.tflint.hcl \
            --file-path buildspecs/.tflint.hcl

        for BUILDSPEC in $(ls buildspecs/*.yml)
        do
            echo "Uploading $BUILDSPEC to codecommit repo"

            COMMIT=$(aws codecommit get-branch --repository-name $REPO --branch-name $BRANCH --query branch.commitId --output text)
            BASE64FILE=$(base64 $BUILDSPEC)

            aws codecommit put-file \
            --repository-name $REPO \
            --branch-name $BRANCH \
            --file-content "$BASE64FILE" \
            --file-path $BUILDSPEC \
            --parent-commit-id $COMMIT
        done

        cd templates

        for TEMPLATE in $(ls)
        do
            echo "Uploading $TEMPLATE to codecommit repo"

            COMMIT=$(aws codecommit get-branch --repository-name $REPO --branch-name $BRANCH --query branch.commitId --output text)
            BASE64FILE=$(base64 $TEMPLATE)

            aws codecommit put-file \
            --repository-name $REPO \
            --branch-name $BRANCH \
            --file-content "$BASE64FILE" \
            --file-path $TEMPLATE \
            --parent-commit-id $COMMIT
        done
    EOT
  }

}

resource "aws_kms_key" "codepipeline_s3" {
  description             = "KMS key used to encrypt organization management account s3"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.codepipeline_s3.json
}

data "aws_iam_policy_document" "codepipeline_s3" {
  statement {
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root", "${aws_iam_role.codepipeline_role.arn}"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:Decrypt"
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["${local.execution_role.arn}", "${local.validate_role.arn}"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:Decrypt"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_kms_alias" "codepipeline_s3" {
  name          = "alias/codepipeline-s3-${var.name}"
  target_key_id = aws_kms_key.codepipeline_s3.key_id
}

resource "aws_codepipeline" "codepipeline" {
  depends_on = [
    null_resource.upload_buildspecs
  ]
  name     = "${var.name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = module.artefact_s3.bucket.id
    type     = "S3"

    encryption_key {
      id   = aws_kms_key.codepipeline_s3.arn
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = aws_codecommit_repository.codecommit.repository_name
        BranchName     = aws_codecommit_repository.codecommit.default_branch
      }
    }
  }

  stage {
    name = "Validate"

    action {
      name            = "Validate"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_validate.codebuild_project.name
      }
    }
    action {
      name            = "FMT"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_fmt.codebuild_project.name
      }
    }
    action {
      name            = "Lint"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_lint.codebuild_project.name
      }
    }
    action {
      name            = "SAST"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_sast.codebuild_project.name
      }
    }
  }

  stage {
    name = "Plan-Dev"

    action {
      name            = "Plan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_plan_dev.codebuild_project.name
      }
    }
  }
  stage {
    name = "Apply-Dev"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_apply_dev.codebuild_project.name
      }
    }
  }
  stage {
    name = "Test-Dev"

    action {
      name            = "Test"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_test_dev.codebuild_project.name
      }
    }
  }

  stage {
    name = "Plan-Test"

    action {
      name            = "Plan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_plan_test.codebuild_project.name
      }
    }
  }
  stage {
    name = "Apply-Test"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_apply_test.codebuild_project.name
      }
    }
  }
  stage {
    name = "Test-Test"

    action {
      name            = "Test"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_test_test.codebuild_project.name
      }
    }
  }

  stage {
    name = "Plan-Prod"

    action {
      name            = "Plan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_plan_prod.codebuild_project.name
      }
    }
  }
  stage {
    name = "Approve"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.codepipeline.arn
        CustomData      = "Please review and approve for ${var.name}-pipeline"
      }
    }
  }
  stage {
    name = "Apply-Prod"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_apply_prod.codebuild_project.name
      }
    }
  }
  stage {
    name = "Test-Prod"

    action {
      name            = "Test"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.tf_test_prod.codebuild_project.name
      }
    }
  }
}

resource "aws_kms_key" "codepipeline" {
  deletion_window_in_days = 7
  description             = "CodePipeline notification encryption key"
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.codepipeline.json
}

resource "aws_kms_alias" "codepipeline" {
  name          = "alias/codepiplien-notification-${var.name}"
  target_key_id = aws_kms_key.codepipeline.id
}

data "aws_iam_policy_document" "codepipeline" {
  statement {
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:List*",
      "kms:Describe*"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic" "codepipeline" {
  name              = "codepipeline-notifications-${var.name}-pipeline"
  kms_master_key_id = aws_kms_key.codepipeline.arn
}

resource "aws_sns_topic_subscription" "codepipeline" {
  for_each  = toset(var.subscribed_emails)
  topic_arn = aws_sns_topic.codepipeline.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.name}-pipeline-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:List*"
      ],
      "Resource": [
        "${module.artefact_s3.bucket.arn}",
        "${module.artefact_s3.bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codeCommit:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:GenerateDataKey",
        "kms:Decrypt"
      ],
      "Resource": "${aws_kms_key.codepipeline.arn}"
    }
  ]
}
EOF
}

resource "aws_iam_role" "this" {
  for_each           = toset(local.codebuild_roles)
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy" "codebuild_validate_role" {
  for_each = aws_iam_role.this
  role     = each.value.id

  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Resource" : [
            "*"
          ],
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ]
        },
        {
          "Effect" : "Allow",
          "Resource" : [
            "*"
          ],
          "Action" : [
            "codebuild:CreateReport",
            "codebuild:UpdateReport",
            "codebuild:BatchPutTestCases"
          ]
        },
        {
          "Effect" : "Allow",
          "Action" : [
            "s3:*"
          ],
          "Resource" : [
            "${module.artefact_s3.bucket.arn}",
            "${module.sast_s3.bucket.arn}",
            "${module.artefact_s3.bucket.arn}/*",
            "${module.sast_s3.bucket.arn}/*"
          ]
        }
      ]
    }
  )
}

resource "aws_iam_role_policy" "codebuild_execution_role" {

  role   = local.execution_role.name
  policy = var.codebuild_execution_policy
}

module "tf_validate" {
  source                = "./modules/codebuild"
  codebuild_name        = "${var.name}-pipeline-tf_validate"
  codebuild_role        = local.validate_role.arn
  environment_variables = var.environment_variables
  build_timeout         = 5
  build_spec            = "buildspecs/tf_validate.yml"
  codebuild_cmk         = aws_kms_key.codebuild.arn
}

module "tf_fmt" {
  source                = "./modules/codebuild"
  codebuild_name        = "${var.name}-pipeline-tf_fmt"
  codebuild_role        = local.validate_role.arn
  environment_variables = var.environment_variables
  build_timeout         = 5
  build_spec            = "buildspecs/tf_fmt.yml"
  codebuild_cmk         = aws_kms_key.codebuild.arn
}

module "tf_lint" {
  source                = "./modules/codebuild"
  codebuild_name        = "${var.name}-pipeline-tf_lint"
  codebuild_role        = local.validate_role.arn
  environment_variables = var.environment_variables
  build_timeout         = 5
  build_spec            = "buildspecs/tf_lint.yml"
  codebuild_cmk         = aws_kms_key.codebuild.arn
}

module "tf_sast" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_sast"
  codebuild_role = local.validate_role.arn
  environment_variables = merge(tomap({
    SAST_REPORT_ARN = aws_codebuild_report_group.sast.arn }),
    var.environment_variables,
  )
  build_timeout = 5
  build_spec    = "buildspecs/tf_sast.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_plan_dev" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_plan_dev"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Development",
    TF_WORKSPACE = "Development" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_plan.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_apply_dev" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_apply_dev"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Development",
    TF_WORKSPACE = "Development" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_apply.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_test_dev" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_test_dev"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Development" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_test.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_plan_test" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_plan_test"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Test",
    TF_WORKSPACE = "Test" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_plan.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_apply_test" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_apply_test"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Test",
    TF_WORKSPACE = "Test" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_apply.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_test_test" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_test_test"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Test" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_test.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_plan_prod" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_plan_prod"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Production",
    TF_WORKSPACE = "Production" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_plan.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_apply_prod" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_apply_prod"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Production",
    TF_WORKSPACE = "Production" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_apply.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

module "tf_test_prod" {
  source         = "./modules/codebuild"
  codebuild_name = "${var.name}-pipeline-tf_test_prod"
  codebuild_role = local.execution_role.arn
  environment_variables = merge(tomap({
    TF_VAR_environment = "Production" }),
    var.environment_variables,
  )
  build_timeout = 10
  build_spec    = "buildspecs/tf_test.yml"
  codebuild_cmk = aws_kms_key.codebuild.arn
}

resource "aws_kms_key" "code_build_sast" {
  description             = "KMS key used to encrypt SAST Scans in codebuild reports"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "kms-tf-1",
    "Statement": [
      {
        "Sid": "Enable IAM User Permissions",
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        "Action": "kms:*",
        "Resource": "*"
      },
      {
        "Sid": "Allow access through Amazon S3 for all principals in the account that are authorized to use Amazon S3",
        "Effect": "Allow",
        "Principal": {
          "AWS": "*"
        },
        "Action": [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        "Resource": "*",
        "Condition": {
          "StringEquals": {
            "kms:ViaService": "s3.${data.aws_region.current.name}.amazonaws.com",
            "kms:CallerAccount": "${data.aws_caller_identity.current.account_id}"
          }
        }
    },
        {
          "Effect": "Allow", 
          "Principal": {
            "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.validate_role.name}"
          },
          "Action": [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ],
          "Resource": "*"
        }
    ]
  }
POLICY
}

resource "aws_kms_alias" "code_build_sast" {
  name          = "alias/codebuild-reports_${var.name}"
  target_key_id = aws_kms_key.code_build_sast.key_id
}

module "sast_s3" {
  source                 = "./modules/s3"
  bucket_name            = "${var.name}-pipeline-sast-bucket-${data.aws_caller_identity.current.account_id}"
  bucket_logging_enabled = var.bucket_logging_enabled
}

module "artefact_s3" {
  source                 = "./modules/s3"
  bucket_name            = "${var.name}-pipeline-artefact-bucket-${data.aws_caller_identity.current.account_id}"
  bucket_logging_enabled = var.bucket_logging_enabled
}

resource "aws_codebuild_report_group" "sast" {
  name           = "Checkov-SAST-${var.name}-pipeline"
  type           = "TEST"
  delete_reports = true

  export_config {
    type = "S3"

    s3_destination {
      bucket              = module.sast_s3.bucket.id
      encryption_disabled = false
      encryption_key      = aws_kms_key.code_build_sast.arn
      packaging           = "NONE"
      path                = "/checkov"
    }
  }
}