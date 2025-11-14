#!/bin/bash

# Pembolehubah untuk semakan versi
SCRIPT_NAME="Gensyn"
SCRIPT_VERSION="1.2.0"
VERSIONS_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/versions.txt"
SCRIPT_FILE_URL="https://raw.githubusercontent.com/k2wGG/scripts/main/Gensyn.sh"

# Warna untuk output
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
    print_info "Menyemak versi skrip terkini..."
    remote_version=$(curl -s "$VERSIONS_FILE_URL" | grep "^${SCRIPT_NAME}=" | cut -d'=' -f2)
    if [ -z "$remote_version" ]; then
        print_warn "Tidak dapat menentukan versi remote untuk ${SCRIPT_NAME}"
    elif [ "$remote_version" != "$SCRIPT_VERSION" ]; then
        print_warn "Versi baru tersedia: $remote_version (semasa: $SCRIPT_VERSION)"
        print_info "Disyorkan untuk memuat turun skrip yang dikemas kini dari sini:\n$SCRIPT_FILE_URL"
    else
        print_ok "Menggunakan versi skrip terkini ($SCRIPT_VERSION)"
    fi
}

# Semakan versi Python dan Node.js telah dibuang

system_update_and_install() {
    print_info "Mengemas kini sistem dan memasang alat pembangunan yang diperlukan..."
    
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip curl screen git
    
    # Установка yarn из официального репозитория
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    sudo apt update && sudo apt install -y yarn
    
    # Установка localtunnel
    sudo npm install -g localtunnel
    
    # Установка Node.js 22.x
    sudo apt-get update
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Проверка версий
    node -v
    sudo npm install -g yarn
    yarn -v
    
    print_ok "Semua kebergantungan telah dipasang"
}

clone_repo() {
    print_info "Mengklon repositori RL Swarm..."
    git clone https://github.com/gensyn-ai/rl-swarm.git "$HOME/rl-swarm" || { print_error "Tidak dapat mengklon repositori"; exit 1; }
    print_ok "Repositori telah diklon"
}

start_gensyn_screen() {
    # Semak dan jalankan sesi screen 'gensyn' untuk nod
    if screen -list | grep -q "gensyn"; then
        print_warn "Sesi screen 'gensyn' sudah wujud! Gunakan 'screen -r gensyn' untuk masuk."
        return
    fi
    print_info "Memulakan nod RL Swarm dalam sesi screen 'gensyn'..."
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
    print_ok "Nod dijalankan dalam sesi screen 'gensyn'. Taip 'screen -r gensyn' untuk sambung."
}

update_node() {
    print_info "Mengemas kini RL Swarm..."
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || exit 1
        git switch main
        git reset --hard
        git clean -fd
        git pull origin main
        git pull
        print_ok "Repositori telah dikemas kini."
    else
        print_error "Folder rl-swarm tidak ditemui"
    fi
}

check_current_node_version() {
    if [ -d "$HOME/rl-swarm" ]; then
        cd "$HOME/rl-swarm" || { print_error "Tidak dapat masuk ke direktori rl-swarm"; return; }
        current_version=$(git describe --tags 2>/dev/null)
        if [ $? -eq 0 ]; then
            print_ok "Versi nod semasa: $current_version"
        else
            print_warn "Tidak dapat menentukan versi semasa (mungkin tiada tag)"
        fi
    else
        print_error "Folder rl-swarm tidak ditemui"
    fi
}

delete_rlswarm() {
    print_warn "Menyimpan kunci peribadi swarm.pem (jika ada)..."
    if [ -f "$HOME/rl-swarm/swarm.pem" ]; then
        cp "$HOME/rl-swarm/swarm.pem" "$HOME/swarm.pem.backup"
        print_ok "swarm.pem disalin ke $HOME/swarm.pem.backup"
    fi
    print_info "Memadam rl-swarm..."
    rm -rf "$HOME/rl-swarm"
    print_ok "Folder rl-swarm telah dipadam. Kunci peribadi disimpan sebagai ~/swarm.pem.backup"
}

restore_swarm_pem() {
    if [ -f "$HOME/swarm.pem.backup" ]; then
        cp "$HOME/swarm.pem.backup" "$HOME/rl-swarm/swarm.pem"
        print_ok "swarm.pem dipulihkan daripada $HOME/swarm.pem.backup"
    else
        print_warn "Sandaran swarm.pem tidak ditemui."
    fi
}

setup_cloudflared_screen() {
    print_info "Pemasangan dan jalankan Cloudflared untuk terowong HTTPS pada port 3000..."

    # Pakej asas
    sudo apt-get update -y
    sudo apt-get install -y ufw screen wget ca-certificates

    # Peraturan UFW
    sudo ufw allow 22/tcp
    sudo ufw allow 3000/tcp
    sudo ufw --force enable

    # Определяем архитектуру для выбора правильного .deb
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
            print_err "Seni bina tidak disokong: ${ARCH}. Hanya amd64 dan arm64 disokong."
            return 1
            ;;
    esac

    # Установка cloudflared, если не стоит
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_info "cloudflared tidak ditemui. Memuat turun pakej untuk ${ARCH}..."
        local TMP_DEB="/tmp/cloudflared-${ARCH}.deb"
        if ! wget -q -O "${TMP_DEB}" "${DEB_URL}"; then
            print_err "Tidak dapat memuat turun cloudflared untuk ${ARCH}."
            return 1
        fi

        print_info "Memasang cloudflared..."
        if ! sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1; then
            # подтянуть зависимости при необходимости
            sudo apt-get -f install -y
            # повторить установку
            sudo dpkg -i "${TMP_DEB}" >/dev/null 2>&1 || {
                print_err "Tidak dapat memasang cloudflared untuk ${ARCH}."
                rm -f "${TMP_DEB}"
                return 1
            }
        fi
        rm -f "${TMP_DEB}"
    fi

    # Финальная проверка наличия бинаря
    if ! command -v cloudflared >/dev/null 2>&1; then
        print_err "cloudflared tidak ditemui selepas pemasangan. Menghentikan."
        return 1
    fi

    # Не создаём второй screen, если уже есть
    if screen -list | grep -q "[.]cftunnel"; then
        print_warn "Sesi screen 'cftunnel' sudah wujud! Gunakan 'screen -r cftunnel' untuk masuk."
        return 0
    fi

    # Folder untuk log
    sudo mkdir -p /var/log
    local LOG_FILE="/var/log/cloudflared-screen.log"

    print_info "Memulakan terowong Cloudflared dalam sesi screen 'cftunnel'..."
    # -dmS: detached, named session; bash -lc чтобы подхватить PATH
    screen -dmS cftunnel bash -lc "cloudflared tunnel --no-autoupdate --url http://localhost:3000 2>&1 | tee -a ${LOG_FILE}"

    # Небольшая задержка и проверка процесса
    sleep 1
    if pgrep -af cloudflared >/dev/null 2>&1; then
        print_ok "Terowong Cloudflared dijalankan dalam screen 'cftunnel'. Lihat pautan dalam output: 'screen -r cftunnel'. Log: ${LOG_FILE}"
        return 0
    else
        print_err "Tidak dapat memulakan cloudflared dalam screen. Semak log: ${LOG_FILE} dan 'screen -r cftunnel'."
        return 1
    fi
}

swap_menu() {
    while true; do
        clear
        display_logo
        echo -e "\n${clrBold}Pengurusan fail swap:${clrReset}"
        echo "1) Fail swap yang aktif sekarang"
        echo "2) Hentikan fail swap"
        echo "3) Cipta fail swap"
        echo "4) Kembali"
        read -rp "Masukkan nombor: " swap_choice
        case $swap_choice in
            1)
                print_info "Fail swap yang aktif:"
                swapon --show
                ;;
            2)
                print_info "Menghentikan fail swap..."
                if [ -f /swapfile ]; then
                    sudo swapoff /swapfile
                    print_ok "Fail swap dihentikan"
                else
                    print_warn "Fail swap /swapfile tidak ditemui"
                fi
                ;;
            3)
                read -rp "Masukkan saiz fail swap dalam GB: " swap_size
                if [[ $swap_size =~ ^[0-9]+$ ]] && [ "$swap_size" -gt 0 ]; then
                    print_info "Mencipta fail swap bersaiz ${swap_size}GB..."
                    sudo fallocate -l ${swap_size}G /swapfile
                    sudo mkswap /swapfile
                    sudo swapon /swapfile
                    print_ok "Fail swap bersaiz ${swap_size}GB telah dicipta dan diaktifkan"
                else
                    print_error "Saiz tidak sah. Sila masukkan nombor bulat positif."
                fi
                ;;
            4)
                return
                ;;
            *)
                print_error "Pilihan tidak sah, cuba lagi."
                ;;
        esac
        echo -e "\nTekan Enter untuk kembali ke menu..."
        read -r
    done
}

main_menu() {
    while true; do
        clear
        display_logo
        check_script_version
        echo -e "\n${clrBold}Pilih tindakan:${clrReset} / Select an action:"
        echo "1) Pasang kebergantungan / Install dependencies"
        echo "2) Klon RL Swarm / Clone RL Swarm"
        echo "3) Jalankan nod Gensyn dalam screen (nama: gensyn) / Run Gensyn node in screen (name: gensyn)"
        echo "4) Kemas kini RL Swarm / Update RL Swarm"
        echo "5) Semak versi nod semasa / Check current node version"
        echo "6) Padam RL Swarm (simpan kunci peribadi) / Remove RL Swarm (keep private key)"
        echo "7) Pulihkan swarm.pem daripada sandaran / Restore swarm.pem from backup"
        echo "8) Jalankan terowong HTTPS Cloudflared (screen: cftunnel) / Start HTTPS tunnel Cloudflared (screen: cftunnel)"
        echo "9) Pengurusan fail swap / Swap file management"
        echo "10) Keluar / Exit"
        read -rp "Masukkan nombor / Enter a number: " choice
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
            10) echo -e "${clrGreen}Selamat jalan!${clrReset}"; exit 0 ;;
            *) print_error "Pilihan tidak sah, cuba lagi." ;;
        esac
        echo -e "\nTekan Enter untuk kembali ke menu..."
        read -r
    done
}

# Jalankan menu utama (tanpa semakan versi)
main_menu
