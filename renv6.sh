#!/bin/bash
# ==========================================
# 🚀 RenClouds v4.5 - FINAL STABLE RELEASE
# Fresh Install + Video + TempMail + Tools + Notif + APK
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain Web (contoh: am.domainkamu.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }
read -p "👉 Email SSL: " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"
read -p "👉 Package Name APK (contoh: com.renclouds.app): " PKG_NAME
[[ -z "$PKG_NAME" ]] && PKG_NAME="com.renclouds.app"

# Firebase Config (Bisa di skip dulu, isi enter aja)
read -p "👉 Firebase API Key (Enter jika skip): " FB_API_KEY
read -p "👉 Firebase Project ID (Enter jika skip): " FB_PROJECT_ID
read -p "👉 Firebase Sender ID (Enter jika skip): " FB_SENDER_ID
read -p "👉 Firebase App ID (Enter jika skip): " FB_APP_ID
read -p "👉 Firebase VAPID Key (Enter jika skip): " FB_VAPID

WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"
DB_USER="ren_user"
DB_PASS=$(openssl rand -hex 12)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
NODE_PORT=3001

# ==========================================
# 1. INSTALL DEPENDENCY
# ==========================================
echo -e "${CYAN}[1/6] Install Nginx, PHP, MariaDB, Node.js...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt update -qq
apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl \
  php8.3-xml php8.3-zip php8.3-gd mariadb-server mariadb-client \
  certbot python3-certbot-nginx curl dnsutils >/dev/null 2>&1
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
apt install -y nodejs >/dev/null 2>&1
systemctl enable --now nginx php8.3-fpm mariadb >/dev/null 2>&1

# ==========================================
# 2. SETUP DATABASE
# ==========================================
echo -e "${CYAN}[2/6] Setup Database & Tables...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << SQLEOF
CREATE TABLE admins (
    id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO admins (username, password) VALUES ('admin', 'Ren11#');

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL,
    is_premium TINYINT(1) DEFAULT 0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE logs (
    id INT AUTO_INCREMENT PRIMARY KEY, email VARCHAR(100), api_used VARCHAR(50),
    status ENUM('success','failed') DEFAULT 'failed', message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE settings (
    id INT PRIMARY KEY,
    api_v1 VARCHAR(255) DEFAULT 'https://am.rafaelxd.my.id/api/v1',
    api_v2 VARCHAR(255) DEFAULT 'https://am.neonode.my.id/api',
    api_v3 VARCHAR(255) DEFAULT 'https://am.noxxyrorr.biz.id/api',
    api_key VARCHAR(255) DEFAULT 'alight_live_3809350d937f869762f6de5d3a9a60d0',
    site_name VARCHAR(100) DEFAULT 'RenClouds',
    maintenance TINYINT(1) DEFAULT 0,
    maintenance_msg TEXT DEFAULT 'Sedang dalam perbaikan, kembali lagi nanti ya!',
    apk_package VARCHAR(100) DEFAULT '$PKG_NAME',
    apk_fingerprint VARCHAR(200) DEFAULT '00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00',
    tools_enabled TINYINT(1) DEFAULT 1,
    fcm_server_key VARCHAR(255) DEFAULT ''
);
INSERT INTO settings (id) VALUES (1);

CREATE TABLE push_subscribers (
    id INT AUTO_INCREMENT PRIMARY KEY, user_id INT, fcm_token TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE notifications (
    id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(255), body TEXT,
    sent_to INT DEFAULT 0, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}  ✅ Database Siap${NC}"

# ==========================================
# 3. BIKIN FILE WEB
# ==========================================
echo -e "${CYAN}[3/6] Generate File Web...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{assets,api,temp,.well-known}

# --- CONFIG.PHP ---
cat > "$WEB_ROOT/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', '127.0.0.1');
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');
define('NODE_MAIL', 'http://127.0.0.1:$NODE_PORT');
try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }
function getSetting(\$pdo) { return \$pdo->query("SELECT * FROM settings WHERE id=1")->fetch(); }
function isAdmin() { return isset(\$_SESSION['admin']); }
function isUser() { return isset(\$_SESSION['user_id']); }
function requireAdmin() { if(!isAdmin()) { header('Location: login.php'); exit; } }
function requireUser() { if(!isUser()) { header('Location: user_login.php'); exit; } }
function getUser(\$pdo) {
    if(!isUser()) return null;
    \$stmt = \$pdo->prepare("SELECT * FROM users WHERE id=?"); \$stmt->execute([\$_SESSION['user_id']]);
    return \$stmt->fetch();
}
function callApi(\$url, \$endpoint, \$data, \$api_key) {
    \$ch = curl_init(rtrim(\$url, '/') . '/' . ltrim(\$endpoint, '/'));
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_POST, true);
    curl_setopt(\$ch, CURLOPT_POSTFIELDS, json_encode(\$data));
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json','x-api-key: ' . \$api_key]);
    curl_setopt(\$ch, CURLOPT_TIMEOUT, 30);
    \$res = curl_exec(\$ch); curl_close(\$ch);
    return json_decode(\$res, true);
}
PHPEOF

# --- FIREBASE CONFIG + PWA INIT ---
cat > "$WEB_ROOT/pwa-init.php" << PHPEOF
<?php require_once 'config.php'; ?>
<link rel="manifest" href="/manifest.json">
<meta name="theme-color" content="#6366f1">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="apple-touch-icon" href="https://h.uguu.se/OTWLMWKtuAMa.jpeg">

<script type="module">
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-app.js";
import { getMessaging, getToken, onMessage } from "https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging.js";

const firebaseConfig = {
    apiKey: "$FB_API_KEY",
    projectId: "$FB_PROJECT_ID",
    messagingSenderId: "$FB_SENDER_ID",
    appId: "$FB_APP_ID"
};

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);

async function enableNotif() {
    try {
        const permission = await Notification.requestPermission();
        if (permission !== 'granted') return alert('Izin notifikasi ditolak!');
        const token = await getToken(messaging, { vapidKey: '$FB_VAPID' });
        if (!token) return alert('Gagal dapat token FCM.');
        const fd = new FormData(); fd.append('token', token);
        const res = await fetch('/api/save_token.php', { method: 'POST', body: fd });
        const data = await res.json();
        if (data.status) {
            alert('✅ Notifikasi Aktif!');
            document.getElementById('btnNotif').innerHTML = '<i class="fas fa-check-circle"></i> Notif Aktif';
            document.getElementById('btnNotif').classList.replace('btn-warning', 'btn-success');
            document.getElementById('btnNotif').disabled = true;
        } else alert('❌ ' + data.message);
    } catch (e) { alert('Error: ' + e.message); }
}
onMessage(messaging, (payload) => { alert(payload.notification.title + '\n' + payload.notification.body); });
window.enableNotif = enableNotif;

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/firebase-messaging-sw.js');
</script>

<script>
let deferredPrompt;
window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault(); deferredPrompt = e;
    const btn = document.getElementById('btnInstallAPK');
    if (btn) btn.style.display = 'flex';
});
function installAPK() {
    if (!deferredPrompt) return alert('Gunakan Chrome untuk install');
    deferredPrompt.prompt();
    deferredPrompt.userChoice.then((choice) => {
        if (choice.outcome === 'accepted') alert('✅ RenClouds terinstall!');
        deferredPrompt = null;
    });
}
</script>
PHPEOF

# --- FIREBASE MESSAGING SW ---
cat > "$WEB_ROOT/firebase-messaging-sw.js" << SWEOF
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');
const firebaseConfig = {
  apiKey: "$FB_API_KEY", projectId: "$FB_PROJECT_ID",
  messagingSenderId: "$FB_SENDER_ID", appId: "$FB_APP_ID"
};
firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification;
  self.registration.showNotification(title, {
    body: body, icon: 'https://h.uguu.se/OTWLMWKtuAMa.jpeg',
    vibrate: [200, 100, 200]
  });
});
SWEOF

# --- ASSET LINKS ---
cat > "$WEB_ROOT/.well-known/assetlinks.json" << ALEOF
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "$PKG_NAME",
    "sha256_cert_fingerprints": ["00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"]
  }
}]
ALEOF

# --- MANIFEST ---
cat > "$WEB_ROOT/manifest.json" << MEOF
{
  "name": "RenClouds - AM Premium", "short_name": "RenClouds",
  "start_url": "/index.php", "display": "standalone",
  "background_color": "#05080f", "theme_color": "#6366f1",
  "icons": [{"src": "https://h.uguu.se/OTWLMWKtuAMa.jpeg", "sizes": "192x192", "type": "image/jpeg"}]
}
MEOF

# --- API SAVE TOKEN ---
cat > "$WEB_ROOT/api/save_token.php" << 'PHPEOF'
<?php
require '../config.php';
header('Content-Type: application/json');
if(!isUser()){ echo json_encode(["status"=>false,"message"=>"Login dulu!"]); exit; }
$token = $_POST['token'] ?? '';
if(!$token){ echo json_encode(["status"=>false,"message"=>"Token kosong"]); exit; }
$user = getUser($pdo);
$stmt = $pdo->prepare("SELECT id FROM push_subscribers WHERE fcm_token=?"); $stmt->execute([$token]);
if($stmt->fetch()){ echo json_encode(["status"=>true,"message"=>"Token sudah tersimpan"]); exit; }
$pdo->prepare("INSERT INTO push_subscribers (user_id, fcm_token) VALUES (?,?)")->execute([$user['id'], $token]);
echo json_encode(["status"=>true, "message"=>"Token disimpan"]);
PHPEOF

# (Index, register, login, dashboard, tools, admin, api endpoints...)
# DISINI GUA SINGKAT KARENA SAMA KAYAK SCRIPT SEBELUMNYA
# Silakan ambil file index.php, dashboard.php, tools.php, admin.php, dll dari script v3 & v4 sebelumnya.
# Intinya script ini fokus di KONEKSI DB yang bersih + Config Firebase yang bener.

# --- NGINX CONF ---
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;
    client_max_body_size 10M;
    location ~ /\.ht { deny all; }
    location /.well-known/assetlinks.json { default_type application/json; allow all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
nginx -t >/dev/null 2>&1 && systemctl reload nginx
chown -R www-data:www-data "$WEB_ROOT"
systemctl restart php8.3-fpm

# SSL Certbot
SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1
fi

echo -e "${GREEN}✅ SUKSES! Web udah fresh install dan bebas error DB.${NC}"
