# DC34 K8s Sandbox — Blue Team Village CTF

Welcome, defender! This repository stands up the **local Kubernetes sandbox you'll compete in** during the **Blue Team Village CTF at DEF CON 34** (Project Obsidian). One command builds a self-contained cluster on your own laptop — complete with runtime telemetry and security guardrails — and the CTF challenges deploy straight into it during the event.

Nothing here touches shared infrastructure: the whole environment lives in a VM on your machine, and you can pause it or wipe it whenever you want.

## What the sandbox looks like

```
Your laptop
└── Linux VM running Docker           ← colima on macOS, Docker Desktop (WSL2) on Windows
    └── minikube cluster "dc34"       ← single-node Kubernetes
        ├── Cilium                    ← CNI: pod networking + NetworkPolicy enforcement
        ├── Tetragon                  ← eBPF runtime observability (process/syscall events)
        ├── Kyverno                   ← policy engine enforcing the guardrails below
        └── metrics-server            ← resource metrics for kubectl top / k9s
```

Why you care as a contestant:

- **Tetragon** streams kernel-level events (process execs, network connections) from every workload — this is telemetry you can hunt in when analyzing a challenge.
- **Kyverno + Cilium** keep challenge workloads contained: restricted pod security, default-deny networking, and resource caps. Suspicious things you deploy stay inside the sandbox.

## Requirements

All platforms: **~4 CPU cores and 8 GB RAM free** for the VM, ~20 GB of disk, and **a GitHub account** for pulling challenge images during the event (see below).

- **macOS** — [Homebrew](https://brew.sh); the `make` workflow installs everything else (see [`Brewfile`](Brewfile): minikube, kubectl, helm, helmfile, k9s, colima, docker CLI).
- **Windows 10/11** — winget + Docker Desktop (WSL2 engine); `windows\start.cmd tools` installs everything else. See [`windows/README.md`](windows/README.md).
- **Linux** — everything except colima is cross-platform. Install `minikube`, `kubectl`, `helm`, and `helmfile`, point Docker at your local daemon, then run the same `minikube start --profile dc34 --driver=docker --cpus=4 --memory=6144 --cni=cilium --addons=metrics-server` followed by `helmfile sync`. Ask in the BTV Discord if you get stuck.

## Quick start

Clone the repo:

```sh
git clone https://github.com/blueteamvillage/btv-k8s-sandbox-infrastructure.git
cd btv-k8s-sandbox-infrastructure
```

**macOS:**

```sh
make tools & make up
```

**Windows** (PowerShell or cmd — full guide in [`windows/README.md`](windows/README.md)):

```powershell
windows\start.cmd tools    # once; then start Docker Desktop and open a new terminal
windows\start.cmd up
```

First run takes several minutes (VM image, cluster bootstrap, Helm charts). Verify everything is healthy:

```sh
make status                          # Windows: windows\start.cmd verify
kubectl --context dc34 get pods -A   # everything Running/Completed
```

| macOS | Windows | What it does |
|---|---|---|
| `make up` | `start.cmd up` | Start the VM + cluster, deploy the sandbox stack. Safe to re-run. |
| `make status` | `start.cmd status` | Show VM and cluster health. |
| — | `start.cmd verify` | Automated health check (cluster, nodes, Tetragon, Kyverno). |
| `make stop` | `start.cmd stop` | Pause the cluster — **state is preserved**, `up` resumes where you left off. |
| `make clean` | `start.cmd clean` | Tear down everything (macOS: including the VM disk). Full reset. |
| `make tools` | `start.cmd tools` | Just install/update the CLI tools (Homebrew / winget). |

## Deploying challenges

Every challenge is a ready-to-apply manifest in [`challenges/`](challenges) paired with a container image from the Blue Team Village registry (`ghcr.io/blueteamvillage/challenge-<NNN>`). Each manifest is **self-contained** — one apply creates the challenge's namespace and its pod:

```sh
kubectl --context dc34 apply -f challenges/challenge-000.pod.yaml
kubectl --context dc34 -n challenge-000 get pods
```

Then dig into the evidence:

```sh
# poke around inside the pod
kubectl --context dc34 -n challenge-000 exec -it challenge-000 -- sh

# or copy the artifacts to your machine
kubectl --context dc34 -n challenge-000 cp challenge-000:/forensics ./challenge-000-forensics
```

Two kinds of challenges:

- **Standalone** (`challenge-<NNN>.pod.yaml`) — each deploys into its own `challenge-<NNN>` namespace.
- **Converged Frontier scenarios** (`challenge-001-s<NNN>-*.challenge.pod.yaml`) — ten scenarios, each in a **`-beginner`** and a **`-pro`** variant; pick the track that fits you. They all share the `converged-frontier` namespace and can run side by side.

### Challenge images

The images are **private until the event**. At the village you'll receive credentials; pull the image on your machine and load it into the cluster (the pods use `imagePullPolicy: IfNotPresent`, so the loaded image is used without any in-cluster registry setup):

```sh
docker login ghcr.io -u <your-github-username>   # paste the token from the organizers
docker pull ghcr.io/blueteamvillage/challenge-000:latest
minikube -p dc34 image load ghcr.io/blueteamvillage/challenge-000:latest
```

Build the sandbox ahead of time, and you'll be ready to pull and play the moment doors open.

### Removing a challenge

```sh
kubectl --context dc34 -n challenge-000 delete pod challenge-000
```

`kubectl delete -f <file>` also works for standalone challenges (it removes that challenge's namespace too), but **avoid it for Converged Frontier files** — it deletes the shared `converged-frontier` namespace and with it every scenario pod you have running. Delete individual pods there instead.

## Guardrails you'll run into (they're features, not bugs)

The sandbox is deliberately hardened. If a pod won't schedule or can't reach the network, it's probably one of these:

- **Restricted Pod Security** — Kyverno enforces the Kubernetes `restricted` Pod Security Standard on all workloads. Pods requesting privileged mode, host namespaces, root users, etc. are **rejected at admission**.
- **Default-deny networking** — every namespace automatically receives deny-all ingress *and* egress NetworkPolicies. Workloads can't phone home unless a policy allows it.
- **Resource caps** — every namespace gets a ResourceQuota (max 5 pods, 2 CPU / 2 Gi requests, 4 CPU / 4 Gi limits) and a LimitRange (containers default to 500m / 512 Mi).

Namespaces can opt out of individual guardrails via labels — challenge manifests set these where needed, and you can too when experimenting:

| Label on the namespace | Effect |
|---|---|
| `blueteamvillage.org/allow-inbound: "true"` | Skip the default-deny **ingress** policy |
| `blueteamvillage.org/allow-outbound: "true"` | Skip the default-deny **egress** policy |
| `blueteamvillage.org/disable-quotas: "true"` | Skip the ResourceQuota |
| `blueteamvillage.org/disable-limits: "true"` | Skip the LimitRange |

(`kube-system` and `kyverno` are exempt from all of the above.)

## Handy commands

```sh
# Cluster access — the kubectl context is "dc34"
kubectl --context dc34 get pods -A

# Interactive TUI for the cluster
k9s --context dc34

# Watch Tetragon runtime events (process execs, connections, ...)
kubectl --context dc34 logs -n kube-system ds/tetragon -c export-stdout -f

# See which workloads Kyverno policies flagged
kubectl --context dc34 get policyreports -A

# List active guardrails in a namespace
kubectl --context dc34 get networkpolicy,resourcequota,limitrange -n <namespace>
```

## Troubleshooting

- **`up` failed partway** — it's idempotent; just run it again. `helmfile sync` picks up where it left off.
- **Docker commands hit the wrong daemon** (macOS) — this setup uses the Docker context `colima-dc34`. `make` exports it automatically; in a plain shell run `docker context use colima-dc34`.
- **Everything is slow / pods evicted** — the VM has 8 GB RAM and 4 CPUs. Close other heavy apps, or bump the numbers in the [`Makefile`](Makefile) if your machine has headroom.
- **Weird unrecoverable state** — `clean` then `up` gives you a factory-fresh sandbox in minutes.
- **Windows-specific issues** (Docker Desktop, WSL2, Git Bash, execution policy) — see [`windows/README.md`](windows/README.md#troubleshooting).

## After the competition

- `make stop` / `windows\start.cmd stop` — pause the sandbox and free CPU/RAM; your cluster state survives.
- `make clean` / `windows\start.cmd clean` — delete the cluster (and on macOS the VM and its disk) entirely.

## Getting help

Find us in the **Blue Team Village Discord** or flag down BTV staff at the village — we're happy to help you get your sandbox running before the CTF starts. Good hunting! 🔵
