# Linux User and Sudo Audit Toolkit

A read-only Bash toolkit for auditing Linux local accounts, privileged groups, sudo access, password ageing, SSH keys, and recent account activity.

## Features

- Local account inventory and UID classification
- Enabled shells, locked accounts, and password ageing
- Sudo and wheel group membership
- Sudoers syntax and include-file inventory
- SSH authorised-key inventory without exposing key material
- Recent login, failed-login, and lastlog evidence
- Orphaned file ownership checks in selected paths
- CSV and JSON exports

## Usage

```bash
chmod +x src/linux_user_sudo_audit.sh
sudo ./src/linux_user_sudo_audit.sh
```

## Safety and privacy

The toolkit does not create, unlock, disable, delete, or modify users. Reports may contain usernames and login metadata; sanitise them before external sharing.

## Validation

Test with standard users, a locked lab account, a sudo-enabled account, and an account with an SSH key.

## Author

Dewald Pretorius — L2 IT Support Engineer
