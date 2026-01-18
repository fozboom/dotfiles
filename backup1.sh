#!/bin/bash
### restic_backup.sh
### See the blog post: https://blog.rymcg.tech/blog/linux/restic_backup/
## Restic Backup Script for S3 cloud storage (and compatible APIs).
## Install the `restic` package with your package manager.
## Copy this script to any directory, and change the permissions:
##   chmod 0700 restic_backup.sh
## Put all your configuration directly in this script.
## Consider creating an alias in your ~/.bashrc: alias backup=<path-to-this-script>
## Edit the variables below (especially the ones like change-me-change-me-change-me):  
## WARNING: This will include plain text passwords for restic and S3
## SAVE A COPY of this configured script to a safe place in the case of disaster.

## Which local directories do you want to backup?
## Specify one or more directories inside this bash array (paths separated by space):
## Directories that don't exist will be skipped:
RESTIC_BACKUP_PATHS=("/Users/daniel/Documents/Neuron")
RESTIC_PASSWORD_FILE=".restic-pass"
## Create a secure encryption passphrase for your restic data:
## WRITE THIS PASSWORD DOWN IN A SAFE PLACE:
## Do NOT store it directly in this script; export RESTIC_PASSWORD (or RESTIC_PASSWORD_FILE) in your shell.
# RESTIC_PASSWORD is expected to be set in the environment

### How often do you want to backup? Use systemd timer OnCalander= notation:
### https://man.archlinux.org/man/systemd.time.7#CALENDAR_EVENTS
### (Backups may occur at a later time if the computer is turned off)
## Hourly on the hour:
# BACKUP_FREQUENCY='*-*-* *:00:00'
## Daily at 3:00 AM:
# BACKUP_FREQUENCY='*-*-* 03:00:00'
## Every 10 minutes:
# BACKUP_FREQUENCY='*-*-* *:0/10:00'
## Systemd also knows aliases like 'hourly', 'daily', 'weekly', 'monthly':
BACKUP_FREQUENCY=daily

## Restic data retention (prune) policy:
# https://restic.readthedocs.io/en/stable/060_forget.html#removing-snapshots-according-to-a-policy
RETENTION_DAYS=7
RETENTION_WEEKS=4
RETENTION_MONTHS=6
RETENTION_YEARS=3
### How often to prune the backups?
## Use systemd timer OnCalendar= notation
### https://man.archlinux.org/man/systemd.time.7#CALENDAR_EVENTS
PRUNE_FREQUENCY=monthly

## The tag to apply to all snapshots made by this script:
## (Default is to use the full command path name)
BACKUP_TAG=${BASH_SOURCE}

## These are the names and paths for the systemd services, you can leave these as-is probably:
BACKUP_ID=${BACKUP_ID:-main}
BACKUP_NAME=restic_backup.${BACKUP_ID}
BACKUP_SERVICE=${HOME}/.config/systemd/user/${BACKUP_NAME}.service
BACKUP_TIMER=${HOME}/.config/systemd/user/${BACKUP_NAME}.timer
PRUNE_NAME=restic_backup.prune.${BACKUP_ID}
PRUNE_SERVICE=${HOME}/.config/systemd/user/${PRUNE_NAME}.service
PRUNE_TIMER=${HOME}/.config/systemd/user/${PRUNE_NAME}.timer

commands=(init now trigger forget prune enable disable status logs prune_logs snapshots restore help)

run_restic() {
    if [[ -z "${RESTIC_PASSWORD}" && -z "${RESTIC_PASSWORD_FILE}" ]]; then
        echo "ERROR: RESTIC_PASSWORD or RESTIC_PASSWORD_FILE is not set. Export one of them before running this script." >&2
        exit 1
    fi
    if [[ -n "${RESTIC_PASSWORD}" ]]; then
        export RESTIC_PASSWORD
    fi
    if [[ -n "${RESTIC_PASSWORD_FILE}" ]]; then
        export RESTIC_PASSWORD_FILE
    fi
    (set -x; restic -v -r rclone:google-drive-backup:ResticBackup "$@")
}

init() { # : Initialize restic repository
    run_restic init
}

now() { # : Run backup now
    ## Test if running in a terminal and have enabled the backup service:
    if [[ -t 0 ]] && [[ -f ${BACKUP_SERVICE} ]]; then
        ## Run by triggering the systemd unit, so everything gets logged:
        trigger
    ## Not running interactive, or haven't run 'enable' yet, so run directly:
    elif run_restic backup --tag ${BACKUP_TAG} ${RESTIC_BACKUP_PATHS[@]}; then
        echo "Restic backup finished successfully."
    else
        echo "Restic backup failed!"
        exit 1
    fi
}

trigger() { # : Run backup now, by triggering the systemd service
    (set -x; systemctl --user start ${BACKUP_NAME}.service)
    echo "systemd is now running the backup job in the background. Check 'status' later."
}

prune() { # : Remove old snapshots from repository
    run_restic prune
}

forget() { # : Apply the configured data retention policy to the backend
    run_restic forget --tag ${BACKUP_TAG} --group-by "paths,tags" \
           --keep-daily $RETENTION_DAYS --keep-weekly $RETENTION_WEEKS \
           --keep-monthly $RETENTION_MONTHS --keep-yearly $RETENTION_YEARS
}

snapshots() { # : List all snapshots
    run_restic snapshots
}

restore() { # [SNAPSHOT] [ROOT_PATH] : Restore data from snapshot (default 'latest')
    SNAPSHOT=${1:-latest}; ROOT_PATH=${2:-/};
    if test -d ${ROOT_PATH} && [[ ${ROOT_PATH} != "/" ]]; then
        echo "ERROR: Non-root restore path already exists: ${ROOT_PATH}"
        echo "Choose a non-existing directory name and try again. Exiting."
        exit 1
    fi
    read -p "Are you sure you want to restore all data from snapshot '${SNAPSHOT}' (y/N)? " yes_no
    if [[ ${yes_no,,} == "y" ]] || [[ ${yes_no,,} == "yes" ]]; then
        run_restic restore -t ${ROOT_PATH} ${SNAPSHOT}
    else
        echo "Exiting." && exit 1
    fi
}

enable() { # : Schedule backups by installing systemd timers
    if loginctl show-user ${USER} | grep "Linger=no"; then
	    echo "User account does not allow systemd Linger."
	    echo "To enable lingering, run as root: loginctl enable-linger $USER"
	    echo "Then try running this command again."
	    exit 1
    fi
    mkdir -p $(dirname $BACKUP_SERVICE)
    cat <<EOF > ${BACKUP_SERVICE}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE})
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath ${BASH_SOURCE}) now
ExecStartPost=$(realpath ${BASH_SOURCE}) forget
EOF
    cat <<EOF > ${BACKUP_TIMER}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE}) daily backups
[Timer]
OnCalendar=${BACKUP_FREQUENCY}
Persistent=true
[Install]
WantedBy=timers.target
EOF
    cat <<EOF > ${PRUNE_SERVICE}
[Unit]
Description=restic_backup prune $(realpath ${BASH_SOURCE})
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=$(realpath ${BASH_SOURCE}) prune
EOF
    cat <<EOF > ${PRUNE_TIMER}
[Unit]
Description=restic_backup $(realpath ${BASH_SOURCE}) monthly pruning
[Timer]
OnCalendar=${PRUNE_FREQUENCY}
Persistent=true
[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable --now ${BACKUP_NAME}.timer
    systemctl --user enable --now ${PRUNE_NAME}.timer
    systemctl --user status ${BACKUP_NAME} --no-pager
    systemctl --user status ${PRUNE_NAME} --no-pager
    echo "You can watch the logs with this command:"
    echo "   journalctl --user --unit ${BACKUP_NAME}"
}

disable() { # : Disable scheduled backups and remove systemd timers
    systemctl --user disable --now ${BACKUP_NAME}.timer
    systemctl --user disable --now ${PRUNE_NAME}.timer
    rm -f ${BACKUP_SERVICE} ${BACKUP_TIMER} ${PRUNE_SERVICE} ${PRUNE_TIMER}
    systemctl --user daemon-reload
}

status() { # : Show the last and next backup/prune times 
    echo "Restic backup paths: (${RESTIC_BACKUP_PATHS[@]})"
    journalctl --user --unit ${BACKUP_NAME} --since yesterday | \
        grep -E "(Restic backup finished successfully|Restic backup failed)" | \
        sort | awk '{ gsub("Restic backup finished successfully", "\033[1;33m&\033[0m");
                      gsub("Restic backup failed", "\033[1;31m&\033[0m"); print }'
    echo "Run the 'logs' subcommand for more information."
    (set -x; systemctl --user list-timers ${BACKUP_NAME} ${PRUNE_NAME} --no-pager)
    run_restic stats
}

logs() { # : Show recent service logs
    set -x
    journalctl --user --unit ${BACKUP_NAME} --since yesterday
}

prune_logs() { # : Show prune logs
    set -x
    journalctl --user --unit ${PRUNE_NAME}
}

help() { # : Show this help
    echo "## restic_backup.sh Help:"
    echo -e "# subcommand [ARG1] [ARG2]\t#  Help Description" | expand -t35
    for cmd in "${commands[@]}"; do
        annotation=$(grep -E "^${cmd}\(\) { # " ${BASH_SOURCE} | sed "s/^${cmd}() { # \(.*\)/\1/")
        args=$(echo ${annotation} | cut -d ":" -f1)
        description=$(echo ${annotation} | cut -d ":" -f2)
        echo -e "${cmd} ${args}\t# ${description} " | expand -t35
    done
}

main() {
    # Check script permissions (portable between GNU and BSD stat)
    if stat --version >/dev/null 2>&1; then
        # GNU stat
        SCRIPT_PERMS=$(stat -c "%a" "${BASH_SOURCE}")
    else
        # BSD / macOS stat
        SCRIPT_PERMS=$(stat -f "%Lp" "${BASH_SOURCE}")
    fi
    if [[ "${SCRIPT_PERMS}" != "700" ]]; then
        echo "Incorrect permissions on script (got ${SCRIPT_PERMS}, expected 700). Run: "
        echo "  chmod 0700 $(realpath "${BASH_SOURCE}")"
        exit 1
    fi
    if ! which restic >/dev/null; then
        echo "You need to install restic." && exit 1
    fi

    if test $# = 0; then
        help
    else
        CMD=$1; shift;
        if [[ " ${commands[*]} " =~ " ${CMD} " ]]; then
            ${CMD} $@
        else
            echo "Unknown command: ${CMD}" && exit 1
        fi
    fi
}

main $@



