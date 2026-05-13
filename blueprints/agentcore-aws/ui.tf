# =============================================================================
# UI bootstrap bundle in S3.
#
# The client invoker EC2 fetches the Streamlit UI, its deps, and the
# scenarios data from this bucket at first boot. Keeps user_data small
# and lets us refresh the UI later by re-uploading objects (instead of
# replacing the instance).
# =============================================================================

resource "random_id" "ui_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "ui" {
  bucket        = "${local.name_prefix}-ui-${random_id.ui_bucket.hex}"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-ui" }
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket                  = aws_s3_bucket.ui.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "ui_app" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/app.py"
  source = "${path.module}/ui/app.py"
  etag   = filemd5("${path.module}/ui/app.py")
}

resource "aws_s3_object" "ui_scenarios_py" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/scenarios.py"
  source = "${path.module}/ui/scenarios.py"
  etag   = filemd5("${path.module}/ui/scenarios.py")
}

resource "aws_s3_object" "ui_scenarios_json" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/scenarios.json"
  source = "${path.module}/ui/scenarios.json"
  etag   = filemd5("${path.module}/ui/scenarios.json")
}

resource "aws_s3_object" "ui_requirements" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/requirements.txt"
  source = "${path.module}/ui/requirements.txt"
  etag   = filemd5("${path.module}/ui/requirements.txt")
}

resource "aws_s3_object" "ui_service" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/agentcore-ui.service"
  source = "${path.module}/ui/agentcore-ui.service"
  etag   = filemd5("${path.module}/ui/agentcore-ui.service")
}

# Grant the client invoker EC2 role permission to read UI bundle objects
data "aws_iam_policy_document" "ui_read" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.ui.arn,
      "${aws_s3_bucket.ui.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "client_invoker_ui_read" {
  name   = "ui-bundle-read"
  role   = aws_iam_role.client_invoker.id
  policy = data.aws_iam_policy_document.ui_read.json
}
