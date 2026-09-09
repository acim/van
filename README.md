# van

[![pipeline](https://github.com/acim/van/actions/workflows/pipeline.yaml/badge.svg)](https://github.com/acim/van/actions/workflows/pipeline.yaml)
[![Go Reference](https://pkg.go.dev/badge/go.acim.net/van.svg)](https://pkg.go.dev/go.acim.net/van)
[![Go Report](https://goreportcard.com/badge/go.acim.net/van)](https://goreportcard.com/report/go.acim.net/van)

Go vanity imports HTTP server.

## Deployment

The Helm chart lives in [`chart/`](chart/README.md), with production values in
[`.github/deploy/van-values.yaml`](.github/deploy/van-values.yaml).
The release is `van`, in namespace `repo` on Kubernetes context `ectobit`.
It serves `go.acim.net` and `go.ectobit.com` using the existing `van-tls` Secret.

CI validates the workflow and chart before building the image. A push to `main`
then upgrades the release from this checkout with the build's immutable image
tag. The shared image workflow builds `linux/amd64` and scans the image with
Grype before publishing it. High or critical vulnerabilities block publishing
and deployment; scan results are saved as the `van-grype-sarif` CI artifact.
Deployment uses the existing `KUBERNETES_*` and `SSH_TUNNEL_*` repository
secrets. The Kubernetes identity must be allowed to manage Helm release Secrets
and the chart's ConfigMap, ServiceAccount, Service, Deployment, and Ingress in
`repo`; an identity limited to patching the Deployment image is insufficient.
Deployment RBAC is managed centrally by the `deploy-role` release in
`ectobit/infrastructure/helmfile.d/00-infrastructure.yaml.gotmpl`, following the
other applications. The existing `repo/deploy` Role must be extended with Helm
permissions, including Secrets for release history, before the first pipeline
deployment. Its existing RoleBinding reuses the `default/deploy` ServiceAccount.
A cluster administrator must apply the infrastructure release after the RBAC
change is approved. Van owns its chart, production values, and deployment
pipeline; shared CI identity and deployment permissions remain in infrastructure.
CI pins Helm 3.21.4 so its API and readiness checks match the RBAC contract.
Existing-object access is limited to resources named `van`, except for Helm's
dynamically named release Secrets and the ReplicaSet list needed by `--wait`.
Kubernetes RBAC cannot constrain resource creation by name. Autoscaling and
`helm test` are not enabled in this pipeline and receive no HPA or Pod permissions.

Run `make chart-check` to lint and render the chart locally. To deploy a reviewed
image manually with an already configured cluster connection:

```sh
IMAGE_TAG=sha-<commit> .github/scripts/deploy-van.sh
```

The chart was moved from `ectobit/infrastructure/charts/van`; its production
values were moved from `helmfile.d/08-repo.yaml.gotmpl`. Keep the release name
and namespace above when migrating. Resource names and selectors are unchanged,
so the existing release can be upgraded in place without an uninstall. The
infrastructure Helmfile must no longer manage Van after this handoff.

## License

Licensed under either of

- Apache License, Version 2.0
  ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
- MIT license
  ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
