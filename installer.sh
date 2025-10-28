#!/bin/bash
# ==========================================
#  Pterodactyl Panel Auto Installer (SQLite - FINAL FIX)
#  By ChatGPT (GPT-5)
#  No MariaDB, No "--email" Error, No SQLite Error
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --------- Input ---------
read -p "Masukkan domain panel (contoh: dashboard.linsofc.my.id): " PANEL_DOMAIN
read -p "Masukkan email admin: " ADMIN_EMAIL
read -p "Masukkan nama pengguna admin: " ADMIN_USERNAME
read -sp "Masukkan password admin: " ADMIN_PASSWORD
echo ""

# --------- Update Sistem ---------
apt update -y && apt upgrade -y
apt install -y curl sudo zip unzip git lsb-release software-properties-common apt-transport-https ca-certificates gnupg

# --------- Install Redis ---------
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
tar -xzf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env

# --------- Install Dependencies ---------
composer install --no-dev --optimize-autoloader

# --------- Generate Key & Setup Environment ---------
php artisan key:generate --force

php artisan p:environment:setup -n \
  --url="https://${PANEL_DOMAIN}" \
  --timezone="Asia/Jakarta" \
  --cache="redis" \
  --session="redis" \
  --queue="redis"

# --------- Setup SQLite Database ---------
mkdir -p database
touch database/database.sqlite
chmod 664 database/database.sqlite

# Update konfigurasi .env ke SQLite
sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/" .env
sed -i "s/^DB_HOST=.*/#DB_HOST=127.0.0.1/" .env
sed -i "s/^DB_PORT=.*/#DB_PORT=3306/" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$(pwd)/database/database.sqlite|" .env
sed -i "s/^DB_USERNAME=.*/#DB_USERNAME=root/" .env
sed -i "s/^DB_PASSWORD=.*/#DB_PASSWORD=/" .env

# Bersihkan cache agar config terbaru dibaca
php artisan config:clear
php artisan cache:clear
php artisan view:clear
php artisan config:cache

# --------- Jalankan Migrasi ---------
php artisan migrate --seed --force

# --------- Buat Admin User ---------
php artisan tinker --execute="
use Pterodactyl\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
User::create([
    'uuid' => (string) Str::uuid(),
    'email' => '${ADMIN_EMAIL}',
    'username' => '${ADMIN_USERNAME}',
    'name_first' => 'Admin',
    'name_last' => 'Panel',
    'password' => Hash::make('${ADMIN_PASSWORD}'),
    'root_admin' => true,
]);
"

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

# --------- SSL ---------
apt install -y certbot python3-certbot-nginx
certbot --nginx -d ${PANEL_DOMAIN} --non-interactive --agree-tos -m ${ADMIN_EMAIL} --redirect || true

# --------- Done ---------
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
