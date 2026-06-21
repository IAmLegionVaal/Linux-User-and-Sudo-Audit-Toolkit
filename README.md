# Linux User and Sudo Audit Toolkit

A Linux support toolkit for auditing local accounts and repairing selected user, sudo-group and home-directory problems.

## Audit script

```bash
chmod +x src/linux_user_sudo_audit.sh
sudo ./src/linux_user_sudo_audit.sh
```

The audit reports account state, enabled shells, password ageing, sudo or wheel membership, sudoers syntax, SSH-key indicators, login history and orphaned ownership findings.

## Repair script

Preview a sudo-group change:

```bash
chmod +x src/linux_user_sudo_repair.sh
sudo ./src/linux_user_sudo_repair.sh --add-sudo --user exampleuser --dry-run
```

Manage sudo-group membership:

```bash
sudo ./src/linux_user_sudo_repair.sh --add-sudo --user exampleuser
sudo ./src/linux_user_sudo_repair.sh --remove-sudo --user exampleuser
```

Lock or unlock an existing account:

```bash
sudo ./src/linux_user_sudo_repair.sh --lock-user --user exampleuser
sudo ./src/linux_user_sudo_repair.sh --unlock-user --user exampleuser
```

Repair ownership of one standard home directory:

```bash
sudo ./src/linux_user_sudo_repair.sh --fix-home-owner --user exampleuser
```

## What the repair does

- Works only with an existing non-system local account.
- Adds or removes membership in the detected sudo or wheel group.
- Refuses to remove the final privileged-group account.
- Can lock or unlock the selected account password.
- Can repair ownership of the selected user's configured home directory.
- Validates sudo configuration and records before-and-after state.
- Supports confirmation prompts, dry-run, logs and clear exit codes.

## Safety and privacy

The tool does not create or delete accounts, set passwords or expose SSH key material. Recursive home-directory ownership repair can take time and should be used only when ownership is known to be incorrect.

## Author

Dewald Pretorius — L2 IT Support Engineer
