#!/bin/bash
# ==========================================
#  Pterodactyl Panel Auto Installer (SQLite Version - No MySQL)
#  Simplified & Fixed by ChatGPT (GPT-5)
#  Compatible with Ubuntu 20.04 / 22.04
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --------- Input Data ---------
read -p "Masukkan domain panel (contoh: dashboard.linsofc.my.id): " PANEL_DOMAIN
read -p "Masukkan email admin: " ADMIN_EMAIL
read -p "Masukkan nama pengguna admin: " ADMIN_USERNAME
read -sp "Masukkan password admin: " ADMIN_PASSWORD
echo ""
read -p "Masukkan alamat IP server: " SERVER_IP

# --------- Update Sistem ---------
apt update -y && apt upgrade -y
apt install -y curl sudo zip unzip git lsb-release software-properties-common apt-transport-https ca-certificates gnupg

# --------- Install Redis & Dependencies ---------
apt install -y redis-server
systemctl enable redis-server --now

# --------- Install PHP 8.2 & Nginx ---------
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-{cli,gd,sqlite3,mbstring,bcmath,xml,curl,zip,common,intl,fpm} nginx composer

# --------- Install Panel ---------
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env

# --------- Install Dependencies ---------
composer install --no-dev --optimize-autoloader

# --------- Konfigurasi Environment ---------
php artisan key:generate --force

# Setup panel environment tanpa database eksternal (pakai SQLite)
php artisan p:environment:setup -n \
  --url="https://${PANEL_DOMAIN}" \
  --timezone="Asia/Jakarta" \
  --cache="redis" \
  --session="redis" \
  --queue="redis"

# Ganti konfigurasi database ke SQLite
sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=sqlite/" .env
sed -i "s/DB_HOST=.*/#DB_HOST=127.0.0.1/" .env
sed -i "s/DB_PORT=.*/#DB_PORT=3306/" .env
sed -i "s/DB_DATABASE=.*/DB_DATABASE=database\/database.sqlite/" .env
sed -i "s/DB_USERNAME=.*/#DB_USERNAME=root/" .env
sed -i "s/DB_PASSWORD=.*/#DB_PASSWORD=/" .env

# Buat file SQLite
touch database/database.sqlite
chmod 664 database/database.sqlite

# Migrasi dan seed database
php artisan migrate --seed --force

# --------- Buat akun admin ---------
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="Admin" \
  --name-last="Panel" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1

# --------- Konfigurasi Nginx ---------
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log /var/log/nginx/pterodactyl_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t && systemctl restart nginx
systemctl enable nginx php8.2-fpm

# --------- Install Certbot (SSL) ---------
apt install -y certbot python3-certbot-nginx
certbot --nginx -d ${PANEL_DOMAIN} --non-interactive --agree-tos -m ${ADMIN_EMAIL} --redirect || true

# --------- Tampilkan hasil ---------
clear
echo "==========================================="
echo "✅ Pterodactyl Panel berhasil diinstal!"
echo "-------------------------------------------"
echo "🌐 URL Panel  : https://${PANEL_DOMAIN}"
echo "👤 Username   : ${ADMIN_USERNAME}"
echo "📧 Email      : ${ADMIN_EMAIL}"
echo "🔑 Password   : ${ADMIN_PASSWORD}"
echo "-------------------------------------------"
echo "🗂 Menggunakan Database SQLite (tanpa MariaDB)"
echo "📍 File DB: /var/www/pterodactyl/database/database.sqlite"
echo "-------------------------------------------"
echo "📌 Login sekarang di: https://${PANEL_DOMAIN}"
echo "==========================================="
