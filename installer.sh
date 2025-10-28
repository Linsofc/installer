#!/bin/bash
# ==========================================
#  Pterodactyl Panel Auto Installer (Non-interactive)
#  Author: ChatGPT Modified Version (Based on Vilhelm Prytz)
#  For: Ubuntu/Debian systems
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# ---------------- CONFIGURABLE VARIABLES ---------------- #
# Edit sesuai kebutuhan kamu
PANEL_DOMAIN="coba.linsofc.my.id"
EMAIL="admin@$PANEL_DOMAIN"
DB_ROOT_PASS="rootpassword123"
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS="pteropass123"
TIMEZONE="Asia/Jakarta"

# -------------------------------------------------------- #
LOG_PATH="/var/log/pterodactyl-auto-install.log"
GITHUB_BASE_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer"
GITHUB_SOURCE="master"

echo "* Starting full automatic Pterodactyl Panel installation..."
echo "* Log file: $LOG_PATH"
echo "" > $LOG_PATH

# ---------- Basic Requirements ---------- #
echo "* Installing dependencies..."
apt update -y >> $LOG_PATH 2>&1
apt install -y curl sudo zip unzip tar git gnupg mysql-server mariadb-client nginx certbot python3-certbot-nginx php php8.1 php8.1-{cli,common,gd,xml,mbstring,mysql,pgsql,tokenizer,bcmath,curl,zip,intl,fpm,sqlite3,redis,imagick} redis-server >> $LOG_PATH 2>&1

# ---------- Configure MariaDB ---------- #
echo "* Configuring MariaDB..."
systemctl enable mariadb --now
mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;" || true
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;"
mysql -u root -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';"
mysql -u root -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

# ---------- Download Panel ---------- #
echo "* Downloading Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz >> $LOG_PATH 2>&1
chmod -R 755 storage/* bootstrap/cache

# ---------- Setup Environment ---------- #
echo "* Setting up environment..."
cp .env.example .env
php artisan key:generate --force

# ---------- Auto configure .env ---------- #
sed -i "s|APP_URL=.*|APP_URL=https://$PANEL_DOMAIN|" .env
sed -i "s|DB_HOST=.*|DB_HOST=127.0.0.1|" .env
sed -i "s|DB_PORT=.*|DB_PORT=3306|" .env
sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env
sed -i "s|APP_TIMEZONE=.*|APP_TIMEZONE=$TIMEZONE|" .env
sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" .env
sed -i "s|SESSION_DRIVER=.*|SESSION_DRIVER=redis|" .env

# ---------- Composer Install ---------- #
echo "* Installing Composer dependencies..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer
composer install --no-dev --optimize-autoloader --no-interaction >> $LOG_PATH 2>&1

# ---------- Database Migrate ---------- #
echo "* Migrating database..."
php artisan migrate --seed --force >> $LOG_PATH 2>&1

# ---------- Create Admin User ---------- #
echo "* Creating admin user..."
php artisan p:user:make \
    --email="$EMAIL" \
    --username="admin" \
    --name-first="Panel" \
    --name-last="Admin" \
    --password="Admin1234" \
    --admin=1 >> $LOG_PATH 2>&1

# ---------- Setup Permissions ---------- #
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl/*

# ---------- Setup Nginx ---------- #
echo "* Setting up Nginx..."
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name $PANEL_DOMAIN;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.access.log;
    error_log /var/log/nginx/pterodactyl.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t && systemctl restart nginx

# ---------- SSL Auto Install ---------- #
echo "* Installing SSL certificate..."
certbot --nginx -d "$PANEL_DOMAIN" --agree-tos -m "$EMAIL" --non-interactive --redirect >> $LOG_PATH 2>&1 || true

# ---------- Queue & Cron Setup ---------- #
echo "* Setting up queue worker..."
cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --sleep=3 --tries=3
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq
systemctl restart nginx php8.1-fpm redis-server

# ---------- Done ---------- #
echo ""
echo "==============================================="
echo "✅ Pterodactyl Panel Installed Successfully!"
echo "==============================================="
echo "URL     : https://$PANEL_DOMAIN"
echo "Email   : $EMAIL"
echo "Password: Admin1234"
echo "DB Name : $DB_NAME"
echo "==============================================="
