#!/bin/bash

# ตัวแปรสำหรับตรวจสอบเวอร์ชัน
SCRIPT_NAME="Gensyn"
SCRIPT_VERSION="1.2.0"
VERSIONS_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/versions.txt"
SCRIPT_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/Gensyn.sh"

# สีสำหรับการแสดงผล
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
  cat << "EOF"
  
█████     ████    █████    █████    ██  ██ 
██  ██   ██  ██   ██  ██     ██     ███ ██ 
██  ██   ██████   █████      ██     ██ ███ 
██  ██   ██  ██   ██  ██     ██     ██  ██ 
█████    ██  ██   ██  ██   █████    ██  ██ 


EOF
}

check_script_version() {
    print_info "กำลังตรวจสอบว่าใช้สคริปต์เวอร์ชันล่าสุดหรือไม่..."
    remote_version=$(curl -s "$VERSIONS_FILE_URL" | grep "^${SCRIPT_NAME}=" | cut -d'=' -f2)
    if [ -z "$remote_version" ]; then
        print_warn "ไม่สามารถตรวจสอบเวอร์ชันจากรีโมตของ ${SCRIPT_NAME} ได้"
    elif [ "$remote_version" != "$SCRIPT_VERSION" ]; then
        print_warn "มีเวอร์ชันใหม่: $remote_version (ปัจจุบัน: $SCRIPT_VERSION)"
        print_info "แนะนำให้ดาวน์โหลดสคริปต์เวอร์ชันล่าสุดจากลิงก์นี้:\n$SCRIPT_FILE_URL"
    else
        print_ok "กำลังใช้สคริปต์เวอร์ชันล่าสุดแล้ว ($SCRIPT_VERSION)"
    fi
}

# เอาการตรวจสอบเวอร์ชันของ Python และ Node.js ออกแล้ว

system_update_and_install() {
    print_info "อัปเดตระบบและติดตั้งเครื่องมือสำหรับพัฒนาให้ครบ..."
    
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip curl screen git
    
    # ติดตั้ง yarn จาก repo อย่างเป็นทางการ
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt update && sudo apt install -y yarn
    
    # ติดตั้ง localtunnel
    sudo npm install -g localtunnel
    
    # ติดตั้ง Node.js 22.x
    sudo apt-get update
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # ตรวจสอบเวอร์ชัน
    node -v
    sudo npm install -g yarn
    yarn -v
    
    print_ok "ติดตั้ง dependencies ทั้งหมดเรียบร้อยแล้ว"
}

clone_repo() {
    print_info "กำลังโคลนรีโพ RL Swarm..."
    git clone https://github.com/gensyn-ai/rl-swarm.git "$HOME/rl-swarm" || { print_error "ไม่สามารถโคลนรีโพได้"; exit 1; }
    print_ok "โคลนรีโพเรียบร้อยแล้ว"
}

start_gensyn_screen() {
    # ตรวจสอบและรัน screen session ชื่อ gensyn สำหรับ node
    if screen -list | gre
