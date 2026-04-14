#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${AGENT_SKILLS_REPO:-https://github.com/dennis-tra/agent-skills.git}"
CLONE_DIR="${AGENT_SKILLS_DIR:-$HOME/.agent-skills}"

# --- Resolve repo root ---

resolve_repo_root() {
  local script_dir
  if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$script_dir/.git" ]] && [[ -f "$script_dir/manifest.json" ]]; then
      echo "$script_dir"
      return 0
    fi
  fi
  return 1
}

# --- JSON parsing via python3 (no jq dependency) ---

parse_manifest() {
  python3 -c "
import json, sys, os
with open(os.path.join(sys.argv[1], 'manifest.json')) as f:
    for entry in json.load(f):
        print('\t'.join([entry['name'], entry['type'], entry['source'], entry['target']]))
" "$1"
}

# --- Core install logic ---

installed=0
skipped=0
warned=0

install_components() {
  local repo_root="$1"
  shift
  local filter_type="${1:-}"
  local filter_name="${2:-}"

  while IFS=$'\t' read -r name type source target; do
    if [[ -n "$filter_type" ]] && [[ "$filter_type" != "all" ]]; then
      if [[ "$type" != "$filter_type" ]] && [[ "$name" != "$filter_type" ]]; then
        continue
      fi
    fi
    if [[ -n "$filter_name" ]] && [[ "$name" != "$filter_name" ]]; then
      continue
    fi

    local abs_source="$repo_root/$source"
    local abs_target="${target/\$HOME/$HOME}"

    local target_dir
    if [[ "$type" == "skill" ]]; then
      target_dir="$(dirname "$abs_target")"
    else
      target_dir="$(dirname "$abs_target")"
    fi
    mkdir -p "$target_dir"

    if [[ -L "$abs_target" ]]; then
      local current
      current="$(readlink "$abs_target")"
      if [[ "$current" == "$abs_source" ]]; then
        printf "  skip  %s (%s already linked)\n" "$name" "$type"
        ((skipped++))
        continue
      else
        printf "  warn  %s — symlink exists but points to %s\n" "$name" "$current"
        ((warned++))
        continue
      fi
    elif [[ -e "$abs_target" ]]; then
      printf "  warn  %s — target exists and is not a symlink: %s\n" "$name" "$abs_target"
      ((warned++))
      continue
    fi

    ln -s "$abs_source" "$abs_target"
    printf "  installed  %s → %s\n" "$name" "$abs_target"
    ((installed++))
  done < <(parse_manifest "$repo_root")
}

print_summary() {
  echo ""
  echo "Summary: $installed installed, $skipped skipped, $warned warnings"
}

# --- Main ---

main() {
  local repo_root
  if repo_root="$(resolve_repo_root)"; then
    echo "Installing from $repo_root ..."
    install_components "$repo_root"
    print_summary
  else
    echo "Error: not running from a local clone (no .git directory found)."
    echo "Run this script from within the agent-skills repository."
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
