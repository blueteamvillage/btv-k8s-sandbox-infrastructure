# Challenges

Every file here is a ready-to-apply Kubernetes manifest for one CTF challenge. Each one is **self-contained** — a single `apply` creates the challenge's namespace *and* its pod, so there's no setup order to get right.

**Everything in this directory is inert.** These pods carry pre-collected forensic evidence — logs, Tetragon event captures, artifact dumps — and nothing in them detonates. They run unprivileged, as a non-root user, with all capabilities dropped, which is why they pass the sandbox's restricted Pod Security enforcement without any exception. The live-malware **"Option B"** variants and the **Cloud Attack Forensics** track that the CTF site advertises are not in this repo; those come through the event channels.

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

## The three families

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
