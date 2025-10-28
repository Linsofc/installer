#!/bin/bash
# ==========================================
#  Pterodactyl Panel Auto Installer (No Prompt)
#  Based on https://pterodactyl-installer.se
#  Modified by ChatGPT — Auto install without confirmation
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --------- Input Data ---------
read -p "Masukkan domain panel (contoh: dashboard.linsofc.my.id): " PANEL_DOMAIN
read -p "Masukkan email admin: " ADMIN_EMAIL
read -p "Masukkan nama pengguna admin: " ADMIN_USERNAME
read -sp "Masukkan password admin: " ADMIN_PASSWORD
echo ""
read -p "Masukkan nama database (contoh: panel): " DB_NAME
read -p "Masukkan user database: " DB_USER
read -sp "Masukkan password database: " DB_PASS
echo ""
read -p "Masukkan alamat IP server: " SERVER_IP

# --------- Update Sistem ---------
apt update -y && apt upgrade -y
apt install -y curl sudo zip unzip git lsb-release software-properties-common apt-transport-https ca-certificates gnupg

# --------- Install MariaDB ---------
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt install -y mariadb-server
systemctl enable mariadb
systemctl start mariadb

# Buat database dan user
mariadb -u root <<MYSQL_SCRIPT
CREATE DATABASE ${DB_NAME};
CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# --------- Install Redis & Dependencies ---------
apt install -y redis-server
systemctl enable redis-server --now

# --------- Install PHP 8.2 ---------
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-{cli,gd,mysql,mbstring,bcmath,xml,curl,zip,common,pgsql,sqlite3,intl,fpm} nginx composer

# --------- Install Panel ---------
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache
cp .env.example .env

# --------- Konfigurasi Database dan App ---------
composer install --no-dev --optimize-autoloader

php artisan key:generate --force
php artisan p:environment:setup -n --url="https://${PANEL_DOMAIN}" --timezone="Asia/Jakarta" --cache="redis" --session="redis" --queue="redis" --email="${ADMIN_EMAIL}"
php artisan p:environment:database -n --host="127.0.0.1" --port=3306 --database="${DB_NAME}" --username="${DB_USER}" --password="${DB_PASS}"
php artisan migrate --seed --force

# --------- Buat akun admin ---------
php artisan p:user:make --email="${ADMIN_EMAIL}" --username="${ADMIN_USERNAME}" --name-first="Admin" --name-last="Panel" --password="${ADMIN_PASSWORD}" --admin=1

# --------- Konfigurasi Nginx ---------
rm /etc/nginx/sites-enabled/default
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
echo "Database:"
echo "  📁 DB Name  : ${DB_NAME}"
echo "  👤 DB User  : ${DB_USER}"
echo "  🔒 DB Pass  : ${DB_PASS}"
echo "-------------------------------------------"
echo "📌 Login sekarang di: https://${PANEL_DOMAIN}"
echo "==========================================="
