# =============================================================================
# UI bootstrap bundle in S3.
#
# The client invoker EC2 fetches the FastAPI UI, its deps, templates, static
# assets, scenarios.json, and the terraform-generated rules.json from this
# bucket at first boot. Keeps user_data small and lets us refresh the UI by
# re-uploading objects (instead of replacing the instance).
#
# Bundle layout on EC2:
#   /opt/agentcore-ui/                       <-- working dir (sys.path root)
#     ui/                                    <-- python package
#       app.py, runtime_client.py, simulation.py, scenario_loader.py,
#       rules_catalog.py, evidence_builder.py, drift_handler.py,
#       __init__.py, scenarios.json, rules.json,
#       templates/, static/
#     venv/                                  <-- created by user_data
#     requirements.txt
#
# That's why every python-module / template / static-asset S3 key starts
# with "ui/ui/" — bucket prefix "ui/" syncs into /opt/agentcore-ui/, which
# means files end up under /opt/agentcore-ui/ui/...
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

# ---- Python modules ---------------------------------------------------------

resource "aws_s3_object" "ui_app" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/app.py"
  source = "${path.module}/ui/app.py"
  etag   = filemd5("${path.module}/ui/app.py")
}

resource "aws_s3_object" "ui_init" {
  bucket  = aws_s3_bucket.ui.id
  key     = "ui/ui/__init__.py"
  content = ""
  etag    = md5("")
}

resource "aws_s3_object" "ui_runtime_client" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/runtime_client.py"
  source = "${path.module}/ui/runtime_client.py"
  etag   = filemd5("${path.module}/ui/runtime_client.py")
}

resource "aws_s3_object" "ui_simulation" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/simulation.py"
  source = "${path.module}/ui/simulation.py"
  etag   = filemd5("${path.module}/ui/simulation.py")
}

resource "aws_s3_object" "ui_scenario_loader" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/scenario_loader.py"
  source = "${path.module}/ui/scenario_loader.py"
  etag   = filemd5("${path.module}/ui/scenario_loader.py")
}

resource "aws_s3_object" "ui_rules_catalog" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/rules_catalog.py"
  source = "${path.module}/ui/rules_catalog.py"
  etag   = filemd5("${path.module}/ui/rules_catalog.py")
}

resource "aws_s3_object" "ui_evidence_builder" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/evidence_builder.py"
  source = "${path.module}/ui/evidence_builder.py"
  etag   = filemd5("${path.module}/ui/evidence_builder.py")
}

resource "aws_s3_object" "ui_drift_handler" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/drift_handler.py"
  source = "${path.module}/ui/drift_handler.py"
  etag   = filemd5("${path.module}/ui/drift_handler.py")
}

# ---- Data files -------------------------------------------------------------

resource "aws_s3_object" "ui_scenarios_json" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/scenarios.json"
  source = "${path.module}/ui/scenarios.json"
  etag   = filemd5("${path.module}/ui/scenarios.json")
}

# rules.json is rendered by local_file.ui_rules_json in ui-rules.tf.
# Use the resource's content_md5 attribute for the etag so terraform plan
# doesn't try to read the file before local_file has written it.
resource "aws_s3_object" "ui_rules_json" {
  bucket = aws_s3_bucket.ui.id
  key    = "ui/ui/rules.json"
  source = local_file.ui_rules_json.filename
  etag   = local_file.ui_rules_json.content_md5

  depends_on = [local_file.ui_rules_json]
}

# ---- Package-level files (one level above the ui/ package) -----------------

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

# ---- Templates --------------------------------------------------------------

resource "aws_s3_object" "ui_template_files" {
  for_each = fileset("${path.module}/ui/templates", "**/*.html")
  bucket   = aws_s3_bucket.ui.id
  key      = "ui/ui/templates/${each.value}"
  source   = "${path.module}/ui/templates/${each.value}"
  etag     = filemd5("${path.module}/ui/templates/${each.value}")
}

# ---- Static assets ----------------------------------------------------------

resource "aws_s3_object" "ui_static_files" {
  for_each = fileset("${path.module}/ui/static", "**/*")
  bucket   = aws_s3_bucket.ui.id
  key      = "ui/ui/static/${each.value}"
  source   = "${path.module}/ui/static/${each.value}"
  etag     = filemd5("${path.module}/ui/static/${each.value}")
}

# ---- IAM read permission for the client invoker EC2 -----------------------

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
