import sys

SKILL_DIR = "/Users/nickda/.claude/plugins/cache/aviatrix-diagram-builder/aviatrix-diagram-builder/1.3.0/skills/aviatrix-diagram"
sys.path.insert(0, SKILL_DIR + "/scripts")
from aviatrix_diagram import *
import aviatrix_diagram as _avx

_avx.FONT_FAMILY = "'Anthropic Sans', 'SF Mono', ui-monospace, 'Segoe UI Mono', monospace"
_avx.COLORS['line_light'] = "none"

ICONS = SKILL_DIR + "/icons"
GW_ICON   = "/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/icon-gateway-ref.svg"
OBOT_LOGO = "/Users/nickda/Code/nick-dev/avx-secure-enterprise-mcp-platform-obot/demo/logos/obot_color_logo.svg"
CTRL_ICON = "/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/icon-controller-ref.svg"

d = Diagram(
    title="Zero-Trust MCP Egress: Obot on AKS with Aviatrix DCF",
    subtitle="Infrastructure topology · per-pod FQDN enforcement · no sidecars · no service mesh",
    width=1200,
    height=560,
    icon_base_path=ICONS,
)

# ── Containers ──────────────────────────────────────────────────────────────

# Azure VNet region
d.add_container(Container(
    "vpc", "Azure VNet",
    x=30, y=80, width=840, height=440,
    style="region", cloud="azure", corner_radius=6,
))

# AKS node subnet — LEFT (pods originate here)
d.add_container(Container(
    "priv-subnet", "AKS node subnet",
    x=58, y=120, width=555, height=370,
    style="vpc",
    fill_color="#F4F2F0", border_color="#C4BFB9", text_color="#2c2826",
    label_position="top-center", corner_radius=6,
))

# AKS cluster — window chrome
d.add_container(Container(
    "eks", "",
    x=78, y=165, width=515, height=310,
    style="vpc",
    fill_color="#F4F2F0", border_color="#C4BFB9",
    border_style="dashed", corner_radius=6,
))
d.add_container(Container(
    "eks-bar", "AKS cluster",
    x=78, y=165, width=515, height=28,
    style="vpc",
    fill_color="#2c2826", border_color="#2c2826", text_color="#F4F2F0",
    label_position="top-center", corner_radius=6,
))

# obot-system namespace
d.add_container(Container(
    "ns-system", "obot-system",
    x=95, y=208, width=232, height=250,
    style="vpc",
    fill_color="#F4F2F0", border_color="#C4BFB9", text_color="#2c2826",
    label_position="top-center", corner_radius=6,
))

# obot-mcp namespace (dashed — ephemeral pods)
d.add_container(Container(
    "ns-mcp", "obot-mcp",
    x=345, y=208, width=232, height=250,
    style="vpc",
    fill_color="#F4F2F0", border_color="#C4BFB9", text_color="#2c2826",
    border_style="dashed", label_position="top-center", corner_radius=6,
))

# Gateway subnet — RIGHT (Aviatrix Gateway, internet-facing)
d.add_container(Container(
    "pub-subnet", "Gateway subnet",
    x=643, y=120, width=196, height=370,
    style="vpc",
    fill_color="#F4F2F0", border_color="#C4BFB9", text_color="#2c2826",
    label_position="top-center", corner_radius=6,
))

# Obot logo inside obot-system namespace
d.add_node(Node(
    "obot-logo", "",
    x=211, y=250,
    icon=OBOT_LOGO, icon_size=26,
    parent_container="ns-system",
))

# ── Nodes ───────────────────────────────────────────────────────────────────

# Aviatrix Gateway (PEP) — in gateway subnet on the RIGHT
d.add_node(Node(
    "gw", "",
    x=741, y=295,
    icon=GW_ICON, icon_size=52,
    sublabel="Aviatrix Gateway (PEP)",
    parent_container="pub-subnet",
))

# Internet — default route exits via gateway subnet
d.add_node(Node(
    "igw", "Internet",
    x=960, y=295,
    icon="avx:edge/cloud",
    icon_size=40,
    sublabel="Default route",
))

# Controller + CoPilot (management plane, external)
d.add_node(Node(
    "controller", "Controller · CoPilot",
    x=960, y=435,
    icon=CTRL_ICON, icon_size=40,
    sublabel="policy · audit",
))

# ── Connections (right-angle, all left→right) ────────────────────────────────

# Gateway → Internet — egress exits VNet via default route
d.add_connection(Connection(
    "gw", "igw",
    color="allow",
    thickness=1.5,
    arrow="end",
    style="solid",
))

# Controller → Gateway — management plane (dotted)
# Route: controller (960,435) → left to x=882 → up to y=325 → left to gw (741,295)
# x=882 clears VNet right border (VNet right edge at x=870)
d.add_connection(Connection(
    "controller", "gw",
    color=COLORS['line'],
    thickness=1.2,
    arrow="end",
    style="dotted",
    waypoints=[(882, 435), (882, 325), (753, 325)],
))

# ── Namespace content labels ─────────────────────────────────────────────────

# obot-system (logo replaces "Obot controller" text)
d.add_label(Label("s2", "aviatrix-network-policy-controller",
    x=211, y=282, font_size=9, color="#4A5568", anchor="middle"))
d.add_label(Label("s3", "Watches MCPNetworkPolicy objects",
    x=211, y=300, font_size=8, color="#6B7280", anchor="middle"))
d.add_label(Label("s4", "Reconciles FirewallPolicy CRDs",
    x=211, y=316, font_size=8, color="#6B7280", anchor="middle"))

# obot-mcp
d.add_label(Label("m1", "MCP server pods",
    x=461, y=252, font_size=11, color="#2c2826", anchor="middle", weight="600"))
d.add_label(Label("m2", "spawned on demand by Obot",
    x=461, y=272, font_size=9, color="#4A5568", anchor="middle"))
d.add_label(Label("m3", "one pod per server · ephemeral",
    x=461, y=290, font_size=8, color="#6B7280", anchor="middle"))
d.add_label(Label("m4", f"egress {SAFE_GLYPHS['arrow_right']} route table {SAFE_GLYPHS['arrow_right']} Gateway EIP",
    x=461, y=314, font_size=9, color=COLORS['allow'], anchor="middle", weight="600"))

# Gateway description
d.add_label(Label("gw1", "DCF · SNAT · eBPF",
    x=741, y=375, font_size=9, color="#4A5568", anchor="middle"))

# ── Render ───────────────────────────────────────────────────────────────────

OUTPUT = "/Users/nickda/Code/avx-dev/aviatrix-blueprints/blueprints/obot-mcp-egress-azure/architecture.svg"
d.save(OUTPUT)
print(f"Saved: {OUTPUT}")
