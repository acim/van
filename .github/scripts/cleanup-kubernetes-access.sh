#!/usr/bin/env bash
set -euo pipefail

[[ -n "${RUNNER_TEMP:-}" ]] || { echo "RUNNER_TEMP is required" >&2; exit 2; }
if [[ -z "${KUBE_TUNNEL_PID:-}" && -z "${KUBE_ACCESS_TEMP_DIR:-}" ]]; then
  echo "no recorded Kubernetes access to clean up"
  exit 0
fi
if [[ ! "${KUBE_TUNNEL_PID:-}" =~ ^[0-9]+$ ]] || (( KUBE_TUNNEL_PID <= 1 )); then
  echo "KUBE_TUNNEL_PID must identify a non-system process" >&2
  exit 2
fi
temp_dir="${KUBE_ACCESS_TEMP_DIR:-}"
temp_parent="${temp_dir%/*}"; temp_name="${temp_dir##*/}"
[[ "$temp_parent" == "${RUNNER_TEMP%/}" && "$temp_name" == van-kube.* ]] || { echo "KUBE_ACCESS_TEMP_DIR is not a direct Van access directory" >&2; exit 2; }
process_command="$(ps -p "$KUBE_TUNNEL_PID" -o command= 2>/dev/null || true)"
case "$process_command" in
  *ssh*" -N "*"UserKnownHostsFile=${temp_dir}/known_hosts"*" -i ${temp_dir}/kube-tunnel "*) expected_tunnel=true ;;
  *) expected_tunnel=false ;;
esac
if [[ "$expected_tunnel" == true ]] && kill -0 "$KUBE_TUNNEL_PID" 2>/dev/null; then
  kill "$KUBE_TUNNEL_PID" 2>/dev/null || true
  for _ in {1..20}; do kill -0 "$KUBE_TUNNEL_PID" 2>/dev/null || break; sleep 0.1; done
fi
rm -rf -- "$temp_dir"
if [[ "$expected_tunnel" == false ]]; then
  echo "::warning::recorded tunnel PID did not match the expected SSH command; not killing"
fi
