# /config.auto.tfvars

region                 = "eu-west-2"
pipeline_name          = ""
repo_name              = ""
repo_description       = ""
# bucket_logging_enabled = true
subscribed_emails      = [""]
environment_variables = {
  TF_VERSION     = "1.1.7"
  TFLINT_VERSION = "0.33.0"
}
name = "lz-dev-appstream-tf-state"