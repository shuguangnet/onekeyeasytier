---
name: easytier-fleet-ssh
description: Discover and manage SSH connections to servers on the local EasyTier overlay using the machine-local structured asset inventory. Use when Codex needs to list EasyTier nodes, refresh peer state, inspect online/offline assets, trust a verified SSH host fingerprint, connect by node alias or overlay IP, or execute a command on an explicitly selected EasyTier node.
---

# EasyTier Fleet SSH

Operate only through `/usr/local/bin/et-ssh`. It reads the structured inventory at
`/var/lib/easytier-assets/nodes.json` and enforces strict SSH host-key checking.

## Resolve The Target

1. Run `et-ssh refresh` before decisions based on current state.
2. Run `et-ssh list` to inspect aliases, overlay IPs, online state, versions, and trust state.
3. Require one exact alias or overlay IP. Do not expand a single-host request into a batch.
4. Use overlay addresses only. Do not substitute a public IP without explicit user direction.

## Establish Trust

For an untrusted target, obtain its expected Ed25519 SHA256 fingerprint through the provider
console, an existing trusted session, or directly on that target:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Then trust the exact target and fingerprint:

```bash
et-ssh trust <alias> SHA256:expectedFingerprint
```

Never trust an `ssh-keyscan` result by itself. Never use `StrictHostKeyChecking=no`,
`UserKnownHostsFile=/dev/null`, or delete known-host records merely to bypass a mismatch.

## Connect Or Execute

Open an interactive session:

```bash
et-ssh connect <alias>
```

Execute a command:

```bash
et-ssh exec <alias> 'systemctl --failed'
```

Treat every remote command as a production operation. Before destructive, firewall, SSH,
storage, reboot, or permission changes, state the exact alias and resource. Verify changes with
service state, a health endpoint, a listening port, process state, or application output.

## Handle Failures

- If the node is offline, report that state and do not fall back to its public address.
- If the host key is unknown, request the expected fingerprint from a trusted channel.
- If the host key changed, stop and report the mismatch; do not replace it automatically.
- If authentication fails, report that an authorized SSH key or agent identity is required.
- Do not print private keys, network secrets, tokens, or unrelated sensitive logs.
