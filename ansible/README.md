# Ansible: server hardening

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

## Notes

- **Bootstrap on a fresh server.** The first run has to connect as `root`
  (`ansible_user: root` in `inventory.yml`), because the admin user does not
  exist yet. Once the role has disabled root login, switch back to
  `ansible_user: "{{ admin_user }}"`; tasks then run through sudo (`become: true`).
- **`--check` on a fresh server.** The `authorized_key` task fails in check mode
  because the admin user was not really created. This is expected; later runs
  pass.
- **Verify effective settings, not files.** On the server use `sudo sshd -T` and
  `apt-config dump`; they show the merged configuration that is actually in use.
- **ansible-lint warnings** about the deprecated `oneline` and `tree` callbacks
  come from ansible-core itself, not from this project.
