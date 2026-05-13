# =============================================================================
# IAM for the AgentCore VCA
#
#   1. agentcore_runtime - execution role the AgentCore Runtime assumes.
#      Trust principal = bedrock-agentcore.amazonaws.com, scoped with
#      aws:SourceAccount / aws:SourceArn to prevent confused deputy.
#
#   2. agentcore_vpc_mode_guardrail - managed policy intended to be attached
#      to IAM principals allowed to Create* AgentCore resources. Enforces that
#      the subnets and security groups in the request come from the approved
#      AgentCore spoke set - blocks PUBLIC mode and foreign-VPC attachment
#      at the API, before DCF sees the first packet.
#
#   3. client_invoker - instance profile for the test EC2 in the client spoke,
#      permitted to call InvokeAgentRuntime.
# =============================================================================

# -----------------------------------------------------------------------------
# AgentCore Runtime execution role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "agentcore_runtime_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:*",
      ]
    }
  }
}

resource "aws_iam_role" "agentcore_runtime" {
  name               = "${var.name_prefix}-runtime-exec"
  assume_role_policy = data.aws_iam_policy_document.agentcore_runtime_trust.json
  description        = "Execution role for the sample AgentCore Runtime in this VCA"
}

data "aws_iam_policy_document" "agentcore_runtime_inline" {
  # Bedrock model invocation. Claude Haiku 4.5 uses the cross-region
  # inference profile (us. prefix); IAM needs both the profile ARN and the
  # underlying foundation-model ARNs in every region the profile fans out
  # to (us-east-1, us-east-2, us-west-2).
  statement {
    sid     = "InvokeBedrockModel"
    effect  = "Allow"
    actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
    resources = [
      # Inference profiles (account-scoped)
      "arn:aws:bedrock:${var.aws_region}:${local.account_id}:inference-profile/us.anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:${var.aws_region}:${local.account_id}:inference-profile/us.anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:${var.aws_region}:${local.account_id}:inference-profile/us.anthropic.claude-3-haiku-*",
      # Foundation models (fan-out regions for the us. profile)
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-haiku-4-5-*",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-5-haiku-*",
      "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-haiku-*",
      "arn:aws:bedrock:us-east-2::foundation-model/anthropic.claude-3-haiku-*",
      "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-3-haiku-*",
    ]
  }

  # Newer Anthropic models on Bedrock require the invoking principal to
  # have AWS Marketplace subscription visibility for the model product.
  # Without this, InvokeModel returns AccessDeniedException pointing at
  # aws-marketplace:ViewSubscriptions / Subscribe. Scope kept to Anthropic
  # product types via the marketplace ProductType condition is not
  # supported here, so we allow the two read/subscribe actions at *.
  statement {
    sid    = "BedrockMarketplaceSubscriptions"
    effect = "Allow"
    actions = [
      "aws-marketplace:ViewSubscriptions",
      "aws-marketplace:Subscribe",
    ]
    resources = ["*"]
  }

  # ECR pull for the container image
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = [aws_ecr_repository.agent.arn]
  }

  # CloudWatch Logs for agent observability
  statement {
    sid    = "CwLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/bedrock-agentcore/*",
    ]
  }

  # X-Ray tracing
  statement {
    sid    = "Xray"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "agentcore_runtime_inline" {
  name   = "runtime-exec-inline"
  role   = aws_iam_role.agentcore_runtime.id
  policy = data.aws_iam_policy_document.agentcore_runtime_inline.json
}

# -----------------------------------------------------------------------------
# VPC-mode guardrail policy (Risky Pattern #6 from the PRD)
#
# Attach to humans/roles allowed to manage AgentCore. Blocks:
#   - Creates where networkModeConfig is PUBLIC
#   - Creates where the subnets aren't from our approved AgentCore spoke set
#   - Creates where the security groups aren't from our approved set
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "vpc_mode_guardrail" {
  # (1) Catches PUBLIC mode: the request has NO subnets key at all.
  # Use a Null condition to explicitly deny when the key is absent.
  # Without this statement, ForAnyValue on a missing key evaluates to
  # FALSE (not TRUE), so the foreign-subnet Deny below wouldn't fire
  # and PUBLIC-mode Creates would sneak through.
  statement {
    sid    = "DenyPublicModeCreate"
    effect = "Deny"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:UpdateAgentRuntime",
      "bedrock-agentcore:CreateBrowser",
      "bedrock-agentcore:CreateCodeInterpreter",
    ]
    resources = ["*"]

    condition {
      test     = "Null"
      variable = "bedrock-agentcore:subnets"
      values   = ["true"] # "true" means key IS null (absent)
    }
  }

  # (2) Catches foreign-subnet placement: VPC-mode Creates whose subnets
  # are not the approved runtime subnet.
  statement {
    sid    = "DenyForeignSubnets"
    effect = "Deny"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:UpdateAgentRuntime",
      "bedrock-agentcore:CreateBrowser",
      "bedrock-agentcore:CreateCodeInterpreter",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringNotEquals"
      variable = "bedrock-agentcore:subnets"
      values   = [aws_subnet.agentcore_runtime.id]
    }
  }

  # (3) Catches foreign-security-group placement.
  statement {
    sid    = "DenyForeignSecurityGroups"
    effect = "Deny"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:UpdateAgentRuntime",
      "bedrock-agentcore:CreateBrowser",
      "bedrock-agentcore:CreateCodeInterpreter",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringNotEquals"
      variable = "bedrock-agentcore:securityGroups"
      values   = [aws_security_group.runtime.id]
    }
  }
}

resource "aws_iam_policy" "vpc_mode_guardrail" {
  name        = "${var.name_prefix}-agentcore-vpc-mode-guardrail"
  description = "Denies AgentCore Create* actions unless subnets/SGs come from the approved AgentCore spoke set. Attach to admins."
  policy      = data.aws_iam_policy_document.vpc_mode_guardrail.json
}

# -----------------------------------------------------------------------------
# Client invoker EC2 instance profile
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "client_invoker_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "client_invoker" {
  name               = "${var.name_prefix}-client-invoker"
  assume_role_policy = data.aws_iam_policy_document.client_invoker_trust.json
}

data "aws_iam_policy_document" "client_invoker_inline" {
  statement {
    sid       = "InvokeAgentCoreRuntime"
    effect    = "Allow"
    actions   = ["bedrock-agentcore:InvokeAgentRuntime"]
    resources = ["arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:runtime/*"]
  }

  # For the drift scenario: the UI attempts CreateAgentRuntime with a
  # PUBLIC network mode. We grant the action but let the VPC-mode
  # guardrail policy (attached below) deny it when the subnets/SGs
  # don't come from the approved set.
  statement {
    sid    = "CreateAgentRuntimeDriftDemo"
    effect = "Allow"
    actions = [
      "bedrock-agentcore:CreateAgentRuntime",
      # CreateAgentRuntime implicitly checks CreateAgentRuntimeEndpoint too;
      # without it the request is implicitly denied BEFORE the VPC-mode
      # guardrail can evaluate, which muddles the drift demo's narrative.
      "bedrock-agentcore:CreateAgentRuntimeEndpoint",
      "bedrock-agentcore:ListAgentRuntimes",
      "bedrock-agentcore:GetAgentRuntime",
      "bedrock-agentcore:DeleteAgentRuntime",
    ]
    resources = ["*"]
  }

  # PassRole so the UI can supply the runtime execution role in a
  # drift CreateAgentRuntime call.
  statement {
    sid       = "PassRuntimeRoleForDriftDemo"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.agentcore_runtime.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["bedrock-agentcore.amazonaws.com"]
    }
  }

  statement {
    sid    = "SsmCore"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

# Attach the VPC-mode guardrail to the client invoker role so the drift
# scenario in the UI demonstrates the prevention layer end-to-end.
resource "aws_iam_role_policy_attachment" "client_invoker_guardrail" {
  role       = aws_iam_role.client_invoker.name
  policy_arn = aws_iam_policy.vpc_mode_guardrail.arn
}

resource "aws_iam_role_policy" "client_invoker_inline" {
  name   = "client-invoker-inline"
  role   = aws_iam_role.client_invoker.id
  policy = data.aws_iam_policy_document.client_invoker_inline.json
}

resource "aws_iam_instance_profile" "client_invoker" {
  name = "${var.name_prefix}-client-invoker"
  role = aws_iam_role.client_invoker.name
}

# -----------------------------------------------------------------------------
# Security group for AgentCore-created ENIs (runtime subnet).
# Egress is wide-open at the SG level; DCF on the Aviatrix spoke gateway
# enforces actual allow/deny.
# -----------------------------------------------------------------------------

resource "aws_security_group" "runtime" {
  name        = "${local.name_prefix}-agentcore-runtime"
  description = "Security group attached to AgentCore-created ENIs"
  vpc_id      = aws_vpc.agentcore.id

  # AgentCore control plane reaches in on an ephemeral loopback-style channel;
  # we do not need any inbound rules here.
  egress {
    description = "All egress; DCF enforces allow/deny on the spoke gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-agentcore-runtime-sg"
  }
}
