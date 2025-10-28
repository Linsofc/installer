#!/bin/bash
# ==========================================
#  Pterodactyl Full Auto Installer
#  Author: Modified by ChatGPT (based on Vilhelm Prytz)
#  Auto input version — Ubuntu/Debian
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# ---------- INPUT AWAL ----------
echo "=== PTERODACTYL AUTO INSTALLER ==="
read -p "Masukkan domain panel (contoh: dashboard.linsofc.my.id): " PANEL_DOMAIN
read -p "Masukkan email admin panel: " ADMIN_EMAIL
read -p "Masukkan username admin: " ADMIN_USER
read -sp "Masukkan password admin: " ADMIN_PASS; echo
read -sp "Masukkan password database (MySQL root): " MYSQL_ROOT_PASS; echo
read -p "Masukkan timezone (contoh: Asia/Jakarta): " TIMEZONE
TIMEZONE=${TIMEZONE:-Asia/Jakarta}

echo ""
echo "=== Mulai instalasi otomatis Pterodactyl Panel ==="
sleep 2

# ---------- UPDATE SISTEM ----------
apt update -y && apt upgrade -y

# ---------- INSTAL DEPENDENSI ----------
apt install -y curl wget sudo unzip zip git gnupg software-properties-common ca-certificates apt-transport-https lsb-release dirmngr

# ---------- INSTALL NGINX, MARIADB, PHP ----------
apt install -y nginx mariadb-server mariadb-client

echo "Mengatur password root MariaDB..."
mysql -u root <<MYSQL_SCRIPT
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

systemctl enable --now mariadb
systemctl enable --now nginx

# ---------- INSTALL PHP 8.2 ----------
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update -y
apt install -y php8.2 php8.2-{cli,gd,mysql,mbstring,xml,bcmath,zip,curl,pgsql,intl,fpm}

# ---------- DOWNLOAD PANEL ----------
cd /var/www/
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
mkdir -p /var/www/pterodactyl
tar -xzvf panel.tar.gz -C /var/www/pterodactyl --strip-components=1
cd /var/www/pterodactyl

# ---------- INSTALL COMPOSER ----------
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# ---------- SETUP DATABASE PANEL ----------
DB_PASS=$(openssl rand -hex 16)
mysql -u root -p"${MYSQL_ROOT_PASS}" <<MYSQL_SCRIPT
CREATE DATABASE panel;
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# ---------- ENV SETUP ----------
cp .env.example .env
composer install --no-dev --optimize-autoloader

php artisan key:generate --force

php artisan p:environment:setup \
  --author="$ADMIN_EMAIL" \
  --url="https://${PANEL_DOMAIN}" \
  --timezone="$TIMEZONE" \
  --cache=redis \
  --session=redis \
  --queue=redis \
  --disable-settings-ui=yes

php artisan p:environment:database \
  --host=127.0.0.1 \
  --port=3306 \
  --database=panel \
  --username=pterodactyl \
  --password="${DB_PASS}"

php artisan p:environment:mail \
  --driver=smtp \
  --host=mail.example.com \
  --port=587 \
  --username=mail@example.com \
  --password=password123 \
  --from=admin@$PANEL_DOMAIN \
  --from-name="Pterodactyl"

php artisan migrate --seed --force
php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name-first="Admin" --name-last="User" --password="$ADMIN_PASS" --admin=1

# ---------- PERMISSION ----------
chown -R www-data:www-data /var/www/pterodactyl/*
chmod -R 755 /var/www/pterodactyl/*

# ---------- KONFIG NGINX ----------
cat >/etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${PANEL_DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl_access.log;
    error_log  /var/log/nginx/pterodactyl_error.log error;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# ---------- INSTALL LET'S ENCRYPT ----------
apt install -y certbot python3-certbot-nginx
certbot --nginx -d "$PANEL_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL"

# ---------- INSTALL WINGS ----------
curl -Lo /usr/local/bin/wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x /usr/local/bin/wings
useradd -r -m -d /etc/pterodactyl -s /bin/false pterodactyl
mkdir -p /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl

cat >/etc/systemd/system/wings.service <<EOF
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=600
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable wings

# ---------- DOCKER INSTALL ----------
curl -fsSL https://get.docker.com | bash
systemctl enable --now docker
systemctl start wings

# ---------- SELESAI ----------
echo ""
echo "=============================================="
echo "✅ Instalasi Pterodactyl Panel Selesai!"
echo "Panel: https://${PANEL_DOMAIN}"
echo "Login Admin: ${ADMIN_EMAIL}"
echo "Password: ${ADMIN_PASS}"
echo "Database Password: ${DB_PASS}"
echo "=============================================="
echo ""
