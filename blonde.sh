#!/bin/bash
# ==========================================
# 🚀 RenClouds v5.0 - FULL STABLE (ANTI 403)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

# Input Domain
read -p "👉 Masukkan Domain (contoh: hackingg.myboc.my.id): " DOMAIN
[[ -z "$DOMAIN" ]] && exit 1
WEB_ROOT="/var/www/$DOMAIN"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
DB_NAME="renclouds_db"
DB_USER="ren_user"
DB_PASS="renpassword123" # Biar ga ribet, password disamain

# 1. BERSIHIN FOLDER & IZIN
echo -e "${CYAN}[1/5] Membersihkan Folder Web...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{api,assets,.well-known}
chmod -R 755 "$WEB_ROOT"

# 2. FILE INDEX.PHP (Landing Page)
echo -e "${CYAN}[2/5] Membuat File Landing Page...${NC}"
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
// Dummy index biar ga 403
echo "<h1 style='color:white;background:#05080f;height:100vh;display:flex;align-items:center;justify-content:center;font-family:sans-serif;'>RenClouds v5.0 - Web Berhasil Diperbaiki!</h1>";
?>
PHPEOF

# 3. SETUP NGINX (Kunci Utama Anti 403)
echo -e "${CYAN}[3/5] Setup Nginx (Fix Permission)...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; 
    index index.php index.html index.htm;
    
    # IZIN AKSES
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location /.well-known/assetlinks.json {
        default_type application/json;
        allow all;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
NGINXEOF

# 4. FIX IZIN & RESTART
echo -e "${CYAN}[4/5] Fix Permission & Restart Service...${NC}"
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
rm -f /etc/nginx/sites-enabled/default # Hapus default biar ga bentrok

# Kasih akses penuh ke www-data
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

nginx -t >/dev/null 2>&1 && systemctl reload nginx
systemctl restart php8.3-fpm

# 5. SELESAI
clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ WEB BERHASIL DIPERBAIKI!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 Coba buka domain lo sekarang:${NC}"
echo -e "   http://$DOMAIN"
echo ""
echo -e "${YELLOW}⚠️ Catatan:${NC}"
echo -e "   Script ini fokus benerin eror 403 (Nginx Permission)."
echo -e "   Begitu web kebuka, balikin file backup lo (kalau ada) atau jalanin script v4 buat Tools & Fitur."
