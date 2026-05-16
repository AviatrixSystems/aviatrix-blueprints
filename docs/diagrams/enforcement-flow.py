import sys

SKILL_DIR = "/Users/nickda/.claude/plugins/cache/aviatrix-diagram-builder/aviatrix-diagram-builder/1.0.0/skills/aviatrix-diagram"
sys.path.insert(0, SKILL_DIR + "/scripts")
from aviatrix_diagram import *
import aviatrix_diagram as _avx
_avx.FONT_FAMILY = "'Anthropic Sans', 'SF Mono', ui-monospace, 'Segoe UI Mono', monospace"
_avx.COLORS['line_light'] = "none"

ICONS = SKILL_DIR + "/icons"

d = Diagram(
    title="DCF Enforcement Flow: Obot MCP Egress Containment",
    subtitle="Data-plane enforcement · Aviatrix Gateway (Policy Enforcement Point)",
    width=1200,
    height=520,
    icon_base_path=ICONS,
)

# ── Containers ─────────────────────────────────────────────────────────────

# obot-mcp namespace (left)
d.add_container(Container(
    "ns-mcp", "obot-mcp namespace",
    x=30, y=110, width=195, height=390,
    style="vpc",
    fill_color="#F4F2F0",
    border_color="#C4BFB9",
    text_color="#2c2826",
    border_style="dashed",
    label_position="top-center",
    corner_radius=6,
))

# Policy Enforcement Point outer box (center) — body, no label
d.add_container(Container(
    "pep", "",
    x=358, y=88, width=484, height=430,
    style="vpc",
    border_style="dashed",
    border_color="#C4BFB9",
    fill_color="#F4F2F0",
    text_color="#2c2826",
    label_position="top-center",
    corner_radius=6,
))

# Window chrome title bar — renders on top (smaller area wins)
d.add_container(Container(
    "pep-titlebar", "Aviatrix Gateway (Policy Enforcement Point)",
    x=358, y=88, width=484, height=28,
    style="vpc",
    fill_color="#2c2826",
    border_color="#2c2826",
    text_color="#F4F2F0",
    label_position="top-center",
    corner_radius=6,
))

# Tier 1 - Named Permits
d.add_container(Container(
    "tier1", "Tier 1: Named Permits",
    x=374, y=220, width=452, height=82,
    style="vpc",
    fill_color="#E6F1FB",
    border_color="#185FA5",
    text_color="#0C447C",
    label_position="top-left",
    corner_radius=6,
))

# Tier 2 - Per-Server FirewallPolicy CRD
d.add_container(Container(
    "tier2", "Tier 2: Per-Server FirewallPolicy CRD",
    x=374, y=312, width=452, height=82,
    style="vpc",
    fill_color="#EEEDFE",
    border_color="#534AB7",
    text_color="#3C3489",
    label_position="top-left",
    corner_radius=6,
))

# Tier 3 - Default Deny + Log
d.add_container(Container(
    "tier3", "Tier 3: Default Deny + Log",
    x=374, y=404, width=452, height=90,
    style="vpc",
    fill_color="#FCEBEB",
    border_color="#A32D2D",
    text_color="#791F1F",
    label_position="top-left",
    corner_radius=6,
))

# ── Nodes ───────────────────────────────────────────────────────────────────

# Pod A (permitted path)
d.add_node(Node(
    "pod-a", "MCP Server Pod",
    x=128, y=228,
    icon="/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/icon-pod-ref.svg",
    icon_size=38,
    sublabel="permitted path",
    parent_container="ns-mcp",
))

# Pod B (blocked path)
d.add_node(Node(
    "pod-b", "MCP Server Pod",
    x=128, y=418,
    icon="/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/icon-pod-ref.svg",
    icon_size=38,
    sublabel="blocked path",
    parent_container="ns-mcp",
))

# Aviatrix spoke gateway icon (top of PEP box)
d.add_node(Node(
    "gateway", "",
    x=600, y=156,
    icon="/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/icon-gateway-ref.svg",
    icon_size=48,
    sublabel="eBPF dataplane evaluation",
    parent_container="pep",
))

# Permitted destination (right)
d.add_node(Node(
    "internet", "Permitted Domain",
    x=1100, y=228,
    icon="avx:edge/cloud",
    icon_size=40,
    sublabel="connection allowed",
))

# Blocked destination (right)
d.add_node(Node(
    "blocked", "Blocked Domain",
    x=1100, y=418,
    icon="avx:edge/unmanaged-network",
    icon_size=40,
    sublabel="dropped · logged to CoPilot",
))

# ── Connections (right-angle, no tier crossings, no border overlap) ──────────
#
# Green (permitted):
#   Entry — right to x=280 (gap between ns/PEP), UP to y=156, right to gateway
#   Exit  — right to x=780 (8px outside PEP right border), DOWN to y=228, right
#
# Red (denied):
#   Entry — right to x=296 (PEP LEFT CORRIDOR: between PEP x=288 and tier x=304),
#            UP to y=162 (open space above tiers), right to x=530, UP to gateway
#   Exit  — DOWN 6px to y=162, right to x=764 (PEP RIGHT CORRIDOR: between tier
#            x=756 and PEP x=772), DOWN to y=418, right to blocked
#
# Corridors are 16px wide; line at corridor center gives 7px clearance each side.
# Green at y=156, red at y=162 (6px separation). No crossings.

# Pod A → Gateway (GREEN)
d.add_connection(Connection(
    "pod-a", "gateway",
    color="allow",
    thickness=1.5,
    arrow="end",
    style="solid",
    waypoints=[(338, 228), (338, 156)],
))

# Pod B → Gateway (RED — uses PEP left corridor x=296, between PEP border x=288
# and tier left border x=304; avoids tier boxes and the above-diagram detour)
d.add_connection(Connection(
    "pod-b", "gateway",
    color="deny",
    thickness=1.5,
    arrow="end",
    style="solid",
    waypoints=[(348, 418), (348, 162), (600, 162)],
))

# Gateway → Internet (GREEN)
d.add_connection(Connection(
    "gateway", "internet",
    color="allow",
    thickness=1.5,
    arrow="end",
    style="solid",
    waypoints=[(862, 156), (862, 228)],
))

# Gateway → Blocked (RED — 6px drop separates from green exit)
d.add_connection(Connection(
    "gateway", "blocked",
    color="deny",
    thickness=1.5,
    arrow="end",
    style="solid",
    waypoints=[(600, 162), (852, 162), (852, 418)],
))

# ── Standalone labels (tier sublabels) ──────────────────────────────────────

# Tier 1 sublabel
d.add_label(Label(
    "t1-sub", "cluster infra · cloud services · Obot egress",
    x=600, y=284,
    font_size=10,
    color="#185FA5",
    anchor="middle",
    weight="normal",
))

# Tier 2 sublabel
d.add_label(Label(
    "t2-sub", "FirewallPolicy CRD per MCP server pod",
    x=600, y=376,
    font_size=10,
    color="#534AB7",
    anchor="middle",
    weight="normal",
))

# Tier 3 sublabel
d.add_label(Label(
    "t3-sub", "all unmatched traffic blocked + logged",
    x=600, y=470,
    font_size=10,
    color="#A32D2D",
    anchor="middle",
    weight="normal",
))

# ── Tier result annotations (reference style — right-aligned inside tier boxes) ─

d.add_label(Label("t1-result", "Permit",
    x=816, y=261, font_size=11, color="#265B19", anchor="end", weight="600"))

d.add_label(Label("t2-result", "Permit",
    x=816, y=353, font_size=11, color="#265B19", anchor="end", weight="600"))

d.add_label(Label("t3-result", "Deny + log",
    x=816, y=449, font_size=11, color="#7F2C28", anchor="end", weight="600"))

# ── Connection labels — explicit positions, clear of all borders ─────────────
# Green: midpoint of final horizontal (y=228), 13px above line, between x=792-1068
d.add_label(Label(
    "lbl-permit", f"{SAFE_GLYPHS['check']} TCP 443 · domain in permit list",
    x=971, y=241,
    font_size=9, color=COLORS['allow'],
    anchor="middle", weight="normal",
    background=True, background_stroke="none",
))

# Red: midpoint of final horizontal (y=418), 13px above line, between x=782-1068
d.add_label(Label(
    "lbl-deny", f"{SAFE_GLYPHS['cross']} domain not in any permit",
    x=966, y=431,
    font_size=9, color=COLORS['deny'],
    anchor="middle", weight="normal",
    background=True, background_stroke="none",
))

# ── Render ──────────────────────────────────────────────────────────────────

OUTPUT = "/Users/nickda/Code/avx-dev/aviatrix-blueprints/docs/diagrams/enforcement-flow.svg"
d.save(OUTPUT)
print(f"Saved: {OUTPUT}")
