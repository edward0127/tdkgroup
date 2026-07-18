#!/usr/bin/env bash
set -euo pipefail

PUSH_GIT_MODE="auto"
AUTO_COMMIT_MESSAGE=""
WAIT_FOR_ACTIONS="false"

usage() {
  cat <<'EOF'
Usage:
  ./script/deploy_production.sh [options]

Options:
  --auto-commit "message"   Stage all changes and create a commit before push.
  --push-git                Force git push.
  --no-push-git             Do not push (useful for checking the commit only).
  --wait                    Wait for the GitHub CI/deploy run to finish (requires gh).
  -h, --help                Show this help.

Examples:
  ./script/deploy_production.sh --auto-commit "Update BAS coding"
  ./script/deploy_production.sh --push-git --wait

This command never runs Docker locally. A push to main starts GitHub-hosted tests,
then GitHub builds the production image and deploys only if every test passes.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto-commit)
      [[ $# -lt 2 ]] && { echo "Missing value for --auto-commit" >&2; usage; exit 1; }
      AUTO_COMMIT_MESSAGE="$2"
      shift 2
      ;;
    --push-git)
      PUSH_GIT_MODE="true"
      shift
      ;;
    --no-push-git)
      PUSH_GIT_MODE="false"
      shift
      ;;
    --wait)
      WAIT_FOR_ACTIONS="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "Missing required command: git" >&2
  exit 1
fi

if [[ -n "$AUTO_COMMIT_MESSAGE" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Creating commit: $AUTO_COMMIT_MESSAGE"
    git add -A
    git commit -m "$AUTO_COMMIT_MESSAGE"
  else
    echo "No local changes detected, skipping auto-commit."
  fi
fi

if [[ -n "$(git status --porcelain)" ]]; then
  cat >&2 <<'EOF'
Working tree is not clean. Commit the changes first, or use:
  ./script/deploy_production.sh --auto-commit "your message"
EOF
  exit 1
fi

current_branch="$(git branch --show-current)"
if [[ -z "$current_branch" ]]; then
  echo "Unable to determine the current branch." >&2
  exit 1
fi

has_upstream() {
  git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1
}

ahead_commit_count() {
  if has_upstream; then
    git rev-list --count "@{u}..HEAD"
  elif git show-ref --verify --quiet "refs/remotes/origin/$current_branch"; then
    git rev-list --count "origin/$current_branch..HEAD"
  else
    echo "0"
  fi
}

push_current_branch() {
  if has_upstream; then
    git push
  else
    git push -u origin "$current_branch"
  fi
}

should_push="false"
if [[ "$PUSH_GIT_MODE" == "true" ]]; then
  should_push="true"
elif [[ "$PUSH_GIT_MODE" == "auto" ]]; then
  if [[ -n "$AUTO_COMMIT_MESSAGE" ]] || [[ "$(ahead_commit_count)" -gt 0 ]]; then
    should_push="true"
  fi
fi

if [[ "$should_push" == "true" ]]; then
  echo "Pushing $current_branch to GitHub..."
  push_current_branch
  echo "Push complete: https://github.com/edward0127/tdkgroup/actions"
elif [[ "$PUSH_GIT_MODE" == "auto" ]]; then
  echo "No local commits ahead of the remote; skipping git push."
fi

if [[ "$current_branch" != "main" ]]; then
  echo "Note: CI runs on this branch through pull requests; production deploys only from main."
  exit 0
fi

if [[ "$WAIT_FOR_ACTIONS" == "true" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "--wait requires the GitHub CLI (gh). The push succeeded; monitor it at:" >&2
    echo "https://github.com/edward0127/tdkgroup/actions" >&2
    exit 1
  fi

  head_sha="$(git rev-parse HEAD)"
  echo "Waiting for GitHub to register the CI run for ${head_sha:0:7}..."
  run_id=""
  for _attempt in $(seq 1 30); do
    run_id="$(gh run list --workflow CI --commit "$head_sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    [[ -n "$run_id" ]] && break
    sleep 2
  done

  if [[ -z "$run_id" ]]; then
    echo "GitHub did not register the run within 60 seconds. Monitor it at:" >&2
    echo "https://github.com/edward0127/tdkgroup/actions" >&2
    exit 1
  fi

  gh run watch "$run_id" --exit-status
fi
