#!/bin/bash

# Copyright (C) 2015 Pablo Piaggio.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.



# Usage info
show_help()
{
cat << EOF
Usage: ${0##*/} [-h | --help] [-n | --dry-run] source
Backup either home or private directory to external disk. Backup can be
full, differential or incremental.

    -h
    --help      display this help and exit
    source      allow values are 'home' and 'private'. Specifying home will
                backup home directory and exclude private one. Private will
                backup only private directory.
    -n
    --dry-run   print as if it were backing files, but it does not.

EOF
}

# Global variables. Relevant file, directories and switches.
BU_MOUNT_POINT="/media/pablo/vbackup"   # Mount point of the the backup disk.
DRY_RUN=""                              # Dry run switch to rsync.

# Boolean variable used to avoid using both home and private.
source_set="not_set"                    # Source not set yet.

#
# Process all arguments.
#
while [ "$#" -gt 0 ]; do
    case $1 in
        -h|-\?|--help)  # Call a "show_help" function to display a synopsis, then exit.
            show_help
            exit 0
            ;;

        -n|--dry-run)   # Set rsync's dry run option.
            DRY_RUN="--dry-run"
            ;;

        home|private)   # set source for backup.
            # Check that only one source has been selected.
            if [ "$source_set" == "set" ]; then
                echo "ERROR: can't backup home and private at same time."
                exit 1
            else
                source_set="set"
            fi

            # Set global variables that depend on source directory.
            if [ "$1" == "home" ]; then
                SOURCE="$HOME/"                         # directory to be backed up.
                DEST_BASE_DIR="$BU_MOUNT_POINT/Backups/rsync/home" # Direct parent directory of all backups.
                EXCLUDE_FILE="$HOME/bin/rsync.exclude.home"  # Exclude rules for rsync.
                TEMPLATE_NAME="Trusty_Vaughan"          # Template name for backup directories.
            else
                SOURCE="$HOME/dwhelper/"                # directory to be backed up.
                DEST_BASE_DIR="$BU_MOUNT_POINT/Backups/rsync/private" # Direct parent directory of all backups.
                EXCLUDE_FILE="$HOME/bin/rsync.exclude.private" # Exclude rules for rsync.
                TEMPLATE_NAME="dwhelper_Trusty_Vaughan" # Template name for backup directories.
            fi
            ;;

        -?*)    # Any other option is ignored.
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;

        *)      # Any other parameter will trigger an error.
            printf 'ERROR: Unknown parameter: %s\n' "$1" >&2
            exit 1
    esac

    shift
done

# Symlink that points to the latest full backup.
LINK_LATEST_FULL_BACKUP="$DEST_BASE_DIR/latest-full-backup" # symlink to latest full backup.

# Exit if source was not set.
if [ "$source_set" == "not_set" ]; then
    echo "ERROR: missing backup source."
    exit 1
fi

# Check if external disk is mounted.
if ! mountpoint -q "$BU_MOUNT_POINT" ; then
    echo "Backup drive not mounted. Stoping."
    exit 1
fi

# Print actual path directory that is going to be backed up.
echo "Backing up: $SOURCE"

# Get type of backup from user.
backup_type="undefined"
while [  "$backup_type" == "undefined" ]; do

    echo -n "Full, differential, or incremental (f/d/i)? "
    read answer

    case $answer in
        "f")    backup_type="Full"
                ;;
        "d")    backup_type="Differential"
                ;;
        "i")    backup_type="Incremental"
                ;;
        *)      backup_type="undefined"
                ;;
    esac
done

# Set backup destination: include date and hour.
current_date=$(date '+%F_%T')
destination="$DEST_BASE_DIR/${current_date}_${TEMPLATE_NAME}_$backup_type/"

# Check for exlcude rules.
if [ -f "$EXCLUDE_FILE" ]; then
    echo "Using exclude rules from: $EXCLUDE_FILE"
    EXCLUDE_RULE="--exclude-from="$EXCLUDE_FILE""
else
    echo "WARNING: exclude file '$EXCLUDE_FILE' does not exist."
    echo "WARNING: Not using exclude rules."
    EXCLUDE_RULE=""
fi

#
# Performe backup.
#

# Full backup.
if [ "$backup_type" == "Full" ]; then
    RSYNC_CMD="rsync -av "$DRY_RUN" "$EXCLUDE_RULE" "$SOURCE" "$destination""
    # Print command to be executed.
    echo Command to be executed:
    echo
    echo "$RSYNC_CMD"
    echo
    echo -n "Press Enter to start backup."
    read

    $RSYNC_CMD

    # Update symlink to the latest full backup.
    rm -rf "$LINK_LATEST_FULL_BACKUP"
    ln -s "$destination" "$LINK_LATEST_FULL_BACKUP"

# Differential backup.
elif [ "$backup_type" == "Differential" ]; then

    # Set full backup directory so it works as a reference.

    # Form a list of available full backups.
    full_dirs=()
    while read -r -d '' dir; do
        full_dirs+=("$dir")
    done < <(find "$DEST_BASE_DIR" -maxdepth 1 -type d -name '*Full' -print0)

    # Get (actual) directory pointed by symlink $LINK_LATEST_FULL_BACKUP
    link_lfb="$(readlink -f "$LINK_LATEST_FULL_BACKUP")"
    link_lfb_fn="${link_lfb##*/}"

    echo "$link_lfb_fn"

    # Show user list of available full backup, and let him/her select it directory
    # as reference for the incremental/differential.
    option_set="false"

    while [ "$option_set" == "false" ]; do
        echo
        echo "Full backups available:"
        for index in ${!full_dirs[*]}; do
            dir="${full_dirs[$index]}"
            filename=${dir##*/}

            # Add label to full backup pointed by by symlink $LINK_LATEST_FULL_BACKU
            if [ "$filename" == "$link_lfb_fn" ]; then
                echo -e "\t$index) $filename (latest)"
            else
                echo -e "\t$index) $filename"
            fi
        done
        echo -n "Select full backup directory? "
        read option

        if [[ $option != *[!0-9]* && $option -ge 0 && $option -lt ${#full_dirs[*]} ]]; then
            option_set="true"
        fi
    done

    RSYNC_CMD="rsync -av "$DRY_RUN" "$EXCLUDE_RULE" --compare-dest="${full_dirs[$option]}/" "$SOURCE" "$destination""

    # Print command to be executed.
    echo Command to be executed:
    echo
    echo "$RSYNC_CMD"
    echo
    echo -n "Press Enter to start backup."
    read

    $RSYNC_CMD

    # Prune empty directories.
    if [ "$DRY_RUN" == "" ]; then
        find "$destination" -depth -type d -empty -delete
    fi

# Incremental backup.
else
    # Set full backup directory so it works as a reference.

    # Form a list of available full backups.
    full_dirs=()
    while read -r -d '' dir; do
        full_dirs+=("$dir")
    done < <(find "$DEST_BASE_DIR" -maxdepth 1 -type d -name '*Full' -print0)

    # Get (actual) directory pointed by symlink $LINK_LATEST_FULL_BACKUP
    link_lfb="$(readlink -f "$LINK_LATEST_FULL_BACKUP")"
    link_lfb_fn="${link_lfb##*/}"

    # Show user list of available full backup, and let him/her select it directory
    # as reference for the incremental/differential.
    option_set="false"

    while [ "$option_set" == "false" ]; do
        echo
        echo "Full backups available:"
        for index in ${!full_dirs[*]}; do
            dir="${full_dirs[$index]}"
            filename=${dir##*/}

            # Add label to full backup pointed by by symlink $LINK_LATEST_FULL_BACKU
            if [ "$filename" == "$link_lfb_fn" ]; then
                echo -e "\t$index) $filename (latest)"
            else
                echo -e "\t$index) $filename"
            fi
        done
        echo -n "Select full backup directory? "
        read option

        if [[ $option != *[!0-9]* && $option -ge 0 && $option -lt ${#full_dirs[*]} ]]; then
            option_set="true"
        fi
    done

    COMPARE_RULES="--compare-dest=${full_dirs[$option]}/" 

    # Form a list of differential and incremental backups.
    full_dirs=()
    while read -r -d '' dir; do
        full_dirs+=("$dir")
    done < <(find "$DEST_BASE_DIR" -maxdepth 1 -type d \( -name '*Differential' -o -name '*Incremental' \) -print0)

    for index in ${!full_dirs[*]}; do
        COMPARE_RULES="$COMPARE_RULES --compare-dest=${full_dirs[$index]}/" 
    done

    echo "--------------------------"
    echo "$COMPARE_RULES"
    echo "--------------------------"

    # Now that the full backup is selected, construct the list of differentil and/or incremental backups.

    RSYNC_CMD="rsync -av "$DRY_RUN" "$EXCLUDE_RULE" "$COMPARE_RULES" "$SOURCE" "$destination""

    # Print command to be executed.
    echo Command to be executed:
    echo
    echo "$RSYNC_CMD"
    echo
    echo -n "Press Enter to start backup."
    read

    $RSYNC_CMD

    # Prune empty directories.
    if [ "$DRY_RUN" == "" ]; then
        find "$destination" -depth -type d -empty -delete
    fi
fi