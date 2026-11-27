# Ansible: server hardening and K3s

Configures the inside of the lab server that Terraform creates in `../terraform`.
Ansible is agentless: it connects over SSH from the workstation and needs only
Python on the server.

## What the `hardening` role does

- **Admin user.** Creates `admin_user` (set in `group_vars/all.yml`) with
  passwordless sudo and only the lab SSH key in `authorized_keys`. The sudoers
  drop-in is checked with `visudo` before it is written, so a typo cannot break
  sudo.
- **SSH.** Writes `/etc/ssh/sshd_config.d/00-hardening.conf`: no root login, no
  passwords, public key only, `AllowUsers` limited to the admin user. The `00-`
  prefix matters: sshd keeps the *first* value it reads, and cloud-init ships
  `50-cloud-init.conf`. The file is validated with `sshd -t` before it is
  written, and sshd restarts only when the file changes. TCP forwarding stays
  enabled for the SSH tunnels to the Kubernetes API and Grafana.
- **Security updates.** Enables unattended-upgrades with a reboot at 03:30 UTC
  when an update requires one. The overrides live in
  `/etc/apt/apt.conf.d/52unattended-upgrades-local`: apt keeps the *last* value
  it reads, so the distro's `50unattended-upgrades` stays untouched.

## What the `k3s` role does

- **Pinned install.** Installs `k3s_version` from `roles/k3s/defaults/main.yml`
  with the install script from the same release tag, not the moving
  `https://get.k3s.io`. The script is checked against a SHA-256 before it runs,
  and the script itself verifies the K3s binary against the release checksums.
  The installer runs only when the installed version differs, so an upgrade
  means changing `k3s_version` and `k3s_install_script_sha256` and running the
  playbook again.
- **Config file, not installer flags.** `/etc/rancher/k3s/config.yaml` comes
  from a template, and a change restarts K3s through a handler. Traefik and
  ServiceLB are disabled because nothing is published from the cluster.
  Secrets are encrypted at rest (`secrets-encryption`).
- **Kubeconfig on the workstation.** The admin kubeconfig is fetched to
  `~/.kube/socialagent-lab.yaml` with mode `0600`. It points to
  `https://127.0.0.1:6443`, which works only through the SSH tunnel below.

## Prerequisites

- The server exists (`terraform apply`) and `LAB_SERVER_IP` is set via
  `source ../.env`. If it is not set, the inventory stops with a clear message
  instead of passing an empty host to SSH.
- Collections are installed: `ansible-galaxy collection install -r requirements.yml`.

## Usage

```bash
cd ansible
source ../.env
ansible all -m ping                       # can Ansible log in and find Python?
ansible-playbook site.yml --check --diff  # dry run, shows what would change
ansible-playbook site.yml --diff          # apply
ansible-playbook site.yml                 # a second run must report changed=0
ansible-lint                              # passes with the production profile
```

## Accessing the cluster

Port 6443 is closed in the Hetzner firewall, so the Kubernetes API is reachable
only through an SSH tunnel:

```bash
ssh -N -L 6443:127.0.0.1:6443 tomajz@"$LAB_SERVER_IP"   # terminal 1, keep it open
kubectl get nodes                                        # terminal 2, KUBECONFIG comes from ../.env
```

Once the monitoring stack is installed, `../scripts/lab-tunnel.sh up` opens
this tunnel together with the monitoring UIs in the background.

## Notes

- **Bootstrap on a fresh server.** The first run has to connect as `root`
  (`ansible_user: root` in `inventory.yml`), because the admin user does not
  exist yet. Once the role has disabled root login, switch back to
  `ansible_user: "{{ admin_user }}"`; tasks then run through sudo (`become: true`).
- **`--check` on a fresh server.** Some tasks fail in check mode because the
  step before them was only simulated: `authorized_key` (the admin user was not
  really created) and the k3s service task (K3s was not really installed). This
  is expected; later runs pass.
- **Verify effective settings, not files.** On the server use `sudo sshd -T` and
  `apt-config dump`; they show the merged configuration that is actually in use.
- **ansible-lint warnings** about the deprecated `oneline` and `tree` callbacks
  come from ansible-core itself, not from this project.
