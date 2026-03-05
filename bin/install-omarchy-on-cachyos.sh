#!/bin/bash

OMARCHY_INSTALL=""

# Enable strict mode
set -o errexit -o errtrace -o nounset -o pipefail

# Print a python-like traceback: message + stack frames
bash_traceback() {
  local err=$?
  local msg=${1:-"Error"}
  echo "$msg (exit $err)" >&2

  local i=0
  local func file line
  # FUNCNAME[0] is this function; skip frame 0 and the trap frame
  for ((i=1; i<${#FUNCNAME[@]}; i++)); do
    func=${FUNCNAME[$i]}
    # BASH_SOURCE and BASH_LINENO align such that BASH_SOURCE[i] is the file in which FUNCNAME[i] was defined,
    # and BASH_LINENO[i-1] is the line number in that file where the call came from.
    file=${BASH_SOURCE[$i]}
    line=${BASH_LINENO[$i-1]:-?}
    printf '  File "%s", line %s, in %s\n' "$file" "$line" "${func:-main}" >&2
  done
}

# Trap ERR and print traceback; ERR trap inherits into functions and sourced scripts with errtrace
trap 'bash_traceback "Traceback (most recent call last):"' ERR

# Optionally show the failing command and line number (more like bash's default)
trap 'echo "Failed at line $LINENO: $BASH_COMMAND" >&2' EXIT


# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git before running this script."
    exit 1
fi

# Clone omarchyy from repo
echo "Clone Omarchy from repo..."
if ! git clone https://www.github.com/basecamp/omarchy ../omarchy; then
    echo "Error: Failed to clone Omarchy repo."
fi



echo "Successfully extracted omarchy archive."

# this is fucking stupid lol
if ! which yay; then
# Check if yay is installed
if ! command -v yay &> /dev/null; then
    echo "yay is not installed. Installing yay..."

    # Install dependencies for building yay
    sudo pacman -S --needed --noconfirm git base-devel

    # Clone and build yay
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay
    makepkg -si --noconfirm
    cd -

    # Clean up
    rm -rf /tmp/yay

    if ! command -v yay &> /dev/null; then
        echo "Error: Failed to install yay."
        exit 1
    fi

    echo "yay has been successfully installed."
else
    echo "yay is already installed."
fi
fi

# receive if missing
if ! pacman-key --list-keys | grep -qi F0134EE680CAC571; then
  sudo pacman-key --recv-keys F0134EE680CAC571
fi

# locally sign if not already signed
if ! pacman-key --list-sigs F0134EE680CAC571 | grep -q "sig.*$HOSTNAME\|sig.*$(whoami)"; then
  sudo pacman-key --lsign-key F0134EE680CAC571
fi

# Add omarchy repository to pacman.conf
echo -e "\n[omarchy]\nSigLevel = Optional TrustedOnly\nServer = https://pkgs.omarchy.org/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
sudo pacman -Syu

# Remove CachyOS SDDM config
if [ -f /etc/sddm.conf ]; then
    echo "Removing /etc/sddm.conf"
    sudo rm /etc/sddm.conf
fi

# Prompt user for username
echo ""
echo "Please enter your username:"
read -r OMARCHY_USER_NAME
export OMARCHY_USER_NAME

# Prompt user for email address
echo ""
echo "Please enter your email address:"
read -r OMARCHY_USER_EMAIL
export OMARCHY_USER_EMAIL

# Make adjustments to Omarchy install scripts to support CachyOS
echo ""
echo "Making adjustments to Omarchy install scripts to support CachyOS..."

# Navigate to Omarchy install scripts
cd ../omarchy

# Remove tldr installation to prevent conflict with tealdeer install.
sed -i '/tldr/d' install/omarchy-base.packages

# Update restart-needed for kernel updates to use cachyos instead of arch
sed -i "s/ | sed 's\/-arch\/\\\.arch\/'//" bin/omarchy-update-restart
sed -i "s/'{print \$2}'/'{print \$2 \"-\" \$1}' | sed 's\/-linux\/\/'/" bin/omarchy-update-restart
sed -i '/linux-cachyos/ ! s/pacman -Q linux/pacman -Q linux-cachyos/' bin/omarchy-update-restart

# Remove pacman.sh from preflight/all.sh to prevent conflict with cachyos packages
sed -i '/run_logged \$OMARCHY_INSTALL\/preflight\/pacman\.sh/d' install/preflight/all.sh

# Replace nvidia.sh with custom CachyOS 580xx Driver Logic
#cp ../bin/nvidia.sh install/config/hardware/nvidia.sh
#chmod +x install/config/hardware/nvidia.sh

echo "$OMARCHY_INSTALL"

rm -f "$OMARCHY_INSTALL/config/hardware/nvidia.sh"
rm "$OMARCHY_INSTALL/config/omarchy-ai-skill.sh"

# Remove plymouth.sh source line from install.sh
sed -i '/run_logged \$OMARCHY_INSTALL\/login\/plymouth\.sh/d' install/login/all.sh

# Remove limine-snapper.sh source line from install.sh
sed -i '/run_logged \$OMARCHY_INSTALL\/login\/limine-snapper\.sh/d' install/login/all.sh

# Remove alt-bootloaders.sh source line from install.sh
sed -i '/run_logged \$OMARCHY_INSTALL\/login\/alt-bootloaders\.sh/d' install/login/all.sh

# Remove pacman.sh from post-install/all.sh to prevent conflict with cachyos packages
sed -i '/run_logged \$OMARCHY_INSTALL\/post-install\/pacman\.sh/d' install/post-install/all.sh

# Update mise activation to support both bash and fish
sed -i 's/omarchy-cmd-present mise && eval "\$(mise activate bash)"/if [ "\$SHELL" = "\/bin\/bash" ] \&\& command -v mise \&> \/dev\/null; then\n  eval "\$(mise activate bash)"\nelif [ "\$SHELL" = "\/bin\/fish" ] \&\& command -v mise \&> \/dev\/null; then\n  mise activate fish | source\nfi/' config/uwsm/env

# Copy omarchy installation files to ~/.local/share/omarchy
mkdir -p ~/.local/share/omarchy
cp -r . ~/.local/share/omarchy
cd ~/.local/share/omarchy

# Pause and prompt for acknowledgment to begin installation
echo ""
echo "The following adjustments have been completed."
echo " 1. Added Omarchy repo to pacman.conf"
echo " 2. Removed tldr from packages.sh to avoid conflict with tealdeer on CachyOS."
echo " 3. Disabled further Omarchy changes to pacman.conf, preserving CachyOS settings."
echo " 4. Replaced nvidia.sh with custom CachyOS 580xx Driver Logic."
echo " 5. Removed plymouth.sh from install.sh to avoid conflict with CachyOS login display manager installation."
echo " 6. Removed limine-snapper.sh from install.sh to avoid conflict with CachyOS boot loader installation."
echo " 7. Removed alt-bootloaders.sh from install.sh to avoid conflict with CachyOS boot loader installation."
echo " 8. Removed /etc/sddm.conf to avoid conflict with Omarchy UWSM session autologin."
echo ""
echo "IMPORTANT: If you installed CachyOS without a deskop environment, you will not have a display manager installed." 
echo "If this is the case, you will need to run the following command after this installation script is complete:"
echo " 1.) ~/.local/share/omarchy/install/login/plymouth.sh"  
echo ""
echo "The aboves script will modify your boot to start Omarchy's Hyprland desktop automatically." 
echo ""
echo "Press Enter to begin the installation of Omarchy..."
read -r

# Run the modified install.sh script 
chmod +x install.sh
./install.sh
