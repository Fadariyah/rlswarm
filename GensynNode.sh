#!/bin/bash

# Variables for version check
SCRIPT_NAME="Gensyn"
SCRIPT_VERSION="1.2.0"
VERSIONS_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/versions.txt"
SCRIPT_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/Gensyn.sh"

# Colors for output
clrGreen='\033[0;32m'
clrCyan='\033[0;36m'
clrRed='\033[0;31m'
clrYellow='\033[1;33m'
clrReset='\033[0m'
clrBold='\033[1m'

print_ok()    { echo -e "${clrGreen}[OK] $1${clrReset}"; }
print_info()  { echo -e "${clrCyan}[INFO] $1${clrReset}"; }
print_warn()  { echo -e "${clrYellow}[WARN] $1${clrReset}"; }
print_error() { echo -e "${clrRed}[ERROR] $1${clrReset}"; }

display_logo() {
    cat <<'EOF'
█████     ████    █████    █████    ██  ██ 
██  ██   ██  ██   ██  ██     ██     ███ ██ 
██  ██   ██████   █████      ██     ██ ███ 
██  ██   ██  ██   ██  ██     ██     ██  ██ 
█████    ██  ██   ██  ██   █████    ██  ██ 
EOF
}

check_script_version() {
    print_info "Checking script version..."
    remote_version=$(curl -s "$VERSIONS_FILE_URL" | grep "^${SCRIPT_NAME}=" | cut -d'=' -f2)
    if [ -z "$remote_version" ]; then
        print_warn "Could not determine remote version for ${SCRIPT_NAME}"
    elif [ "$remote_version" != "$SCRIPT_VERSION" ]; then
        print_warn "New version available: $remote_version (current: $SCRIPT_VERSION)"
        print_info "It is recommended to download the updated script from:\n$SCRIPT_FILE_URL"
    else
        print_ok "You are using the latest script version ($SCRIPT_VERSION)"
    fi
}

# Removed Python and Node.js version checks

system_update_and_install() {
    print_info "Updating system and installing required development tools..."
    
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip curl screen git
    
    # Install yarn from the official repository
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt update && sudo apt install -y yarn
    
    # Install localtunnel
    sudo npm install -g localtunnel
    
    # Install Node.js 22.x
    sudo apt-get update
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Check versions
    node -v
    sudo npm install -g yarn
    yarn -v
    
    print_ok "All dependencies installed"
}

clone_repo() {
    print_info "Cloning RL Swarm repository..."
    git clone https://github.com/gensyn-ai/rl-swarm.git "$HOME/rl-swarm" || { print_error "Failed to clone repository"; exit 1; }
    print_ok "Repository cloned"
}

start_gensyn_screen() {
    # Check and start screen session 'gensyn' for the node
    if screen -list | grep -q "gensyn"; then
        print_warn "Screen session 'gensyn' already exists! Use 'screen -r gensyn' to attach."
        return
    fi
    print_info "Starting RL Swarm node in screen session 'gensyn'..."
    screen -dmS gensyn bash -c '
        cd ~/rl-swarm || exit 1
        python3 -m venv .venv
        source .venv/bin/activate
        pip install --force-reinstall trl==0.19.1
        ./run_rl_swarm.sh
        while true; do
            sleep 60
        done
    '
    print_ok "Node started in screen session 'gensyn'. Use 'screen -r gensyn' to attach."
}

update_node() {
    print_info "Updating RL Swarm..."
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || exit 1
        git switch main
        git reset --hard
        git clean -fd
        git pull origin main
        git pull
        print_ok "Repository updated."
    else
        print_error "Directory rl-swarm not found"
    fi
}

check_current_node_version() {
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || { print_error "Failed to change directory to rl-swarm"; return; }
        current_version=$(git describe --tags 2>/dev/null)
        if [ $? -eq 0 ]; then
            print_ok "Current node version: $current_version"
        else
            print_warn "Could not determine current version (possibly no tags)"
        fi
    else
        print_error "Directory rl-swarm not found"
    fi
}

delete_rlswarm() {
    print_warn "Saving private key swarm.pem (if exists)..."
    if [ -f "$HOME/rl-swarm/swarm.pem" ]; then
        cp "$HOME/rl-swarm/swarm.pem" "$HOME/swarm.pem.backup"
        print_ok "swarm.pem copied to $HOME/swarm.pem.backup"
    fi
    print_info "Removing rl-swarm..."
    rm -rf "$HOME/rl-swarm"
    print_ok "Directory rl-swarm removed. Private key saved as ~/swarm.pem.backup"
}

restore_swarm_pem() {
    if [ -f "$HOME/swarm.pem.backup" ]; then
        cp "$HOME/swarm.pem.backup" "$HOME/rl-swarm/swarm.pem"
        print_ok "swarm.pem restored from $HOME/swarm.pem.backup"
    else
        print_warn "swarm.pem backup not found."
    fi
}

setup_cloudflared_screen() {
    print_info "Installing and starting Cloudflared HTTPS tunnel to port 3000..."

    # Basic packages
    sudo apt-get update -y
    sudo apt-get install -y ufw screen wget ca-certificates

    # UFW rules
    sudo ufw allow 22/tcp
    sudo ufw allow 3000/tcp
    sudo ufw --force enable

    # Detect architecture for the correct .deb
    local ARCH
    ARCH="$(dpkg --print-architecture 2>/dev/null || echo unknown)"

    local DEB_URL=""
    case "$ARCH" in
        amd64)
            DEB_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
            ;;
        arm64)
            DEB_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
            ;;
        *)
            print_error "Unsupported architecture: ${ARCH}. Only amd64 and arm64 are supported."
            return 1
            ;;
    esac

    # Install cloudflared if not present
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_info "cloudflared not found. Downloading package for ${ARCH}..."
        local TMP_DEB="/tmp/cloudflared-${ARCH}.deb"
        if ! wget -q -O "${TMP_DEB}" "${DEB_URL}"; then
            print_error "Failed to download cloudflared for ${ARCH}."
            return 1
        fi

        print_info "Installing cloudflared..."
        if ! sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1; then
            # Pull dependencies if needed
            sudo apt-get -f install -y
            # Retry install
            sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1 || {
                print_error "Failed to install cloudflared for ${ARCH}."
                rm -f "${TMP_DEB}"
                return 1
            }
        fi
        rm -f "${TMP_DEB}"
    fi

    # Final check
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_error "cloudflared not found after installation. Aborting."
        return 1
    fi

    # Do not create another screen if exists
    if screen -list | grep -q "[.]cftunnel"; then
        print_warn "Screen session 'cftunnel' already exists! Use 'screen -r cftunnel' to attach."
        return 0
    fi

    # Log directory
    sudo mkdir -p /var/log
    local LOG_FILE="/var/log/cloudflared-screen.log"

    print_info "Starting Cloudflared tunnel in screen session 'cftunnel'..."
    screen -dmS cftunnel bash -lc "cloudflared tunnel --no-autoupdate --url http://localhost:3000 2>&1 | tee -a ${LOG_FILE}"

    sleep 1
    if pgrep -af cloudflared >/dev/null 2>&1; then
        print_ok "Cloudflared tunnel started in screen 'cftunnel'. See URL in: 'screen -r cftunnel'. Logs: ${LOG_FILE}"
        return 0
    else
        print_error "Failed to start cloudflared in screen. Check logs: ${LOG_FILE} and 'screen -r cftunnel'."
        return 1
    fi
}

swap_menu() {
    while true; do
        clear
        display_logo
        echo -e "\n${clrBold}Swap file management:${clrReset}"
        echo "1) Show active swap file"
        echo "2) Disable swap file"
        echo "3) Create swap file"
        echo "4) Back"
        read -rp "Enter a number: " swap_choice
        case $swap_choice in
            1)
                print_info "Active swap file:"
                swapon --show
                ;;
            2)
                print_info "Stopping swap file..."
                if [ -f /swapfile ]; then
                    sudo swapoff /swapfile
                    print_ok "Swap file disabled"
                else
                    print_warn "Swap file /swapfile not found"
                fi
                ;;
            3)
                read -rp "Enter swap file size in GB: " swap_size
                if [[ $swap_size =~ ^[0-9]+$ ]] && [ "$swap_size" -gt 0 ]; then
                    print_info "Creating swap file of size ${swap_size}G..."
                    sudo fallocate -l ${swap_size}G /swapfile
                    sudo mkswap /swapfile
                    sudo swapon /swapfile
                    print_ok "Swap file of size ${swap_size}G created and activated"
                else
                    print_error "Invalid size. Enter a positive integer."
                fi
                ;;
            4)
                return
                ;;
            *)
                print_error "Invalid choice, please try again."
                ;;
        esac
        echo -e "\nPress Enter to return to the menu..."
        read -r
    done
}

main_menu() {
    while true; do
        clear
        display_logo
        check_script_version
        echo -e "\n${clrBold}Select an action:${clrReset}"
        echo "1) Install dependencies"
        echo "2) Clone RL Swarm"
        echo "3) Run Gensyn node in screen (name: gensyn)"
        echo "4) Update RL Swarm"
        echo "5) Check current node version"
        echo "6) Remove RL Swarm (keep private key)"
        echo "7) Restore swarm.pem from backup"
        echo "8) Start HTTPS tunnel Cloudflared (screen: cftunnel)"
        echo "9) Swap file management"
        echo "10) Exit"
        read -rp "Enter a number: " choice
        case $choice in
            1) system_update_and_install ;;
            2) clone_repo ;;
            3) start_gensyn_screen ;;
            4) update_node ;;
            5) check_current_node_version ;;
            6) delete_rlswarm ;;
            7) restore_swarm_pem ;;
            8) setup_cloudflared_screen ;;
            9) swap_menu ;;
            10) echo -e "${clrGreen}Goodbye!${clrReset}"; exit 0 ;;
            *) print_error "Invalid choice, please try again." ;;
        esac
        echo -e "\nPress Enter to return to the menu..."
        read -r
    done
}

# Start main menu
main_menu
