# terraform -chdir=modules/s3-bucket test
# Mock provider: no AWS account, no credentials, no cost. Only plans are checked.
mock_provider "aws" {}

variables {
  name = "plat-test-bucket"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "plat-test-bucket"
    error_message = "The bucket must use the name that was passed in."
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 1
    error_message = "Versioning must be on by default."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 0
    error_message = "No lifecycle configuration unless rules are given."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = !aws_s3_bucket.this.force_destroy
    error_message = "force_destroy must default to false."
  }
}

run "versioning_can_be_turned_off" {
  command = plan

  variables {
    versioning = false
  }

  assert {
    condition     = length(aws_s3_bucket_versioning.this) == 0
    error_message = "versioning = false must not create a versioning resource."
  }
}

run "lifecycle_and_prefixes" {
  command = plan

  variables {
    prefixes = ["raw/", "processed/"]
    lifecycle_rules = [
      { id = "a", noncurrent_expiration_days = 30 },
      { id = "b", prefix = "raw/", transition_days = 30 },
    ]
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this) == 1
    error_message = "Rules must create exactly one lifecycle configuration."
  }

  assert {
    condition     = length(aws_s3_object.prefix) == 2
    error_message = "One marker object per prefix."
  }
}
