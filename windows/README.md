# Windows setup — DC34 K8s Sandbox

Windows path to the **same sandbox as macOS** (`make up`): a local minikube cluster with Cilium, Tetragon, and Kyverno. Docker Desktop's WSL2 engine takes the place of colima; everything else is identical, including the `dc34` cluster profile.

## Prerequisites

| Resource | Minimum | Notes |
|----------|---------|-------|
| OS | Windows 10/11 x64 | Virtualization enabled in firmware (required for WSL2) |
| CPU | 4 cores | Matches `minikube start --cpus=4` |
| RAM | 8 GiB | minikube node gets 6144 MiB; leave headroom for Docker Desktop |
| Disk | 20 GiB free | minikube image + Helm charts + challenge images |

You'll also need **winget** (App Installer, preinstalled on modern Windows — otherwise grab it from the Microsoft Store).

## Quick start

From a PowerShell or cmd prompt in the repo root:

```powershell
windows\start.cmd tools    # once — installs Docker Desktop, minikube, kubectl, helm, helmfile, Git
windows\start.cmd up       # start the cluster + deploy the sandbox stack
windows\start.cmd verify   # automated health check
```

Between `tools` and `up`:

1. Start **Docker Desktop** and wait until the whale icon shows **Running**.
2. Check **Settings → General → Use the WSL 2 based engine** (reboot if prompted).
3. Open a **new terminal** so the freshly installed tools are on `PATH`.

`start.cmd` bypasses PowerShell execution policy, so no `Set-ExecutionPolicy` changes are needed. All commands:

| Command | What it does |
|---|---|
| `windows\start.cmd tools` | Install CLI tools via winget (helmfile from GitHub releases). |
| `windows\start.cmd up` | Start minikube (`dc34` profile) and deploy Tetragon + Kyverno. Safe to re-run. |
| `windows\start.cmd verify` | Automated health check: cluster, nodes, Tetragon, Kyverno. |
| `windows\start.cmd status` | Show cluster health at a glance. |
| `windows\start.cmd stop` | Pause the cluster — state preserved. |
| `windows\start.cmd clean` | Delete the minikube profile and kubectl context. |

Everything else — the guardrails you'll run into, handy `kubectl`/`k9s` commands — is in the [main README](../README.md) and works the same on Windows.

## Deploying challenges

Identical to the [main README](../README.md#deploying-challenges) flow — kubectl accepts both `\` and `/` in file paths on Windows. From PowerShell in the repo root:

```powershell
kubectl --context=dc34 apply -f challenges\challenge-000.pod.yaml
kubectl --context=dc34 -n challenge-000 get pods

# poke around inside the pod
kubectl --context=dc34 -n challenge-000 exec -it challenge-000 -- sh

# or copy the artifacts to your machine
kubectl --context=dc34 -n challenge-000 cp challenge-000:/forensics .\challenge-000-forensics
```

The challenge images are **private until the event**. Pull them through Docker Desktop and load them into the cluster (the pods use `imagePullPolicy: IfNotPresent`, so no in-cluster registry setup is needed):

```powershell
docker login ghcr.io -u <your-github-username>   # paste the token from the organizers
docker pull ghcr.io/blueteamvillage/challenge-000:latest
minikube -p dc34 image load ghcr.io/blueteamvillage/challenge-000:latest
```

See the main README for the challenge layout (standalone vs Converged Frontier beginner/pro scenarios) and the cleanup caveat about the shared `converged-frontier` namespace.

## What `up` does

1. Asserts `docker`, `minikube`, `kubectl`, `helm`, `helmfile`, and Git Bash are installed, and Docker Desktop is running
2. `minikube start -p dc34 --driver=docker --cpus=4 --memory=6144 --cni=cilium --addons=metrics-server`
3. `helmfile sync --enable-live-output` — installs Tetragon, Kyverno, and the guardrail policies

First run downloads images and charts; expect several minutes.

**Why Git Bash?** The helmfile config uses a `bash` presync hook to wait for Kyverno's webhook, so a bash on `PATH` is required. The script prefers Git for Windows (`C:\Program Files\Git\bin\bash.exe`), installed by `tools`.

Prefer installing tools yourself? The manual equivalent:

```powershell
winget install -e --id Docker.DockerDesktop
winget install -e --id Kubernetes.minikube
winget install -e --id Kubernetes.kubectl
winget install -e --id Helm.Helm
winget install -e --id Git.Git
scoop install helmfile        # or download helmfile.exe from GitHub releases
winget install -e --id Derailed.k9s   # optional

minikube start -p dc34 --driver=docker --cpus=4 --memory=6144 --cni=cilium --addons=metrics-server
bash -lc "helmfile sync --enable-live-output"
```

## WSL2 alternative

If you live entirely inside **WSL2 Ubuntu** (with Docker Desktop WSL integration or a native docker daemon), skip this directory: install `minikube`, `kubectl`, `helm`, and `helmfile` inside WSL and run the same `minikube start`/`helmfile sync` commands from the [main README](../README.md)'s Linux note. This `windows/` tree targets native Windows PowerShell calling Windows-installed CLIs.

## Troubleshooting

### Docker / WSL2

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Docker Desktop is unable to start` | WSL2 engine wedged after reboot/update | Quit Docker; Admin PowerShell: `wsl --shutdown`; start Docker again; wait 2–5 min |
| `docker info` fails | Docker Desktop stopped | Start Docker Desktop; wait for **Running** |
| Docker starts then exits | Virtualization off | Enable virtualization in BIOS; `wsl --install` |
| Docker demands a WSL update | Old WSL kernel (`wsl --status`) | Admin PowerShell: `wsl --shutdown` then `wsl --update --web-download`; reboot |
| `minikube start` hangs / driver error | WSL2 not installed or disabled | `wsl --install`; Docker Settings → WSL2 engine |
| `minikube start` "docker not found" | Tools not on `PATH` in this shell | Open a new terminal after `tools`; launch Docker Desktop once |
| Node NotReady / OOM | Host RAM too low | Close heavy apps |

### helmfile / bash

| Symptom | Cause | Fix |
|---------|-------|-----|
| `bash: command not found` during `up` | Git for Windows missing | `winget install -e --id Git.Git`; reopen shell |
| `cd: ... No such file or directory` from an unexpected distro | `bash` resolves to WSL, not Git Bash | Install Git for Windows; the script prefers `Git\bin\bash.exe`; re-run `up` |
| helmfile presync hook waits forever | Kyverno webhook not ready yet | Wait and re-run `windows\start.cmd up`; check `kubectl --context=dc34 -n kyverno get pods` |
| `helmfile: command not found` | Not on `PATH` | Open a new terminal, or `scoop install helmfile` |
| Path errors in bash | Special characters in repo path | Clone to a simple path, e.g. `C:\Users\<you>\github\btv-k8s-sandbox-infrastructure` |

### General

- **Wrong cluster targeted** — always pass `--context=dc34` to kubectl (or `kubectl config use-context dc34`).
- **"running scripts is disabled"** — use `windows\start.cmd` (it bypasses execution policy), or `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- **Unsure what's broken** — `windows\start.cmd verify` prints a FAIL line per issue.
- **Clean slate** — `windows\start.cmd clean`, restart Docker Desktop, then `windows\start.cmd up`.

Still stuck? Find us in the **Blue Team Village Discord** or at the village.
