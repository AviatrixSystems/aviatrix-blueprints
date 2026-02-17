# ============================================================================
# Distributed Cloud Firewall (DCF) Configuration
# ============================================================================

# Enable DCF
resource "aviatrix_distributed_firewalling_config" "main" {
  enable_distributed_firewalling = true
}

# ============================================================================
# SmartGroups - Define network segments
# ============================================================================

# Development Environment SmartGroup
resource "aviatrix_smart_group" "dev" {
  name = "${var.name_prefix}-dev-smartgroup"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Environment = "development"
      }
    }
  }
}

# Production Environment SmartGroup
resource "aviatrix_smart_group" "prod" {
  name = "${var.name_prefix}-prod-smartgroup"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Environment = "production"
      }
    }
  }
}

# Database Environment SmartGroup
resource "aviatrix_smart_group" "db" {
  name = "${var.name_prefix}-db-smartgroup"

  selector {
    match_expressions {
      type         = "vm"
      account_name = var.aws_account_name
      region       = var.aws_region
      tags = {
        Environment = "database"
      }
    }
  }
}

# ============================================================================
# DCF Policies - Zero Trust Segmentation Rules
# ============================================================================

resource "aviatrix_distributed_firewalling_policy_list" "main" {
  depends_on = [
    aviatrix_distributed_firewalling_config.main,
    aviatrix_smart_group.dev,
    aviatrix_smart_group.prod,
    aviatrix_smart_group.db
  ]

  policies {
    name     = "allow-prod-to-db"
    action   = "PERMIT"
    priority = 100
    protocol = "ANY"
    logging  = true
    watch    = false

    src_smart_groups = [
      aviatrix_smart_group.prod.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.db.uuid
    ]
  }

  policies {
    name     = "allow-dev-to-prod-read-only"
    action   = "PERMIT"
    priority = 110
    protocol = "ICMP"
    logging  = true
    watch    = false

    src_smart_groups = [
      aviatrix_smart_group.dev.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.prod.uuid
    ]
  }

  policies {
    name     = "deny-dev-to-db"
    action   = "DENY"
    priority = 200
    protocol = "ANY"
    logging  = true
    watch    = true # Watch mode to highlight this rule in CoPilot

    src_smart_groups = [
      aviatrix_smart_group.dev.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.db.uuid
    ]
  }

  policies {
    name     = "deny-prod-to-dev"
    action   = "DENY"
    priority = 210
    protocol = "ANY"
    logging  = true
    watch    = false

    src_smart_groups = [
      aviatrix_smart_group.prod.uuid
    ]
    dst_smart_groups = [
      aviatrix_smart_group.dev.uuid
    ]
  }

  policies {
    name     = "default-deny-all"
    action   = "DENY"
    priority = 1000
    protocol = "ANY"
    logging  = true
    watch    = false

    src_smart_groups = [
      "def000ad-0000-0000-0000-000000000000" # Public Internet
    ]
    dst_smart_groups = [
      "def000ad-0000-0000-0000-000000000000" # Public Internet
    ]
  }
}
