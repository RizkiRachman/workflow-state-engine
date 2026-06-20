#!/usr/bin/env bash
# shellcheck disable=SC2317
# Consolidate Graphify communities from 283+ auto-detected groups to ~15 meaningful clusters.
# Reads graphify-out/graph.json, remaps community IDs based on file path patterns,
# writes updated graph.json and regenerates GRAPH_REPORT.md.
# Usage: bash scripts/consolidate-graphify-communities.sh [--dry-run|--apply]

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GRAPH_FILE="$PROJECT_ROOT/graphify-out/graph.json"
REPORT_FILE="$PROJECT_ROOT/graphify-out/GRAPH_REPORT.md"
MODE="${1:---dry-run}"

if [ ! -f "$GRAPH_FILE" ]; then
  echo "ERROR: $GRAPH_FILE not found."
  exit 1
fi

echo "=== Graphify Community Consolidation ==="
echo "Mode: $MODE"
echo "Input: $GRAPH_FILE"

export GRAPH_FILE REPORT_FILE MODE
python3 << 'PYEOF'
import json, sys, re, os

graph_file = os.environ['GRAPH_FILE']
report_file = os.environ['REPORT_FILE']
mode = os.environ['MODE']

with open(graph_file, 'r') as f:
    graph = json.load(f)

nodes = graph.get('nodes', [])
edges = graph.get('edges', [])

groups = [
    (0,  "Orchestration Core",     re.compile(r'^contract/')),
    (1,  "Agents",                 re.compile(r'^agents/')),
    (2,  "Skills",                 re.compile(r'^skills/(?!gitnexus/)')),
    (3,  "Scripts & Tooling",      re.compile(r'^scripts/')),
    (4,  "GitNexus Intelligence",  re.compile(r'^skills/gitnexus/')),
    (5,  "Configuration",          re.compile(r'^config/|^opencode\.json|\.opencode/config/')),
    (6,  "Rules & Governance",     re.compile(r'^rules/|\.github/')),
    (7,  "Documentation",          re.compile(r'^doc/')),
    (8,  "Usage Guides",           re.compile(r'^usage/')),
    (9,  "Session Artifacts",      re.compile(r'^session/')),
    (10, "Tests",                  re.compile(r'^test/')),
    (11, "Graphify Output",        re.compile(r'^graphify-out/')),
    (12, "Meta Orchestration",     re.compile(r'^agent\.md$|^AGENTS\.md$|^README\.md$|^\.opencode/(?!config/)')),
    (13, "Tasks & Templates",      re.compile(r'^tasks/')),
    (14, "Package & Dependencies", re.compile(r'^package\.json$|^node_modules/|^package-lock\.json')),
    (15, ".githooks",              re.compile(r'^\.githooks/')),
]
FALLBACK_GROUP = 99
FALLBACK_NAME = "Uncategorized"

old_count = len(set(n.get('community', -1) for n in nodes))
new_map = {}
group_members = {g[0]: [] for g in groups}
group_members[FALLBACK_GROUP] = []
uncategorized = []

for node in nodes:
    # source_file or src_file depending on graph version
    raw_field = node.get('source_file') or node.get('src_file') or ''
    src = raw_field if raw_field and raw_field != '?' else ''
    matched = False
    for gid, gname, pat in groups:
        if src and pat.search(src):
            node['community'] = gid
            new_map[gid] = gname
            group_members[gid].append(node)
            matched = True
            break
    if not matched:
        # Fallback: classify by file_type
        ft = node.get('file_type', '')
        if ft == 'concept':
            node['community'] = 12  # Meta Orchestration
            new_map[12] = "Meta Orchestration"
            group_members[12].append(node)
        elif ft == 'paper':
            node['community'] = 7  # Documentation
            new_map[7] = "Documentation"
            group_members[7].append(node)
        else:
            node['community'] = FALLBACK_GROUP
            new_map[FALLBACK_GROUP] = FALLBACK_NAME
            group_members[FALLBACK_GROUP].append(node)
        uncategorized.append(node.get('label', src or '?'))

new_count = len(new_map)

print(f"\nOld communities: {old_count}")
print(f"New communities: {new_count}")
print(f"\n=== New Group Sizes ===")
for gid, gname, _ in groups:
    count = len(group_members[gid])
    pct = 100.0 * count / len(nodes) if nodes else 0
    print(f"  [{gid:2d}] {gname:30s} {count:4d} nodes ({pct:.1f}%)")

if group_members[FALLBACK_GROUP]:
    fc = len(group_members[FALLBACK_GROUP])
    print(f"  [{FALLBACK_GROUP}] {FALLBACK_NAME:30s} {fc:4d} nodes")
    print(f"  Sample uncategorized: {uncategorized[:10]}")

if mode == '--apply':
    with open(graph_file, 'w') as f:
        json.dump(graph, f, indent=2)
    print(f"\nWriting: {graph_file}")

    lines = ["# Graphify Community Report (Consolidated)", "", "## Communities", ""]
    for gid, gname, _ in groups:
        members = group_members[gid]
        if not members:
            continue
        lines.append(f"### [{gid}] {gname} ({len(members)} nodes)")
        lines.append("")
        labels = sorted(set(m.get('label', '?') for m in members))
        for lbl in labels[:20]:
            lines.append(f"- {lbl}")
        if len(labels) > 20:
            lines.append(f"- ... and {len(labels) - 20} more")
        lines.append("")

    if group_members[FALLBACK_GROUP]:
        lines.append(f"### [{FALLBACK_GROUP}] {FALLBACK_NAME} ({len(group_members[FALLBACK_GROUP])} nodes)")
        for lbl in sorted(uncategorized)[:20]:
            lines.append(f"- {lbl}")

    with open(report_file, 'w') as f:
        f.write('\n'.join(lines))
    print(f"Writing: {report_file}")
else:
    print(f"\nUse --apply to write changes")

sys.exit(0 if len(uncategorized) == 0 else 1)
PYEOF
