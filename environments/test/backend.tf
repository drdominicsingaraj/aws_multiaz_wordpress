# Remote state is opt-in. By default this environment uses local state (each environment
# directory has its own, so dev/test/prod never share it).
#
# To store state in S3 with locking and versioning:
#   1. once per account: cd bootstrap && terraform init && terraform apply
#   2. replace this file with the `backend_snippet` output of the bootstrap (key = "deham9/test/terraform.tfstate")
#   3. terraform init -migrate-state
#
# terraform {
#   backend "s3" {
#     bucket         = "deham9-terraform-state-<account id>"
#     key            = "deham9/test/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "deham9-terraform-locks"
#     encrypt        = true
#   }
# }
