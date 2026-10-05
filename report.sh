#!/usr/bin/env bash
# Tell the ENCY store how this run is getting on: report.sh RUNNING|FAILED|PUBLISHED|SUBMITTED [version]
#
# Why this exists: publishing already talks to the store, but the run was silent about everything
# else, so the only way to find out that a build had started — or why it stopped — was to go to
# GitHub and look. Now the extension's own page in the store can say it.
#
# Best-effort by contract. Every caller runs it with `|| true`, and it exits 0 whatever happens: a
# status line must never be the reason a publish fails. It also adds no credential — the same GitHub
# OIDC token that authenticates a publish signs the report, and the store reads the repository from
# that token rather than from anything we send, so no run can report against somebody else's.
#
# REPORT_WARN=true turns "the store did not take the report" into a run annotation instead of
# silence — still exit 0. Set for SUBMITTED only: a store older than that status answers 400, and the
# author should hear why the card still says "building" about a package that went through.
set -uo pipefail

warn() { if [ -n "${REPORT_WARN:-}" ]; then echo "::warning::$*"; fi; }

status="${1:-}"
version="${2:-}"
api="${API:-https://apps.encycam.com/api}"

[ -n "$status" ] || exit 0
# jq builds the JSON; without it there is nothing to send
command -v jq >/dev/null 2>&1 || { warn "Could not tell the store this run is $status: jq is missing."; exit 0; }

auth=()
token="$(printf '%s' "${TOKEN:-}" | sed 's/^[[:space:]]*Bearer[[:space:]]*//')"
if [ -n "$token" ]; then
  auth=(-H "Authorization: Bearer $token")
elif [ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  ghjwt="$(curl -sS -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" \
           "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=ency-extension-store" 2>/dev/null \
           | jq -r '.value // empty')"
  [ -n "$ghjwt" ] || { warn "Could not tell the store this run is $status: no GitHub OIDC token."; exit 0; }
  auth=(-H "X-GitHub-OIDC-Token: $ghjwt")
else
  exit 0                                     # nothing to authenticate with: nothing to report
fi

run_url=""
if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
  run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi

body="$(jq -nc \
  --arg status "$status" \
  --arg runUrl "$run_url" \
  --arg version "$version" \
  --arg actionVersion "${ACTION_REF:-}" \
  --arg failedStep "${FAILED_STEP:-}" \
  --arg failureLog "${FAILURE_LOG:-}" \
  '{status: $status}
   + (if $runUrl        != "" then {runUrl: $runUrl}               else {} end)
   + (if $version       != "" then {version: $version}             else {} end)
   + (if $actionVersion != "" then {actionVersion: $actionVersion} else {} end)
   + (if $failedStep    != "" then {failedStep: $failedStep}       else {} end)
   + (if $failureLog    != "" then {failureLog: $failureLog}       else {} end)')"

code="$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' -X POST "$api/builds/report" \
  "${auth[@]}" -H "Content-Type: application/json" -d "$body" 2>/dev/null)" || true
if ! [[ "${code:-}" =~ ^2[0-9][0-9]$ ]]; then
  warn "The store did not record this run as $status (HTTP ${code:-000}). The package went through; only the run status on the store page is behind."
fi
exit 0
