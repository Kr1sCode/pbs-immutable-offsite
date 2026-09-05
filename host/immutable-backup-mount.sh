#!/bin/bash
# Montuje offsite (Hetzner Storage Box) jako drugi, tylko-do-odczytu datastore PBS.
# Podmien wartosci ponizej przed uzyciem.
set -e

STORAGEBOX_USER="uXXXXXX"                       # np. u123456
STORAGEBOX_HOST="${STORAGEBOX_USER}.your-storagebox.de"
REMOTE_PATH="./pbs-offsite/"                    # katalog na Storage Boxie z danymi PBS
SSH_KEY="/root/.ssh/id_ed25519"                 # klucz z dostepem do Storage Boxa
MOUNT_POINT="/mnt/immutable-backup"

mkdir -p "$MOUNT_POINT"

mountpoint -q "$MOUNT_POINT" || \
  sshfs -p 23 -o ro,uid=34,gid=34,IdentityFile="$SSH_KEY",StrictHostKeyChecking=accept-new,allow_other,reconnect,ServerAliveInterval=15 \
  "${STORAGEBOX_USER}@${STORAGEBOX_HOST}:${REMOTE_PATH}" "$MOUNT_POINT"
