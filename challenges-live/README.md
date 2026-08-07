# challenges-live

Opt-in **live detonation** sandboxes for the local `dc34` cluster.

These are separate from the inert forensic pods under [`challenges/`](../challenges/). Each subdirectory builds an inert tooling image and fetches sample bytes at runtime from a third-party URL.

| Directory | Kubernetes namespace / pod | Launch |
|-----------|---------------------------|--------|
| [`challenge_000_live`](challenge_000_live/) | `challenge-000-live` | `cd challenge_000_live && make challenge_000_live` |

Hard requirement: `kubectl --context=dc34` only. See each challenge README for gates and network policy notes.
