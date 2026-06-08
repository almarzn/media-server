# media-server

GitOps repo (Flux CD v2) for a self-hosted media server stack on bare-metal Kubernetes.

## Dev commands

```bash
helm lint ./charts/media-server
helm template media-server ./charts/media-server -f ./charts/media-server/values.yaml
helm template media-server ./charts/media-server --debug
```

No tests, no linters, no CI. Flux reconciles `main` automatically.

## Repo layout

| Path | Purpose |
|---|---|
| `charts/media-server/` | Helm chart (app entrypoint) |
| `charts/media-server/values.yaml` | Default values (placeholders marked `invalid` — real values in Flux HelmRelease) |
| `charts/media-server/templates/` | Service deployments, secrets, configmaps |
| `clusters/media-server/` | Flux cluster state, bootstrap, image policies |
| `clusters/media-server/flux-system/` | Flux bootstrap (gitrepo + root kustomization) |
| `clusters/media-server/media-server/` | ImageRepository, ImagePolicy per service + HelmRelease with real values |
| `infrastructure/controllers/` | External-Secrets HelmRelease, Intel GPU Plugin DaemonSet |
| `infrastructure/configs/` | CoreDNS config, Infisical ClusterSecretStore |

## Flux commands (requires cluster)

```bash
flux get kustomizations
flux get helmreleases
flux get images
flux reconcile kustomization media-server
flux reconcile helmrelease media-server
flux reconcile image repository plex
```

## Architecture notes

- **Secrets**: All via External Secrets Operator from Infisical (EU instance). Pods fail if Infisical unreachable.
- **Tailscale**: Mesh VPN with `tailscale serve` proxying web UIs. Restart pod after config changes.
- **VPN**: qBittorrent runs with gluetun sidecar (ProtonVPN WireGuard). Privileged container. Dynamic port forwarding via VPN_PORT_FORWARDING_UP_COMMAND.
- **Image automation**: Flux `ImageUpdateAutomation` resolves tags to digests and auto-commits to `main` — any local `values.yaml` edits will be overwritten.
- **Samba**: Runs privileged (NodePort 445). Two instances (admin + shared).
- **Intel GPU**: GPU plugin DaemonSet for Plex hardware transcoding.
- **No CI/CD**: No PR gates, no lint checks, no approval workflow.
- **`helmrelease.yaml`** at `clusters/media-server/media-server/` is the source of truth for per-environment overrides (advertiseIp, paths, ports).

## Gotchas

- `values.yaml` placeholders (`invalid`) must never reach production — real values come from Flux HelmRelease.
- Flux image automation writes digest updates into `values.yaml` — treat it as a generated file.
- Tailscale auth key renewal: generate key at tailscale admin → paste in Infisical `tailscale/AUTH_KEY` → annotate ExternalSecret to force resync → restart tailscale pod.
- No CI means no pre-commit validation — `helm lint` is the only local check available.
