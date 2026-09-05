#!/bin/bash
# Uruchamiac WEWNATRZ kontenera PBS (nie na hoscie - patrz README, sekcja "Dlaczego dwie warstwy").
# Podmienia jeden plik (.lock) w read-only mouncie offsite lokalnym, zapisywalnym plikiem,
# zeby proxmox-backup-proxy mogl normalnie dzialac bez prawa zapisu na offsite.
set -e

MOUNT_POINT="/mnt/immutable-backup"
SHIM_DIR="/root/.immutable-backup-shim"

mkdir -p "$SHIM_DIR"
touch "$SHIM_DIR/lock"
chown backup:backup "$SHIM_DIR/lock"
chmod 0666 "$SHIM_DIR/lock"

mountpoint -q "$MOUNT_POINT/.lock" || \
  mount --bind "$SHIM_DIR/lock" "$MOUNT_POINT/.lock"
