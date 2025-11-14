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
    cat <<'EOF'

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
    if screen -list | grep -q "gensyn"; then
        print_warn "มี screen session 'gensyn' อยู่แล้ว! ใช้คำสั่ง 'screen -r gensyn' เพื่อเข้าใช้งาน"
        return
    fi
    print_info "กำลังรัน RL Swarm node ใน screen session 'gensyn'..."
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
    print_ok "รัน node ใน screen session 'gensyn' แล้ว พิมพ์ 'screen -r gensyn' เพื่อเข้าไปดู"
}

update_node() {
    print_info "กำลังอัปเดต RL Swarm..."
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || exit 1
        git switch main
        git reset --hard
        git clean -fd
        git pull origin main
        git pull
        print_ok "อัปเดตรีโพเรียบร้อยแล้ว"
    else
        print_error "ไม่พบโฟลเดอร์ rl-swarm"
    fi
}

check_current_node_version() {
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || { print_error "ไม่สามารถเข้าโฟลเดอร์ rl-swarm ได้"; return; }
        current_version=$(git describe --tags 2>/dev/null)
        if [ $? -eq 0 ]; then
            print_ok "เวอร์ชันปัจจุบันของ node: $current_version"
        else
            print_warn "ไม่สามารถดูเวอร์ชันปัจจุบันได้ (อาจยังไม่มี tag)"
        fi
    else
        print_error "ไม่พบโฟลเดอร์ rl-swarm"
    fi
}

delete_rlswarm() {
    print_warn "กำลังสำรองไฟล์คีย์ส่วนตัว swarm.pem (ถ้ามี)..."
    if [ -f "$HOME/rl-swarm/swarm.pem" ]; then
        cp "$HOME/rl-swarm/swarm.pem" "$HOME/swarm.pem.backup"
        print_ok "คัดลอก swarm.pem ไปไว้ที่ $HOME/swarm.pem.backup แล้ว"
    fi
    print_info "กำลังลบโฟลเดอร์ rl-swarm..."
    rm -rf "$HOME/rl-swarm"
    print_ok "ลบโฟลเดอร์ rl-swarm เรียบร้อยแล้ว คีย์ส่วนตัวถูกสำรองเป็น ~/swarm.pem.backup"
}

restore_swarm_pem() {
    if [ -f "$HOME/swarm.pem.backup" ]; then
        cp "$HOME/swarm.pem.backup" "$HOME/rl-swarm/swarm.pem"
        print_ok "กู้คืน swarm.pem จาก $HOME/swarm.pem.backup แล้ว"
    else
        print_warn "ไม่พบไฟล์สำรอง swarm.pem"
    fi
}

setup_cloudflared_screen() {
    print_info "ติดตั้งและรัน Cloudflared สำหรับ HTTPS tunnel ที่พอร์ต 3000..."

    # แพ็กเกจพื้นฐาน
    sudo apt-get update -y
    sudo apt-get install -y ufw screen wget ca-certificates

    # ตั้งค่า UFW
    sudo ufw allow 22/tcp
    sudo ufw allow 3000/tcp
    sudo ufw --force enable

    # ตรวจสอบสถาปัตยกรรมเพื่อลง .deb ให้ถูก
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
            print_err "สถาปัตยกรรมไม่รองรับ: ${ARCH} รองรับเฉพาะ amd64 และ arm64."
            return 1
            ;;
    esac

    # ติดตั้ง cloudflared ถ้ายังไม่มี
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_info "ไม่พบ cloudflared กำลังดาวน์โหลดแพ็กเกจสำหรับ ${ARCH}..."
        local TMP_DEB="/tmp/cloudflared-${ARCH}.deb"
        if ! wget -q -O "${TMP_DEB}" "${DEB_URL}"; then
            print_err "ไม่สามารถดาวน์โหลด cloudflared สำหรับ ${ARCH} ได้"
            return 1
        fi

        print_info "กำลังติดตั้ง cloudflared..."
        if ! sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1; then
            # ติดตั้ง dependencies เพิ่มถ้าจำเป็น
            sudo apt-get -f install -y
            # ลองติดตั้งซ้ำ
            sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1 || {
                print_err "ติดตั้ง cloudflared สำหรับ ${ARCH} ไม่สำเร็จ"
                rm -f "${TMP_DEB}"
                return 1
            }
        fi
        rm -f "${TMP_DEB}"
    fi

    # ตรวจสอบว่ามี binary จริงหรือไม่
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_err "ไม่พบ cloudflared หลังติดตั้ง หยุดทำงาน"
        return 1
    fi

    # ไม่สร้าง screen ซ้ำถ้ามีอยู่แล้ว
    if screen -list | grep -q "[.]cftunnel"; then
        print_warn "มี screen session 'cftunnel' อยู่แล้ว! ใช้ 'screen -r cftunnel' เพื่อเข้าใช้งาน"
        return 0
    fi

    # โฟลเดอร์สำหรับ log
    sudo mkdir -p /var/log
    local LOG_FILE="/var/log/cloudflared-screen.log"

    print_info "กำลังรัน Cloudflared tunnel ใน screen session 'cftunnel'..."
    # -dmS: detached, ตั้งชื่อ session; bash -lc เพื่อให้ PATH ถูกต้อง
    screen -dmS cftunnel bash -lc "cloudflared tunnel --no-autoupdate --url http://localhost:3000 2>&1 | tee -a ${LOG_FILE}"

    # หน่วงเวลานิดหน่อยแล้วเช็ก process
    sleep 1
    if pgrep -af cloudflared >/dev/null 2>&1; then
        print_ok "Cloudflared tunnel รันอยู่ใน screen 'cftunnel' แล้ว ดูลิงก์ได้โดยใช้ 'screen -r cftunnel' log อยู่ที่: ${LOG_FILE}"
        return 0
    else
        print_err "ไม่สามารถรัน cloudflared ใน screen ได้ ตรวจสอบ log: ${LOG_FILE} และ 'screen -r cftunnel'"
        return 1
    fi
}

swap_menu() {
    while true; do
        clear
        display_logo
        echo -e "\n${clrBold}จัดการไฟล์สว็อป (swap file):${clrReset}"
        echo "1) แสดงไฟล์สว็อปที่ใช้งานอยู่ตอนนี้"
        echo "2) ปิดการใช้งานไฟล์สว็อป"
        echo "3) สร้างไฟล์สว็อปใหม่"
        echo "4) กลับไปเมนูก่อนหน้า"
        read -rp "กรอกหมายเลข: " swap_choice
        case $swap_choice in
            1)
                print_info "ไฟล์สว็อปที่กำลังใช้งาน:"
                swapon --show
                ;;
            2)
                print_info "กำลังปิดการใช้งานไฟล์สว็อป..."
                if [ -f /swapfile ]; then
                    sudo swapoff /swapfile
                    print_ok "ปิดการใช้งานไฟล์สว็อปแล้ว"
                else
                    print_warn "ไม่พบไฟล์สว็อป /swapfile"
                fi
                ;;
            3)
                read -rp "ระบุขนาดไฟล์สว็อปเป็น GB: " swap_size
                if [[ $swap_size =~ ^[0-9]+$ ]] && [ "$swap_size" -gt 0 ]; then
                    print_info "กำลังสร้างไฟล์สว็อปขนาด ${swap_size}GB..."
                    sudo fallocate -l ${swap_size}G /swapfile
                    sudo mkswap /swapfile
                    sudo swapon /swapfile
                    print_ok "สร้างและเปิดใช้งานไฟล์สว็อปขนาด ${swap_size}GB เรียบร้อยแล้ว"
                else
                    print_error "ขนาดไม่ถูกต้อง กรุณาใส่จำนวนเต็มบวก"
                fi
                ;;
            4)
                return
                ;;
            *)
                print_error "ตัวเลือกไม่ถูกต้อง โปรดลองใหม่อีกครั้ง"
                ;;
        esac
        echo -e "\nกด Enter เพื่อกลับไปที่เมนู..."
        read -r
    done
}

main_menu() {
    while true; do
        clear
        display_logo
        check_script_version
        echo -e "\n${clrBold}เลือกคำสั่งที่ต้องการ:${clrReset} / Select an action:"
        echo "1) ติดตั้ง dependencies / Install dependencies"
        echo "2) โคลน RL Swarm / Clone RL Swarm"
        echo "3) รัน Gensyn node ใน screen (ชื่อ: gensyn) / Run Gensyn node in screen (name: gensyn)"
        echo "4) อัปเดต RL Swarm / Update RL Swarm"
        echo "5) ตรวจสอบเวอร์ชันปัจจุบันของ node / Check current node version"
        echo "6) ลบ RL Swarm (พร้อมสำรองคีย์ส่วนตัว) / Remove RL Swarm (keep private key)"
        echo "7) กู้คืน swarm.pem จากไฟล์สำรอง / Restore swarm.pem from backup"
        echo "8) รัน HTTPS tunnel ด้วย Cloudflared (screen: cftunnel) / Start HTTPS tunnel Cloudflared (screen: cftunnel)"
        echo "9) จัดการไฟล์สว็อป / Swap file management"
        echo "10) ออกจากโปรแกรม / Exit"
        read -rp "กรอกหมายเลข / Enter a number: " choice
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
            10) echo -e "${clrGreen}ลาก่อน!${clrReset}"; exit 0 ;;
            *) print_error "ตัวเลือกไม่ถูกต้อง โปรดลองใหม่อีกครั้ง" ;;
        esac
        echo -े "\nกด Enter เพื่อกลับไปที่เมนู..."
        read -r
    done
}

# เรียกเมนูหลัก (ไม่มีการตรวจสอบเวอร์ชันเพิ่มเติม)
main_menu
