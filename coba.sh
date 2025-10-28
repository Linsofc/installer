#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pterodactyl-installer'                                                    #
#                                                                                    #
# Copyright (C) 2018 - 2025, Vilhelm Prytz, <vilhelm@prytznet.se>                      #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/pterodactyl-installer/pterodactyl-installer/blob/master/LICENSE #
#                                                                                    #
# This script is not associated with the official Pterodactyl Project.               #
# https://github.com/pterodactyl-installer/pterodactyl-installer                     #
#                                                                                    #
######################################################################################

export GITHUB_SOURCE="v1.2.0"
export SCRIPT_RELEASE="v1.2.0"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"

LOG_PATH="/var/log/pterodactyl-installer.log"

# check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* curl is required in order for this script to work."
  echo "* install using apt (Debian and derivatives) or yum/dnf (CentOS)"
  exit 1
fi

# Always remove lib.sh, before downloading it
[ -f /tmp/lib.sh ] && rm -rf /tmp/lib.sh
curl -sSL -o /tmp/lib.sh "$GITHUB_BASE_URL"/master/lib/lib.sh
# shellcheck source=lib/lib.sh
source /tmp/lib.sh

# MODIFIKASI: Fungsi execute disederhanakan untuk tidak menanyakan instalasi lanjutan
execute() {
  echo -e "\n\n* pterodactyl-installer $(date) \n\n" >>$LOG_PATH

  [[ "$1" == *"canary"* ]] && export GITHUB_SOURCE="master" && export SCRIPT_RELEASE="canary"
  update_lib_source
  run_ui "${1//_canary/}" |& tee -a $LOG_PATH

  # Blok 'if' yang menanyakan instalasi $2 (wings) telah dihapus
  # Ini membuat skrip berhenti setelah $1 (panel) selesai
}

welcome ""

# --- MULAI MODIFIKASI: Kumpulkan Semua Input di Awal ---
# Skrip installer akan menggunakan variabel ini dan melewatkan pertanyaan

output "Memasukkan semua data yang diperlukan untuk instalasi panel..."
output "Skrip ini akan mengumpulkan semua data sekarang, lalu berjalan otomatis."
output ""

# FQDN
required_input "PANEL_FQDN" "Masukkan FQDN (domain) untuk panel (e.g., panel.domain.com): " "FQDN tidak boleh kosong."
export PANEL_FQDN

# Admin User
email_input "ADMIN_EMAIL" "Masukkan email untuk akun admin: " "Email tidak valid."
export ADMIN_EMAIL
required_input "ADMIN_USER" "Masukkan username untuk akun admin (default: admin): " "" "admin"
export ADMIN_USER
# 'gen_passwd 32' akan membuat password 32 karakter jika input dikosongkan
password_input "ADMIN_PASS" "Password admin (akan digenerate jika kosong): " "" "$(gen_passwd 32)"
export ADMIN_PASS
required_input "ADMIN_NAME_FIRST" "Masukkan nama depan admin (default: Admin): " "" "Admin"
export ADMIN_NAME_FIRST
required_input "ADMIN_NAME_LAST" "Masukkan nama belakang admin (default: User): " "" "User"
export ADMIN_NAME_LAST

# Database
required_input "DB_NAME" "Nama database (default: panel): " "" "panel"
export DB_NAME
required_input "DB_USER" "User database (default: pterodactyl): " "" "pterodactyl"
export DB_USER
password_input "DB_PASS" "Password database (akan digenerate jika kosong): " "" "$(gen_passwd 32)"
export DB_PASS

# Konfigurasi Tambahan (Firewall & SSL)
# Ini akan meng-override 'ask_firewall' dan 'ask_ssl' di dalam skrip instalasi

echo -e -n "* Apakah Anda ingin mengkonfigurasi firewall (UFW/firewalld)? (y/N): "
read -r CONFIRM_FIREWALL
if [[ "$CONFIRM_FIREWALL" =~ [Yy] ]]; then
    export FIREWALL="true"
else
    export FIREWALL="false"
fi

echo -e -n "* Apakah Anda ingin mengkonfigurasi SSL/HTTPS (Let's Encrypt)? (y/N): "
read -r CONFIRM_SSL
if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    export SSL="true"
else
    export SSL="false"
fi

output "=================================================================="
output "Semua data telah dikumpulkan. Memulai instalasi non-interaktif..."
output "Log instalasi akan disimpan di $LOG_PATH"
output "=================================================================="
sleep 3

# --- SELESAI MODIFIKASI ---

# Hapus loop menu interaktif
# done=false
# while [ "$done" == false ]; do
#   ... (semua kode menu dihapus) ...
# done

# Langsung jalankan fungsi instalasi panel
execute "panel"

# Remove lib.sh, so next time the script is run the, newest version is downloaded.
rm -rf /tmp/lib.sh

echo "=================================================================="
success "Instalasi panel selesai."
echo "Login: http://$PANEL_FQDN untuk mengakses panel Pterodactyl."
echo "Password admin: $ADMIN_PASS"
echo "Username admin: $ADMIN_USER"
echo "Database name: $DB_NAME"
echo "Database user: $DB_USER"
echo "Database password: $DB_PASS"
echo "=================================================================="