#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 1 ]] || { echo "usage: $0 <namespace>" >&2; exit 2; }
namespace="$1"
[[ "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || { echo "invalid Kubernetes namespace" >&2; exit 2; }
startup_timeout_seconds="${KUBE_TUNNEL_START_TIMEOUT_SECONDS:-15}"
[[ "$startup_timeout_seconds" =~ ^[1-9][0-9]*$ ]] || { echo "KUBE_TUNNEL_START_TIMEOUT_SECONDS must be a positive integer" >&2; exit 2; }
required_variables=(RUNNER_TEMP GITHUB_ENV SSH_TUNNEL_HOST SSH_TUNNEL_KNOWN_HOSTS SSH_TUNNEL_LOCAL_PORT SSH_TUNNEL_PRIVATE_KEY SSH_TUNNEL_TARGET_HOST SSH_TUNNEL_TARGET_PORT SSH_TUNNEL_USER KUBERNETES_CERT KUBERNETES_SERVER KUBERNETES_TLS_SERVER_NAME KUBERNETES_TOKEN)
for variable_name in "${required_variables[@]}"; do
  [[ -n "${!variable_name:-}" ]] || { echo "required environment variable is empty: ${variable_name}" >&2; exit 2; }
done
forward_is_ready() { (exec 3<>"/dev/tcp/127.0.0.1/${SSH_TUNNEL_LOCAL_PORT}") 2>/dev/null; }
temp_dir="$(mktemp -d "${RUNNER_TEMP}/van-kube.XXXXXX")"
ssh_key_path="$temp_dir/kube-tunnel"; known_hosts_path="$temp_dir/known_hosts"; kubeconfig_path="$temp_dir/config"; tunnel_pid=""
cleanup_on_error() { status="$1"; trap - ERR INT TERM; [[ -z "$tunnel_pid" ]] || ! kill -0 "$tunnel_pid" 2>/dev/null || kill "$tunnel_pid" 2>/dev/null || true; rm -rf -- "$temp_dir"; (( status != 0 )) || status=1; exit "$status"; }
trap 'cleanup_on_error "$?"' ERR
trap 'cleanup_on_error 130' INT
trap 'cleanup_on_error 143' TERM
forward_is_ready && { echo "SSH tunnel local port is already occupied" >&2; cleanup_on_error 1; }
printf '%s\n' "$SSH_TUNNEL_PRIVATE_KEY" >"$ssh_key_path"
printf '%s\n' "$SSH_TUNNEL_KNOWN_HOSTS" >"$known_hosts_path"
chmod 600 "$ssh_key_path" "$known_hosts_path"
ssh -N -F /dev/null -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o GlobalKnownHostsFile=/dev/null -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o "UserKnownHostsFile=${known_hosts_path}" -i "$ssh_key_path" -L "${SSH_TUNNEL_LOCAL_PORT}:${SSH_TUNNEL_TARGET_HOST}:${SSH_TUNNEL_TARGET_PORT}" "${SSH_TUNNEL_USER}@${SSH_TUNNEL_HOST}" </dev/null &
tunnel_pid="$!"
startup_deadline=$((SECONDS + startup_timeout_seconds))
while true; do
  if ! kill -0 "$tunnel_pid" 2>/dev/null; then wait "$tunnel_pid" || true; echo "SSH tunnel exited before access configuration completed" >&2; cleanup_on_error 1; fi
  forward_is_ready && break
  (( SECONDS < startup_deadline )) || { echo "timed out waiting for the SSH tunnel local port" >&2; cleanup_on_error 1; }
  sleep 0.2
done
cat >"$kubeconfig_path" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: ectobit
  cluster:
    server: ${KUBERNETES_SERVER}
    certificate-authority-data: ${KUBERNETES_CERT}
    tls-server-name: ${KUBERNETES_TLS_SERVER_NAME}
users:
- name: deploy
  user:
    token: ${KUBERNETES_TOKEN}
contexts:
- name: ectobit
  context:
    cluster: ectobit
    user: deploy
    namespace: ${namespace}
current-context: ectobit
EOF
chmod 600 "$kubeconfig_path"
{ printf 'KUBECONFIG=%s\n' "$kubeconfig_path"; printf 'KUBE_TUNNEL_PID=%s\n' "$tunnel_pid"; printf 'KUBE_TUNNEL_LOCAL_PORT=%s\n' "$SSH_TUNNEL_LOCAL_PORT"; printf 'KUBE_ACCESS_TEMP_DIR=%s\n' "$temp_dir"; } >>"$GITHUB_ENV"
trap - ERR INT TERM
