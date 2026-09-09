#!/usr/bin/env bash
set -euo pipefail

[[ "${IMAGE_TAG:-}" =~ ^sha-[0-9a-f]{7,40}$ ]] || {
  echo "IMAGE_TAG must be the immutable sha tag produced by the image build" >&2
  exit 2
}

helm upgrade --install van ./chart \
  --kube-context ectobit --namespace repo \
  --values .github/deploy/van-values.yaml \
  --set-string "image.tag=$IMAGE_TAG" \
  --wait --timeout 5m

kubectl --context ectobit --namespace repo rollout status deployment/van --timeout=5m
actual_image="$(kubectl --context ectobit --namespace repo get deployment/van -o 'jsonpath={.spec.template.spec.containers[?(@.name=="van")].image}')"
[[ "$actual_image" == "acim/van:$IMAGE_TAG" ]] || {
  echo "deployed image does not match the selected build artifact" >&2
  exit 1
}
