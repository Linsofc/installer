#!/bin/bash
# ==========================================
#  Pterodactyl Panel Installer (Only Panel)
#  Author: ChatGPT Modified Version
#  Compatible: Ubuntu/Debian/Rocky/AlmaLinux
# ==========================================

set -e
export DEBIAN_FRONTEND=noninteractive

# ---------- CHECK ROOT ----------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Silakan jalankan script ini sebagai root."
  exit 1
fi

# ---------- OS DETECTION ----------
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
  VER=$VERSION_ID
else
  echo "Tidak dapat mendeteksi OS!"
  exit 1
fi

echo "🧩 OS terdeteksi: $OS $VER"

# ---------- UPDATE & INSTALL DEPENDENCIES ----------
echo "🔧 Mengupdate repository dan menginstal dependensi..."
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  apt update -y
  apt install -y curl unzip git redis-server nginx mariadb-server php php-cli php-gd php-mysql php-mbstring php-xml php-bcmath php-zip php-curl php-tokenizer php-common php-fpm php-intl composer
elif [[ "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
  dnf install -y epel-release
  dnf install -y curl unzip git redis nginx mariadb-server php php-cli php-gd php-mysqlnd php-mbstring php-xml php-bcmath php-zip php-curl php-intl composer
  systemctl enable --now mariadb redis nginx php-fpm
else
  echo "❌ OS tidak didukung!"
  exit 1
fi

systemctl enable --now mariadb redis nginx php-fpm || true

# ---------- DATABASE SETUP ----------
echo "📦 Membuat database untuk panel..."
DB_NAME="panel"
DB_USER="pterodactyl"
DB_PASS=$(openssl rand -base64 12)

mysql -u root <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "✅ Database dibuat!"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo "   Password: $DB_PASS"

# ---------- DOWNLOAD PANEL ----------
cd /var/www
echo "⬇️ Mengunduh Pterodactyl Panel..."
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
mkdir -p /var/www/pterodactyl
tar -xzvf panel.tar.gz -C /var/www/pterodactyl --strip-components=1
cd /var/www/pterodactyl

# ---------- SET PERMISSIONS ----------
chown -R www-data:www-data /var/www/pterodactyl
chmod -R 755 /var/www/pterodactyl

# ---------- ENV SETUP ----------
echo "⚙️ Membuat file environment .env..."
cp .env.example .env

php artisan key:generate --force

# ---------- CONFIGURE DATABASE ----------
sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env
sed -i "s/APP_ENV=production/APP_ENV=production/" .env
sed -i "s|APP_URL=.*|APP_URL=http://$(hostname -I | awk '{print $1}')|" .env

# ---------- COMPOSER INSTALL ----------
echo "📥 Menginstal dependensi PHP (composer install)..."
composer install --no-dev --optimize-autoloader

# ---------- MIGRATE & ADMIN SETUP ----------
echo "🧱 Migrasi database dan setup admin..."
php artisan migrate --seed --force

php artisan p:admin:make --email=admin@localhost --username=admin --name-first=Admin --name-last=Panel --password=admin123 --admin=1

# ---------- QUEUE WORKER ----------
echo "⚙️ Membuat service queue worker..."
cat > /etc/systemd/system/pteroq.service <<EOF
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now pteroq

# ---------- NGINX CONFIG ----------
echo "🌐 Membuat konfigurasi Nginx..."
cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name $(hostname -I | awk '{print $1}');
    root /var/www/pterodactyl/public;

    index index.php;
    charset utf-8;
    client_max_body_size 100M;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
nginx -t && systemctl reload nginx

# ---------- FINISH ----------
echo "✅ Instalasi selesai!"
echo "============================================="
echo "URL Panel     : http://$(hostname -I | awk '{print $1}')"
echo "Admin Email   : admin@localhost"
echo "Admin User    : admin"
echo "Admin Pass    : admin123"
echo "Database Name : $DB_NAME"
echo "Database User : $DB_USER"
echo "Database Pass : $DB_PASS"
echo "============================================="
echo "Login ke panel lalu ubah konfigurasi sesuai kebutuhanmu."
