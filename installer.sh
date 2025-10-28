#!/bin/bash
# ==========================================
#  Pterodactyl Panel Auto Installer (SQLite)
#  Tested on Ubuntu 20.04 / 22.04
#  No Database Server Required (uses SQLite)
#  Author: ChatGPT (Modified for local testing)
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --------- Konfigurasi Awal ---------
PANEL_DOMAIN="dahlahv.linsofc.my.id"
ADMIN_EMAIL="admin@example.com"
ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin123"
SERVER_IP="$(hostname -I | awk '{print $1}')"

# --------- Update Sistem ---------
apt update -y && apt upgrade -y
apt install -y curl sudo zip unzip git lsb-release software-properties-common apt-transport-https ca-certificates gnupg redis-server nginx composer

# --------- Install PHP 8.2 ---------
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-{cli,gd,mbstring,bcmath,xml,curl,zip,common,pgsql,sqlite3,intl,fpm}

systemctl enable redis-server --now
systemctl enable php8.2-fpm --now
systemctl enable nginx --now

# --------- Install Panel ---------
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env

composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# --------- Konfigurasi Environment (tanpa database MySQL) ---------
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

# Update .env agar pakai SQLite
sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/" .env
sed -i "s|^DB_DATABASE=.*|DB_DATABASE=$(pwd)/database/database.sqlite|" .env
sed -i "s/^DB_HOST=.*/#DB_HOST=127.0.0.1/" .env
sed -i "s/^DB_PORT=.*/#DB_PORT=3306/" .env
sed -i "s/^DB_USERNAME=.*/#DB_USERNAME=root/" .env
sed -i "s/^DB_PASSWORD=.*/#DB_PASSWORD=/" .env

# Tambahkan definisi koneksi SQLite kalau belum ada
grep -q "'sqlite'" config/database.php || cat <<'EOF' >> config/database.php

        'sqlite' => [
            'driver' => 'sqlite',
            'url' => env('DATABASE_URL'),
            'database' => env('DB_DATABASE', database_path('database.sqlite')),
            'prefix' => '',
            'foreign_key_constraints' => env('DB_FOREIGN_KEYS', true),
        ],
EOF

php artisan config:clear || true
php artisan cache:clear || true
php artisan view:clear || true
php artisan config:cache || true

# --------- Jalankan Migrasi ---------
php artisan migrate --seed --force

# --------- Buat akun admin ---------
php artisan p:user:make \
  --email="${ADMIN_EMAIL}" \
  --username="${ADMIN_USERNAME}" \
  --name-first="Admin" \
  --name-last="Panel" \
  --password="${ADMIN_PASSWORD}" \
  --admin=1 \
  -n

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
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t && systemctl restart nginx

# --------- Install SSL (optional) ---------
apt install -y certbot python3-certbot-nginx || true
certbot --nginx -d ${PANEL_DOMAIN} --non-interactive --agree-tos -m ${ADMIN_EMAIL} --redirect || true

# --------- Output Info ---------
clear
echo "==========================================="
echo "✅ Pterodactyl Panel berhasil diinstal!"
echo "-------------------------------------------"
echo "🌐 URL Panel  : https://${PANEL_DOMAIN}"
echo "👤 Username   : ${ADMIN_USERNAME}"
echo "📧 Email      : ${ADMIN_EMAIL}"
echo "🔑 Password   : ${ADMIN_PASSWORD}"
echo "-------------------------------------------"
echo "🗂  Database   : SQLite (file: /var/www/pterodactyl/database/database.sqlite)"
echo "-------------------------------------------"
echo "📌 Akses sekarang di: https://${PANEL_DOMAIN}"
echo "==========================================="
