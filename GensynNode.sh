#!/bin/bash

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No color (reset)

# Logo
channel_logo() {
  echo -e "${GREEN}"
  cat << "EOF"
█████     ████    █████    █████    ██  ██ 
██  ██   ██  ██   ██  ██     ██     ███ ██ 
██  ██   ██████   █████      ██     ██ ███ 
██  ██   ██  ██   ██  ██     ██     ██  ██ 
█████    ██  ██   ██  ██   █████    ██  ██ 


EOF
  echo -e "${NC}"
}

# Install node
download_node() {
  echo "Starting node installation..."
  cd "$HOME" || exit 1

  # Install required packages
  sudo apt update -y && sudo apt install -y lsof

  # Check ports
  local ports=(4040 3000 42763)
  for port in "${ports[@]}"; do
    if lsof -i :"$port" >/dev/null 2>&1; then
      echo "Error: port $port is in use."
      echo "Installation is not possible."
      exit 1
    fi
  done
  echo "All ports are free! Starting installation..."

  # Remove old node if it exists
  if [ -d "$HOME/rl-swarm" ]; then
    local pid
    pid=$(netstat -tulnp | grep :3000 | awk '{print $7}' | cut -d'/' -f1)
    [ -n "$pid" ] && sudo kill "$pid"
    sudo rm -rf "$HOME/rl-swarm"
  fi

  # Configure swap
  local target_swap_gb=32
  local current_swap_kb
  current_swap_kb=$(free -k | awk '/Swap:/ {print $2}')
  local current_swap_gb=$((current_swap_kb / 1024 / 1024))
  echo "Current swap size: ${current_swap_gb}GB"
  if [ "$current_swap_gb" -lt "$target_swap_gb" ]; then
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    local swapfile=/swapfile
    fallocate -l "${target_swap_gb}G" "$swapfile"
    chmod 600 "$swapfile"
    mkswap "$swapfile"
    swapon "$swapfile"
    echo "$swapfile none swap sw 0 0" >> /etc/fstab
    echo "vm.swappiness = 10" >> /etc/sysctl.conf
    sysctl -p
    echo "Swap set to ${target_swap_gb}GB"
  fi

  # Install dependencies
  sudo apt update -y && sudo apt upgrade -y
  sudo apt install -y git curl wget build-essential python3 python3-venv python3-pip screen yarn net-tools

  # Install Node.js and Yarn
  curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
  echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
  curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
  sudo apt install -y nodejs
  sudo apt update
  curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash

  # Clone and setup repo
  git clone https://github.com/zunxbt/rl-swarm.git
  cd rl-swarm || exit 1
  python3 -m venv .venv
  source .venv/bin/activate
  pip install hivemind==1.1.11
  pip install --upgrade pip

  # PyTorch setup
  read -p "Does your server have only CPU (no GPU)? (Y/N, if you are not sure - Y): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Configuring PyTorch for CPU..."
    export PYTORCH_ENABLE_MPS_FALLBACK=1
    export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
    sed -i 's/torch\.device("mps" if torch\.backends\.mps\.is_available() else "cpu")/torch.device("cpu")/g' hivemind_exp/trainer/hivemind_grpo_trainer.py
    echo "Configuration completed."
  else
    echo "Keeping default settings."
  fi

  # Clear old screen session
  if screen -list | grep -q "gensyn"; then
    screen -ls | grep gensyn | awk '{print $1}' | cut -d'.' -f1 | xargs kill
  fi

  echo "Follow further instructions in the guide."
}

# Launch node
launch_node() {
  # Create directory if it does not exist
  mkdir -p "$HOME/rl-swarm"

  # Create or clear log file
  touch "$HOME/rl-swarm/gensyn.log"
  : > "$HOME/rl-swarm/gensyn.log"

  cd "$HOME/rl-swarm" || exit 1
  source .venv/bin/activate

  # Determine Python version in virtual environment
  python_version=$(python --version 2>&1 | awk '{print $2}' | cut -d'.' -f1,2)
  site_packages_path="$HOME/rl-swarm/.venv/lib/python${python_version}/site-packages/transformers/trainer.py"

  # Check that trainer.py exists
  if [ -f "$site_packages_path" ]; then
    echo "Found trainer.py for Python ${python_version}."
    echo "Replacing line..."
    sed -i 's/torch\.cpu\.amp\.autocast(/torch.amp.autocast('"'"'cpu'"'"', /g' "$site_packages_path"
    if [ $? -eq 0 ]; then
      echo "Line replacement successfully completed in $site_packages_path"
    else
      echo "Error while replacing line in $site_packages_path"
      exit 1
    fi
  else
    echo "File $site_packages_path not found."
    echo "Skipping line replacement."
  fi

  # Clear existing screen session, if any
  if screen -list | grep -q "gensyn"; then
    screen -ls | grep gensyn | awk '{print $1}' | cut -d'.' -f1 | xargs kill
  fi

  # Launch node in a new screen session
  screen -S gensyn -d -m bash -c "trap '' INT; bash run_rl_swarm.sh 2>&1 | tee $HOME/rl-swarm/gensyn.log"
  echo "Node started in screen 'gensyn'."
}

# View logs
watch_logs() {
  echo "Viewing logs (Ctrl+C to return to menu)..."
  trap 'echo -e "\nReturning to menu..."; return' SIGINT
  tail -n 100 -f "$HOME/rl-swarm/gensyn.log"
}

# Attach to screen
go_to_screen() {
  echo "Detach from screen via Ctrl+A + D"
  sleep 2
  screen -r gensyn
}

# Start local server via SSH tunnel and localtunnel
open_local_server() {
  npm install -g localtunnel
  local server_ip
  server_ip=$(curl -s https://api.ipify.org || curl -s https://ifconfig.co/ip || dig +short myip.opendns.com @resolver1.opendns.com)
  read -p "Your IP: $server_ip. Is this the correct IP? (y/n): " confirm
  if [[ "$confirm" != "y" ]]; then
    read -p "Enter your IP address: " server_ip
  fi
  echo "Using IP: $server_ip"
  ssh -L 3000:localhost:3000 "root@${server_ip}" &
  lt --port 3000
}

# Show user data
userdata() {
  cat "$HOME/rl-swarm/modal-login/temp-data/userData.json" 2>/dev/null || echo "File userData.json not found."
}

# Show user API key
userapikey() {
  cat "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" 2>/dev/null || echo "File userApiKey.json not found."
}

# Stop node
stop_node() {
  if screen -list | grep -q "gensyn"; then
    screen -ls | grep gensyn | awk '{print $1}' | cut -d'.' -f1 | xargs kill
  fi
  local pid
  pid=$(netstat -tulnp | grep :3000 | awk '{print $7}' | cut -d'/' -f1)
  [ -n "$pid" ] && sudo kill "$pid"
  echo "Node stopped."
}

# Delete node
delete_node() {
  stop_node
  sudo rm -rf "$HOME/rl-swarm"
  echo "Node deleted."
}

# Fix FutureWarning: torch.cpu.amp.autocast
fix_future_warning() {
  echo -e "${BLUE}Fixing FutureWarning: torch.cpu.amp.autocast...${NC}"

  # Stop node
  echo -e "${YELLOW}Stopping node...${NC}"
  stop_node

  # Go to rl-swarm directory
  cd "$HOME/rl-swarm" || { echo -e "${RED}Failed to enter rl-swarm directory. Make sure the node is installed.${NC}"; return; }

  # Activate virtual environment
  source .venv/bin/activate

  # Determine Python version
  python_version=$(python --version 2>&1 | awk '{print $2}' | cut -d'.' -f1,2)
  site_packages_path="$HOME/rl-swarm/.venv/lib/python${python_version}/site-packages/transformers/trainer.py"

  # Check trainer.py
  if [ -f "$site_packages_path" ]; then
    echo -e "${YELLOW}Found trainer.py for Python ${python_version}. Replacing line...${NC}"
    sed -i 's/torch\.cpu\.amp\.autocast(/torch.amp.autocast('"'"'cpu'"'"', /g' "$site_packages_path"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Line replacement successfully completed in $site_packages_path${NC}"
    else
      echo -e "${RED}Error while replacing line in $site_packages_path${NC}"
      return
    fi
  else
    echo -e "${RED}File $site_packages_path not found. Make sure the transformers package is installed in the virtual environment.${NC}"
    echo -e "${YELLOW}Try starting the node to install dependencies, then run this again.${NC}"
    return
  fi

  # Restart node
  echo -e "${YELLOW}Restarting node...${NC}"
  launch_node
}

# Fix SyntaxError: duplicate argument 'bootstrap_timeout'
fix_bootstrap_timeout() {
  echo -e "${BLUE}Fixing SyntaxError: duplicate argument 'bootstrap_timeout'...${NC}"

  # Stop node
  echo -e "${YELLOW}Stopping node...${NC}"
  stop_node

  # Go to rl-swarm directory
  cd "$HOME/rl-swarm" || { echo -e "${RED}Failed to enter rl-swarm directory. Make sure the node is installed.${NC}"; return; }

  # Activate virtual environment
  source .venv/bin/activate

  # Install hivemind==1.1.11
  echo -e "${YELLOW}Installing hivemind==1.1.11...${NC}"
  pip install hivemind==1.1.11
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Installed hivemind==1.1.11 successfully${NC}"
  else
    echo -e "${RED}Error installing hivemind==1.1.11${NC}"
    return
  fi

  # Clear existing screen session, if any
  if screen -list | grep -q "gensyn"; then
    screen -ls | grep gensyn | awk '{print $1}' | cut -d'.' -f1 | xargs kill
  fi

  # Create or clear log file
  touch "$HOME/rl-swarm/gensyn.log"
  : > "$HOME/rl-swarm/gensyn.log"

  # Restart node in screen with explicit command
  echo -e "${YELLOW}Restarting node...${NC}"
  screen -S gensyn -d -m bash -c "cd $HOME/rl-swarm && python3 -m venv .venv && source .venv/bin/activate && ./run_rl_swarm.sh 2>&1 | tee $HOME/rl-swarm/gensyn.log"
  echo -e "${GREEN}Node started in screen 'gensyn'${NC}"
}

# Troubleshooting menu
troubleshoot_menu() {
  while true; do
    echo -e "${BLUE}Troubleshooting menu:${NC}"
    echo -e "${CYAN}1. Fix FutureWarning: torch.cpu.amp.autocast(args...) is deprecated${NC}"
    echo -e "${CYAN}2. Fix SyntaxError: duplicate argument 'bootstrap_timeout' in function definition${NC}"
    echo -e "${CYAN}3. Return to main menu${NC}"
    echo -e " "
    read -p "Enter number: " choice
    case "$choice" in
      1) fix_future_warning ;;
      2) fix_bootstrap_timeout ;;
      3) return ;;
      *) echo -e "Invalid choice.
Enter a number from 1 to 3." ;;
    esac
  done
}

# Update node
update_node() {
  echo -e "${BLUE}Starting node update...${NC}"

  # Create directory if it does not exist
  mkdir -p "$HOME/rl-swarm"

  # Create or clear log file
  touch "$HOME/rl-swarm/gensyn.log"
  : > "$HOME/rl-swarm/gensyn.log"

  # Stop existing screen session
  pkill -f "SCREEN.*gensyn"

  # Save existing files swarm.pem, userData.json and userApiKey.json
  if [ -f "$HOME/rl-swarm/swarm.pem" ]; then
    cp "$HOME/rl-swarm/swarm.pem" "$HOME/"
    cp "$HOME/rl-swarm/modal-login/temp-data/userData.json" "$HOME/" 2>/dev/null
    cp "$HOME/rl-swarm/modal-login/temp-data/userApiKey.json" "$HOME/" 2>/dev/null
  fi

  # Remove old directory and clone new one
  rm -rf "$HOME/rl-swarm"
  cd "$HOME" && git clone https://github.com/zunxbt/rl-swarm.git > /dev/null 2>&1
  cd "$HOME/rl-swarm" || { echo -e "${RED}Failed to enter rl-swarm directory. Exiting.${NC}"; exit 1; }

  # Restore saved files
  if [ -f "$HOME/swarm.pem" ]; then
    mv "$HOME/swarm.pem" "$HOME/rl-swarm/"
    mv "$HOME/userData.json" "$HOME/rl-swarm/modal-login/temp-data/" 2>/dev/null
    mv "$HOME/userApiKey.json" "$HOME/rl-swarm/modal-login/temp-data/" 2>/dev/null
  fi

  # Setup virtual environment
  if [ -n "$VIRTUAL_ENV" ]; then
    deactivate
  fi
  python3 -m venv .venv
  source .venv/bin/activate

  # Determine Python version
  python_version=$(python --version 2>&1 | awk '{print $2}' | cut -d'.' -f1,2)
  site_packages_path="$HOME/rl-swarm/.venv/lib/python${python_version}/site-packages/transformers/trainer.py"

  # Check trainer.py
  if [ -f "$site_packages_path" ]; then
    echo -e "${YELLOW}Found trainer.py for Python ${python_version}. Replacing line...${NC}"
    sed -i 's/torch\.cpu\.amp\.autocast(/torch.amp.autocast('"'"'cpu'"'"', /g' "$site_packages_path"
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}Line replacement successfully completed in $site_packages_path${NC}"
    else
      echo -e "${RED}Error while replacing line in $site_packages_path${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}File $site_packages_path not found. Skipping line replacement.${NC}"
  fi

  # Launch node in screen
  screen -S gensyn -d -m bash -c "trap '' INT; bash run_rl_swarm.sh 2>&1 | tee $HOME/rl-swarm/gensyn.log"
  echo -e "${GREEN}Update completed. Node started in screen 'gensyn'. Logs are available at $HOME/rl-swarm/gensyn.log${NC}"
}

# Main menu
main_menu() {
  while true; do
    channel_logo
    sleep 2
    echo -e "${YELLOW}Choose an action:${NC}"
    echo -e "${CYAN}1. Install node (v. 0.4.2)${NC}"
    echo -e "${CYAN}2. Launch node${NC}"
    echo -e "${CYAN}3. View logs${NC}"
    echo -e "${CYAN}4. Attach to node screen${NC}"
    echo -e "${CYAN}5. Start local server${NC}"
    echo -e "${CYAN}6. Show user data${NC}"
    echo -e "${CYAN}7. Show user API key${NC}"
    echo -e "${CYAN}8. Stop node${NC}"
    echo -e "${CYAN}9. Delete node${NC}"
    echo -e "${CYAN}10. Update node (v. 0.4.2)${NC}"
    echo -e "${CYAN}11. Exit script${NC}"
    echo -e "${CYAN}12. Troubleshooting${NC}"
    echo -e " "
    read -p "Enter number: " choice
    case "$choice" in
      1) download_node ;;
      2) launch_node ;;
      3) watch_logs ;;
      4) go_to_screen ;;
      5) open_local_server ;;
      6) userdata ;;
      7) userapikey ;;
      8) stop_node ;;
      9) delete_node ;;
      10) update_node ;;
      11) exit 0 ;;
      12) troubleshoot_menu ;;
      *) echo "Invalid choice. Enter a number from 1 to 12." ;;
    esac
  done
}

# Run script
main_menu
