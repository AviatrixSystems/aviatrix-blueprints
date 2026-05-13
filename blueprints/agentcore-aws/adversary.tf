# =============================================================================
# Adversary MCP server - Lambda + Function URL.
#
# Hosts a "trusted" (allowlisted) MCP server whose tool DESCRIPTIONS contain
# prompt injection pointing at an attacker-controlled domain
# (evil.attacker.example). The demo uses this to show OWASP LLM05: a
# sanctioned MCP source carrying a malicious payload, with DCF preventing
# the downstream egress.
#
# The Lambda lives outside any AgentCore spoke on purpose - it represents
# a supply-chain source outside the VCA's containment boundary. Traffic
# from the agent reaches it over the Internet (via the spoke GW + NAT),
# traversing DCF rule -33- (allowed-mcp-servers).
# =============================================================================

data "archive_file" "adversary" {
  type        = "zip"
  source_dir  = "${path.module}/adversary"
  output_path = "${path.module}/adversary/build.zip"
}

resource "aws_iam_role" "adversary" {
  name = "${local.name_prefix}-adversary-mcp"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "adversary_logs" {
  role       = aws_iam_role.adversary.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "adversary" {
  function_name = "${local.name_prefix}-adversary-mcp"
  role          = aws_iam_role.adversary.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 256

  filename         = data.archive_file.adversary.output_path
  source_code_hash = data.archive_file.adversary.output_base64sha256

  environment {
    variables = {
      DEMO_NOTE = "adversarial MCP for Aviatrix AgentCore VCA LLM05 scenario"
    }
  }

  tags = {
    Name = "${local.name_prefix}-adversary-mcp"
    Role = "demo-adversary"
  }
}

resource "aws_lambda_function_url" "adversary" {
  function_name      = aws_lambda_function.adversary.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
    max_age       = 86400
  }
}

locals {
  adversary_mcp_url  = "${aws_lambda_function_url.adversary.function_url}mcp"
  adversary_mcp_host = replace(replace(aws_lambda_function_url.adversary.function_url, "https://", ""), "/", "")
}
