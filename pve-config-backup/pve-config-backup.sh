#!/bin/bash

# set -x
# set -e         ### Wahlweise für Stops/Debugs

# 1. UMGEBUNG LADEN
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.env" ]; then
    # Filtert Kommentare und exportiert die Variablen sauber
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
else
    echo "[$(date)] FEHLER: .env Datei wurde nicht gefunden!" >&2
    exit 1
fi

# 2. RUNTIME VARIABLEN (Bleiben im Skript)
DATE=$(date +%F)
ERRORS=0

# Wandelt den PVE_NODES-String aus der .env in ein echtes Bash-Array um
NODES=($PVE_NODES)

# Sicherheitsprüfung: Wurden Nodes und Pfad geladen?
if [ ${#NODES[@]} -eq 0 ] || [ -z "$BACKUP_BASE" ]; then
    echo "[$(date)] FEHLER: Wichtige Konfigurationsvariablen fehlen in der .env!" >&2
    exit 1
fi

# 3. BACKUP WORKFLOW
for NODE in "${NODES[@]}"; do
    DEST="${BACKUP_BASE}/${NODE}"
    mkdir -p "$DEST"

    ssh -i "$SSH_KEY_PVE" -o StrictHostKeyChecking=no \
    "${REMOTE_USER_PVE}@${NODE}" \
    "tar czf - /etc/pve 2>/dev/null" > "${DEST}/etc-pve.tar.gz"

    rsync -az \
        -e "ssh -i $SSH_KEY_PVE -o StrictHostKeyChecking=no" \
        "${REMOTE_USER_PVE}@${NODE}:/etc/network/interfaces" "${DEST}/" || ERRORS=$((ERRORS+1))

    rsync -az \
        -e "ssh -i $SSH_KEY_PVE -o StrictHostKeyChecking=no" \
        "${REMOTE_USER_PVE}@${NODE}:/etc/corosync/" "${DEST}/corosync/" || ERRORS=$((ERRORS+1))

    ARCHIVE="${BACKUP_BASE}/pve-config-${NODE}-${DATE}.tar.gz"
    tar czf "$ARCHIVE" -C "$BACKUP_BASE" "$NODE" 2>/dev/null

    # Zielordner auf VPS anlegen und Archiv schieben
    ssh -i "$SSH_KEY_VPS" -o StrictHostKeyChecking=no \
        "${REMOTE_USER_VPS}@${REMOTE_HOST_VPS}" \
        "mkdir -p /backups/proxmox/${NODE}"

    if rsync -az --delete \
        -e "ssh -i $SSH_KEY_VPS -o StrictHostKeyChecking=no" \
        "$ARCHIVE" \
        "${REMOTE_USER_VPS}@${REMOTE_HOST_VPS}:/backups/proxmox/${NODE}/"; then
        echo "[$(date)] ${NODE}: Backup OK"
    else
        echo "[$(date)] ${NODE}: FEHLER beim Transfer zum VPS!" >&2
        ERRORS=$((ERRORS+1))
    fi
done

# Sicherheitsnetz: Nur löschen, wenn BACKUP_BASE existiert und nicht das Root-Verzeichnis ist
if [ -d "$BACKUP_BASE" ] && [ "$BACKUP_BASE" != "/" ]; then
    rm -rf "$BACKUP_BASE"
fi

# 4. AUSWERTUNG
if [ $ERRORS -gt 0 ]; then
    echo "[$(date)] Fertig mit $ERRORS Fehler(n)!" >&2
    exit 1
else
    echo "[$(date)] Alle Backups erfolgreich."
fi