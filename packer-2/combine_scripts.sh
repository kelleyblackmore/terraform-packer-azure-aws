#!/bin/bash

# Create the directory scripts-spel--gen9 if it doesn't exist
mkdir -p scripts-spel--gen9

# Create combined.sh
COMBINED_SCRIPT="scripts-spel--gen9/combined.sh"

# Write header to combined.sh
cat << 'EOF' > "$COMBINED_SCRIPT"
scripts from spel 
amigen9-build.sh
base.sh
builder-prep-9.sh
cleanup.sh
dep.sh
free-root.sh
pivot-root.sh
retry.sh
zerodisk.sh


gen9
AWSutils.sh
DiskSetup.sh
DualMode-GRUBsetup.sh
MkChrootTree.sh
OSpackages.sh
PostBuild.sh
README.md
Umount.sh
XdistroSetup.sh
err_exit.bashlib
no_sel.bashlib
EOF

# Arrays of scripts
SCRIPTS_SPEL=(
    "amigen9-build.sh"
    "base.sh"
    "builder-prep-9.sh"
    "cleanup.sh"
    "dep.sh"
    "free-root.sh"
    "pivot-root.sh"
    "retry.sh"
    "zerodisk.sh"
)

SCRIPTS_GEN9=(
    "AWSutils.sh"
    "DiskSetup.sh"
    "DualMode-GRUBsetup.sh"
    "MkChrootTree.sh"
    "OSpackages.sh"
    "PostBuild.sh"
    "README.md"
    "Umount.sh"
    "XdistroSetup.sh"
    "err_exit.bashlib"
    "no_sel.bashlib"
)

# Process scripts from spel
for script in "${SCRIPTS_SPEL[@]}"; do
    script_path="ansible/rhel-lvm-role/scripts/$script"
    if [ -f "$script_path" ]; then
        echo -e "\n# --- Start of $script ---" >> "$COMBINED_SCRIPT"
        cat "$script_path" >> "$COMBINED_SCRIPT"
        echo -e "\n# --- End of $script ---" >> "$COMBINED_SCRIPT"
    else
        echo "Warning: $script_path not found"
    fi
done

# Process scripts from gen9
for script in "${SCRIPTS_GEN9[@]}"; do
    script_path="ansible/rhel-lvm-role/gen9/$script"
    if [ -f "$script_path" ]; then
        echo -e "\n# --- Start of $script ---" >> "$COMBINED_SCRIPT"
        cat "$script_path" >> "$COMBINED_SCRIPT"
        echo -e "\n# --- End of $script ---" >> "$COMBINED_SCRIPT"
    else
        echo "Warning: $script_path not found"
    fi
done