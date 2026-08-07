# Challenges

Every file here is a ready-to-apply Kubernetes manifest for one CTF challenge. Each one is **self-contained** — a single `apply` creates the challenge's namespace *and* its pod, so there's no setup order to get right.

**Everything in this directory is inert.** These pods carry pre-collected forensic evidence — logs, Tetragon event captures, artifact dumps, cloud audit trails — and nothing in them detonates. They run unprivileged, as a non-root user, with all capabilities dropped, which is why they pass the sandbox's restricted Pod Security enforcement without any exception. The live-malware **"Option B"** variants that the CTF site advertises are not in this repo; those come through the event channels.

New here? Start with the [main README](../README.md) to get the `dc34` cluster running, then come back.

## Deploy one

```sh
kubectl --context dc34 apply -f challenges/challenge-000.pod.yaml
kubectl --context dc34 -n challenge-000 get pods
```

Then go find the evidence:

```sh
kubectl --context dc34 -n challenge-000 exec -it challenge-000 -- sh

# or pull it back to your machine and work locally
kubectl --context dc34 -n challenge-000 cp challenge-000:/forensics ./challenge-000-forensics
```

**Stuck in `ImagePullBackOff`?** Expected before the event — the images are private on GHCR until the CTF opens. See [Pulling challenge images](../README.md#pulling-challenge-images) in the main README; [`scripts/pull-btv-images.sh`](../scripts/pull-btv-images.sh) fetches and side-loads all of them in one pass.

## Where the evidence lives

The path differs by family, so `ls /` first if you're not sure what you're in.

| Family | Evidence path | Start with |
|---|---|---|
| Standalone (`challenge-<NNN>.pod.yaml`) | `/forensics` | `cat /forensics/tetragon-events.json` |
| Converged Frontier (`challenge-001-s<NNN>-*`) | `/challenge` | `cat /challenge/README.md`, then `ls -R /challenge/evidence/` |
| Tracked standalone (`challenge-023-*`) | `/challenge` | `cat /challenge/CONTESTANT-GUIDE.md`, then `find /challenge/evidence -type f \| sort` |
| Cloud Attack Forensics (`challenge-024.pod.yaml`) | `/forensics` | `cat /forensics/README.md`, then `sha256sum -c /forensics/checksums.sha256` |

## The four families

### Standalone — Container & Malware Forensics

One namespace per challenge (`challenge-<NNN>`), one pod, one malware family to work out. These are the site's **"Option A"** forensic snapshots.

The numbering is not contiguous: **there is no `challenge-014`.** A gap doesn't mean your clone is broken.

| Challenge | Scenario |
|---|---|
| `000` | `bpfdoor-redmenshen-backdoor` |
| `002` | `gafgyt-telnet-loader-bot` |
| `003` | `kinsing-sustes-dropper` |
| `004` | `libprocesshider-readdir-hook-rootkit` |
| `005` | `lightning-framework-modular-c2` |
| `006` | `messagetap-sms-imsi-interceptor` |
| `007` | `mirai-botkill-c2-loader` |
| `008` | `necrobot-python-xmrig-loader` |
| `009` | `ok-readdir-hook-port-hiding-rootkit` |
| `010` | `redxor-po1kitd-proxy-backdoor` |
| `011` | `rocke-cryptominer-dropper` |
| `012` | `shellbot-pam-credential-backdoor` |
| `013` | `shikitega-polyglot-coinminer-dropper` |
| `015` | `symbiote-ldpreload-credential-rootkit` |
| `016` | `syslogk-starttls-shell-rootkit` |
| `017` | `sysrv-xmrig-base64-coinminer-dropper` |
| `018` | `vermilionstrike-cobaltstrike-beacon` |
| `019` | `webshell-rat-persistence` |
| `020` | `winnti-azazel-userland-rootkit-backdoor` |
| `021` | `xanthe-docker-coinminer` |
| `022` | `xorddos-initd-ddos-trojan` |

The scenario name is also a label, so you can find a pod without remembering its number:

```sh
kubectl --context dc34 get pods -A -l scenario=bpfdoor-redmenshen-backdoor
```

### Converged Frontier

Ten scenarios, each shipped in a **`-beginner`** and a **`-pro`** variant — pick whichever fits you. All twenty share the `converged-frontier` namespace and can run side by side.

| Scenario | Title | Files |
|---|---|---|
| `s01` | Cloud-to-OT Control Plane Compromise | `challenge-001-s001-{beginner,pro}.challenge.pod.yaml` |
| `s02` | The Silent Historian | `challenge-001-s002-{beginner,pro}.challenge.pod.yaml` |
| `s03` | The Poisoned Pipeline | `challenge-001-s003-{beginner,pro}.challenge.pod.yaml` |
| `s04` | The Exposed Controller | `challenge-001-s004-{beginner,pro}.challenge.pod.yaml` |
| `s05` | The Frosted Loop | `challenge-001-s005-{beginner,pro}.challenge.pod.yaml` |
| `s06` | The Ghost VPN | `challenge-001-s006-{beginner,pro}.challenge.pod.yaml` |
| `s07` | The Living Tenant | `challenge-001-s007-{beginner,pro}.challenge.pod.yaml` |
| `s08` | The Carrier Shadow | `challenge-001-s008-{beginner,pro}.challenge.pod.yaml` |
| `s09` | The Vendor Tunnel | `challenge-001-s009-{beginner,pro}.challenge.pod.yaml` |
| `s10` | The Hypervisor Blackout | `challenge-001-s010-{beginner,pro}.challenge.pod.yaml` |

**Mind the zero-padding.** Filenames, pod names, and image tags use `s001`–`s010`; the `scenario` label and the CTF site use `s01`–`s10`. Site scenario S01 is the file `challenge-001-s001-*`, and you select it with `-l scenario=s01`:

```sh
kubectl --context dc34 -n converged-frontier get pods -l scenario=s01
kubectl --context dc34 -n converged-frontier get pods -l track=pro
```

### Tracked standalone

| Challenge | Scenario | Files |
|---|---|---|
| `023` | `lunar-spider-scenario` ("Ghost in the Assistant") | `challenge-023-{beginner,pro}.challenge.pod.yaml` |

Both variants share the `challenge-023` namespace and carry **identical** evidence, questions, hints, and points — the track is a delivery label only. Run either; running both is fine.

### Cloud Attack Forensics

No malware at all in this one — it's an AWS log investigation, contributed by the **DEF CON Cloud Village**.

| Challenge | Scenario | File |
|---|---|---|
| `024` | `groundlink-intrusion` ("GroundLink Intrusion: Ten Techniques") | `challenge-024.pod.yaml` |

One gzipped native CloudTrail corpus of 211 records — 10 form the incident chain, 201 are routine or decoy — and you reconstruct the intrusion with `jq` across ten objectives. Evidence is at `/forensics`, same as the standalone family:

```sh
kubectl --context dc34 apply -f challenges/challenge-024.pod.yaml
kubectl --context dc34 -n challenge-024 exec -it challenge-024 -- sh
# then:
cd /forensics && sha256sum -c checksums.sha256 && cat README.md
```

Two things differ from the other challenges:

- **`/forensics` is read-only and `/work` is where you write.** `/work` is an `emptyDir` and also `$HOME`, so shell history and `jq` output land there. It's wiped when the pod goes away — `kubectl cp` anything you want to keep.
- **The published package is multi-arch** (`linux/amd64` + `linux/arm64`), so pulling it from GHCR gets you your node's native architecture rather than an emulated one. Note this applies to a *pull*: an image side-loaded from a local build is whatever platform that build targeted, and the default is `amd64`, which runs under QEMU on an arm64 node exactly like the malware images. `ps -o args` inside the pod will show a `qemu-x86_64` interpreter if you're emulated. Nothing about the challenge depends on this either way — it's `jq` over a 33 KB file.

There's also an optional offline browser aid at `/forensics/workbench`. It's a convenience, not the intended path — the CLI and `jq` workflow is canonical, and the workbench grades nothing and reveals nothing.

It takes **two steps**, and they're easy to half-do. Start the web server *inside* the pod first:

```sh
kubectl --context dc34 -n challenge-024 exec challenge-024 -- \
  sh -c 'httpd -f -p 8080 -h /forensics/workbench >/dev/null 2>&1 &'
```

Confirm something is actually listening before you forward — this one line saves a lot of confusion:

```sh
kubectl --context dc34 -n challenge-024 exec challenge-024 -- netstat -ltn | grep 8080
```

Then forward it and open <http://127.0.0.1:8080/>:

```sh
kubectl --context dc34 -n challenge-024 port-forward pod/challenge-024 8080:8080
```

`port-forward` proxies through the API server rather than the pod network, so the namespace's default-deny egress policy doesn't block it.

### "port-forward keeps breaking"

If you see this — port-forward announces itself, then dies the moment you load the page:

```text
Forwarding from 127.0.0.1:8080 -> 8080
Handling connection for 8080
an error occurred forwarding 8080 -> 8080: ... socat[...] E connect(5, AF=2 127.0.0.1:8080, 16): Connection refused
error: lost connection to pod
```

…then `port-forward` is fine and **nothing is listening on 8080 inside the pod.** It is relaying a connection-refused from the container. `curl` reports the same thing as `curl: (52) Empty reply from server`.

Almost always one of:

- **`httpd` was never started.** Run the first command above.
- **The pod was recreated.** `httpd` is started by hand and does not come back on its own; a `delete pod` / re-apply cycle leaves you with no listener. Start it again.
- **`httpd` was started but died.** Check with `pgrep -a httpd` inside the pod.

Deliberately *not* the cause, so don't go hunting there: the default-deny NetworkPolicy (port-forward doesn't traverse the pod network), and the read-only root filesystem (`httpd` serves `/forensics` read-only and writes nothing).

## Cleaning up

Deleting the pod is almost always what you want, and it leaves the namespace ready for a re-apply:

```sh
kubectl --context dc34 -n challenge-000 delete pod challenge-000
```

`kubectl delete -f <file>` also works, but it removes the **namespace** in that file — which is fine for a standalone challenge and destructive for a shared one:

- Any **Converged Frontier** file takes down `converged-frontier` and every scenario pod running in it.
- Either **`challenge-023`** file takes down both `023` track pods.

Delete pods individually in those two namespaces.

## Things that will surprise you

- **Pods never restart.** Every manifest sets `restartPolicy: Never`, because static evidence has nothing to recover by restarting. A pod that reaches `Completed` or `Error` stays there — delete it and re-apply.
- **The pod can't reach the network,** by design. Every namespace gets default-deny ingress *and* egress NetworkPolicies, so no challenge can phone home. Work the evidence from inside the pod or copy it out with `kubectl cp`.
- **You get 5 pods per namespace.** The auto-generated ResourceQuota caps each namespace at 5 pods. `converged-frontier` is the exception — it opts out via `blueteamvillage.org/disable-quotas`, which is how all 20 scenario pods coexist. Challenge resource requests are tiny (100m CPU / 128Mi limits at most), so the quota is only a problem if you add your own workloads.
- **`kubectl run` gets rejected.** Restricted Pod Security is enforced cluster-wide, and a bare `kubectl run` doesn't set the `securityContext` fields it demands. Copy the `securityContext` block out of any manifest here as a starting point for your own scratch pods.
- **The whole thing is yours.** Nothing here touches shared infrastructure — if you wedge the cluster, `make clean && make up` gives you a fresh one in minutes.

Details on all of the above are in [Guardrails you'll run into](../README.md#guardrails-youll-run-into-theyre-features-not-bugs).

## Need help?

Ask in the **Blue Team Village Discord** or find BTV staff at the village. Good hunting! 🔵
