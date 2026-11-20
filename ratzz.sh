#!/bin/bash
# ==========================================
# 🎮 RenClouds v9.0 - PURE REMOTE CONTROLLER
# Fokus: Kontrol HP User via Web (Wallpaper, Senter, Getar, dll)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"
DB_USER="ren_user"
DB_PASS="renpassword123"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

echo -e "${CYAN}[1/4] Reset Database...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << SQLEOF
-- Tabel Admin
CREATE TABLE admins (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL);
INSERT INTO admins (username, password) VALUES ('admin', 'Ren11#');

-- Tabel User (Target)
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    device_id VARCHAR(100) UNIQUE NOT NULL, 
    device_name VARCHAR(100) DEFAULT 'Unknown',
    device_os VARCHAR(100) DEFAULT 'Unknown',
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Tabel Perintah (Command Queue)
CREATE TABLE user_commands (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    device_id VARCHAR(100), 
    command_type VARCHAR(50), 
    command_value TEXT, 
    status ENUM('pending','executed') DEFAULT 'pending', 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}✅ Database Siap${NC}"

echo -e "${CYAN}[2/4] Generate Web Files...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{api,assets}

# --- CONFIG ---
cat > "$WEB_ROOT/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', '127.0.0.1'); define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER'); define('DB_PASS', '$DB_PASS');
try { \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]); } catch (PDOException \$e) { die("DB Error"); }
function isAdmin() { return isset(\$_SESSION['admin']); }
function requireAdmin() { if(!isAdmin()) { header('Location: login.php'); exit; } }
PHPEOF

# --- CSS ---
cat > "$WEB_ROOT/style.css" << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600;800;900&display=swap');
@import url('https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css');
:root{--bg:#05080f;--card:#0f1a2e;--primary:#6366f1;--primary2:#8b5cf6;--success:#10b981;--danger:#ef4444;--warning:#f59e0b;--text:#f8fafc;--text-muted:#94a3b8;--border:#1e2a45;}
*{margin:0;padding:0;box-sizing:border-box;font-family:'Inter',sans-serif;}
body{background:var(--bg);color:var(--text);min-height:100vh;}
.container{max-width:1100px;margin:0 auto;padding:20px;}
.navbar{display:flex;justify-content:space-between;align-items:center;padding:15px 30px;background:rgba(5,8,15,.9);border-bottom:1px solid var(--border);}
.logo{font-size:1.4em;font-weight:900;display:flex;align-items:center;gap:10px;color:white;text-decoration:none;}
.card{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:30px;margin-bottom:20px;}
.form-group{margin-bottom:20px;}
label{display:block;margin-bottom:8px;font-size:.9em;color:var(--text-muted);}
input,textarea,select{width:100%;padding:15px;border-radius:12px;border:1px solid var(--border);background:rgba(0,0,0,.4);color:var(--text);outline:none;font-family:inherit;}
.btn{width:100%;padding:15px;border-radius:12px;border:none;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px;text-decoration:none;font-family:inherit;font-size:1em;color:white;}
.btn-primary{background:linear-gradient(135deg,var(--primary),var(--primary2));}
.btn-danger{background:linear-gradient(135deg,#ef4444,#dc2626);}
.btn-warning{background:linear-gradient(135deg,#f59e0b,#d97706);}
.btn-success{background:linear-gradient(135deg,#10b981,#059669);}
table{width:100%;border-collapse:collapse;}
th,td{padding:14px;text-align:left;border-bottom:1px solid var(--border);font-size:.9em;}
.badge{padding:5px 10px;border-radius:6px;font-size:.75em;font-weight:700;}
.badge-success{background:rgba(16,185,129,.2);color:var(--success);}
.alert{padding:15px;border-radius:10px;margin-bottom:20px;background:rgba(239,68,68,.2);color:#ef4444;}
.grid-tools{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin-top:20px;}
.tool-btn{padding:20px;border-radius:12px;background:var(--card);border:1px solid var(--border);text-align:center;cursor:pointer;transition:0.3s;}
.tool-btn:hover{border-color:var(--primary);background:rgba(99,102,241,0.1);}
.tool-btn i{font-size:2em;margin-bottom:10px;color:var(--primary);}
CSSEOF

# --- INDEX (LANDING PAGE USER) ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; ?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Device Controller</title><link rel="stylesheet" href="style.css"></head>
<body>
<nav class="navbar"><a href="#" class="logo"><i class="fas fa-mobile-alt" style="color:var(--primary)"></i><span>RenController</span></a></nav>
<div class="container" style="text-align:center;padding-top:50px;">
<div id="welcome" style="display:block;">
    <h1 style="font-size:2em;margin-bottom:20px;">Selamat Datang!</h1>
    <p style="color:var(--text-muted);margin-bottom:30px;">Website ini akan mendeteksi device kamu secara otomatis.</p>
    <div class="card" style="max-width:400px;margin:0 auto;">
        <p style="margin-bottom:20px;font-weight:bold;">Sedang mendeteksi device...</p>
        <div style="width:40px;height:40px;border:4px solid var(--border);border-top-color:var(--primary);border-radius:50%;animation:spin 1s linear infinite;margin:0 auto;"></div>
    </div>
</div>

<div id="status" style="display:none;">
    <div class="card" style="max-width:400px;margin:0 auto;border:1px solid var(--success);">
        <i class="fas fa-check-circle" style="font-size:3em;color:var(--success);margin-bottom:15px;"></i>
        <h2 style="margin-bottom:10px;">Device Terhubung!</h2>
        <p style="color:var(--text-muted);margin-bottom:15px;">Nama HP: <strong id="devName" style="color:white;"></strong></p>
        <p style="color:var(--text-muted);">OS: <strong id="devOs" style="color:white;"></strong></p>
        <p style="font-size:0.8em;color:var(--text-muted);margin-top:20px;"><i class="fas fa-info-circle"></i> Kamu bisa menutup halaman ini. Admin akan mengontrol HP kamu.</p>
    </div>
</div>
</div>

<style>@keyframes spin { 100% { transform: rotate(360deg); } }</style>

<script>
// DETEKSI DEVICE & KIRIM KE SERVER
function registerDevice(){
    let ua = navigator.userAgent;
    let devName = "Unknown", devOs = "Unknown";
    
    // Deteksi OS
    if (/android/i.test(ua)) { let m = ua.match(/Android\s([0-9\.]+)/); devOs = m ? "Android " + m[1] : "Android"; } 
    else if (/iPhone|iPad/i.test(ua)) devOs = "iOS";
    else if (/Windows/i.test(ua)) devOs = "Windows";

    // Deteksi Nama HP
    if (/SM-|Samsung/i.test(ua)) devName = "Samsung";
    else if (/Xiaomi|Redmi|POCO/i.test(ua)) devName = "Xiaomi/Redmi";
    else if (/OPPO/i.test(ua)) devName = "OPPO";
    else if (/vivo/i.test(ua)) devName = "Vivo";
    else if (/Realme/i.test(ua)) devName = "Realme";
    else if (/Infinix/i.test(ua)) devName = "Infinix";
    else if (/iPhone/i.test(ua)) devName = "Apple iPhone";
    else devName = ua.split(' ')[0] || "Unknown"; // Fallback

    // Generate Device ID (Simpan di LocalStorage)
    let devId = localStorage.getItem('ren_dev_id');
    if(!devId){
        devId = 'DEV-' + Math.random().toString(36).substr(2, 9).toUpperCase();
        localStorage.setItem('ren_dev_id', devId);
    }

    // Kirim ke API
    let fd = new FormData(); 
    fd.append("device_id", devId);
    fd.append("device_name", devName); 
    fd.append("device_os", devOs);
    
    fetch("api/register_device.php", { method: "POST", body: fd })
    .then(res => res.json())
    .then(data => {
        if(data.status){
            document.getElementById('welcome').style.display = 'none';
            document.getElementById('status').style.display = 'block';
            document.getElementById('devName').textContent = devName;
            document.getElementById('devOs').textContent = devOs;
            
            // Mulai dengerin perintah dari admin
            listenCommands(devId);
        }
    });
}

// LISTENER PERINTAH DARI ADMIN
function listenCommands(devId) {
    setInterval(async () => {
        try {
            let res = await fetch("api/get_command.php?device_id=" + devId);
            let data = await res.json();
            
            if (data.status) {
                let cmd = data.command;
                let val = data.value;
                let id = data.id;
                
                // Eksekusi perintah
                if (cmd === "wallpaper") {
                    if (window.AndroidInterface) window.AndroidInterface.setWallpaper(val);
                    else alert("Hanya jalan di APK! URL: " + val);
                } 
                else if (cmd === "flash_on") {
                    if (window.AndroidInterface) window.AndroidInterface.toggleFlashlight(true);
                    else alert("Hanya jalan di APK! (Senter ON)");
                }
                else if (cmd === "flash_off") {
                    if (window.AndroidInterface) window.AndroidInterface.toggleFlashlight(false);
                    else alert("Hanya jalan di APK! (Senter OFF)");
                }
                else if (cmd === "vibrate") {
                    if (window.AndroidInterface) window.AndroidInterface.vibrate(1500);
                    else alert("Hanya jalan di APK! (Getar)");
                }
                else if (cmd === "toast") {
                    if (window.AndroidInterface) window.AndroidInterface.showToast(val);
                    else alert("Hanya jalan di APK! (Pesan: " + val + ")");
                }

                // Tandai selesai
                let fd = new FormData(); fd.append("id", id);
                fetch("api/complete_command.php", { method: "POST", body: fd });
            }
        } catch(e) {}
    }, 5000); // Cek tiap 5 detik
}

window.addEventListener("load", registerDevice);
</script>
</body></html>
PHPEOF

# --- API REGISTER DEVICE ---
cat > "$WEB_ROOT/api/register_device.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json');
$devId = $_POST['device_id'] ?? '';
$name = $_POST['device_name'] ?? 'Unknown';
$os = $_POST['device_os'] ?? 'Unknown';
if(!$devId) { echo json_encode(["status"=>false]); exit; }

// Cek apa udah ada
$stmt = $pdo->prepare("SELECT id FROM users WHERE device_id=?"); $stmt->execute([$devId]);
if($stmt->fetch()){
    $pdo->prepare("UPDATE users SET device_name=?, device_os=?, last_active=NOW() WHERE device_id=?")->execute([$name, $os, $devId]);
} else {
    $pdo->prepare("INSERT INTO users (device_id, device_name, device_os) VALUES (?,?,?)")->execute([$devId, $name, $os]);
}
echo json_encode(["status"=>true, "message"=>"Device registered"]);
PHPEOF

# --- API COMMAND QUEUE ---
cat > "$WEB_ROOT/api/get_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json');
$devId = $_GET['device_id'] ?? '';
if(!$devId) { echo json_encode(["status"=>false]); exit; }
$stmt = $pdo->prepare("SELECT * FROM user_commands WHERE device_id=? AND status='pending' ORDER BY id ASC LIMIT 1");
$stmt->execute([$devId]); $cmd = $stmt->fetch();
if($cmd) echo json_encode(["status"=>true,"command"=>$cmd['command_type'],"value"=>$cmd['command_value'],"id"=>$cmd['id']]);
else echo json_encode(["status"=>false]);
PHPEOF

cat > "$WEB_ROOT/api/complete_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json');
$id = $_POST['id'] ?? 0;
if($id) $pdo->prepare("UPDATE user_commands SET status='executed' WHERE id=?")->execute([$id]);
echo json_encode(["status"=>true]);
PHPEOF

# --- ADMIN LOGIN ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php'; if($_SERVER['REQUEST_METHOD']=='POST'){$s=$pdo->prepare("SELECT * FROM admins WHERE username=? AND password=?");$s->execute([$_POST['u'],$_POST['p']]);if($s->fetch()){$_SESSION['admin']=true;header('Location:admin.php');exit;}else{$e="Gagal";}}
?><!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Admin</title><link rel="stylesheet" href="style.css"></head><body>
<div class="container" style="max-width:400px;margin-top:100px;"><div class="card">
<h2 style="text-align:center;"><i class="fas fa-shield-alt" style="color:var(--primary)"></i> Admin Login</h2>
<?php if(isset($e)) echo "<div class='alert'>$e</div>"; ?>
<form method="POST" style="margin-top:20px;"><div class="form-group"><input type="text" name="u" placeholder="Username" required></div><div class="form-group"><input type="password" name="p" placeholder="Password" required></div><button class="btn btn-primary">Login</button></form>
</div></div></body></html>
PHPEOF

# --- ADMIN PANEL (COMMAND CENTER) ---
cat > "$WEB_ROOT/admin.php" << 'PHPEOF'
<?php require 'config.php'; requireAdmin(); 
$users = $pdo->query("SELECT * FROM users ORDER BY last_active DESC")->fetchAll(); 
?>
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Admin Panel</title><link rel="stylesheet" href="style.css"></head><body>
<nav class="navbar"><a href="#" class="logo"><i class="fas fa-satellite-dish" style="color:var(--primary)"></i><span>Command Center</span></a><div class="nav-links"><a href="logout.php" style="color:var(--danger);text-decoration:none;font-weight:bold;">Logout</a></div></nav>
<div class="container">
<h2 style="margin-bottom:20px;">Connected Devices</h2>

<div class="card" style="margin-bottom:30px;">
    <table><tr><th>Device Name</th><th>OS</th><th>Last Active</th><th>Action</th></tr>
    <?php foreach($users as $u): ?>
    <tr>
        <td style="color:var(--success);font-weight:bold;"><?=htmlspecialchars($u['device_name'])?></td>
        <td><?=htmlspecialchars($u['device_os'])?></td>
        <td style="font-size:0.8em;color:var(--text-muted);"><?=date('H:i:s', strtotime($u['last_active']))?></td>
        <td><button class="btn btn-primary" style="width:auto;padding:5px 10px;font-size:0.8em;" onclick="selectDevice('<?=$u['device_id']?>', '<?=$u['device_name']?>')">Kontrol</button></td>
    </tr>
    <?php endforeach; ?>
    </table>
</div>

<div class="card" id="controlPanel" style="display:none; border:2px solid var(--primary);">
    <h3 style="margin-bottom:15px;">Kontrol Device: <span id="targetName" style="color:var(--primary);"></span></h3>
    <input type="hidden" id="targetId">
    
    <div class="grid-tools">
        <div class="tool-btn" onclick="sendCmd('flash_on')"><i class="fas fa-lightbulb"></i><br>Senter ON</div>
        <div class="tool-btn" onclick="sendCmd('flash_off')"><i class="fas fa-lightbulb" style="color:#555"></i><br>Senter OFF</div>
        <div class="tool-btn" onclick="sendCmd('vibrate')"><i class="fas fa-mobile"></i><br>Getarkan HP</div>
        <div class="tool-btn" onclick="promptToast()"><i class="fas fa-comment-dots"></i><br>Kirim Pesan</div>
    </div>

    <div style="margin-top:20px; border-top:1px solid var(--border); padding-top:20px;">
        <h4 style="margin-bottom:10px;">Ganti Wallpaper</h4>
        <div style="display:flex;gap:10px;">
            <input type="url" id="wpUrl" placeholder="https://contoh.com/gambar.jpg" style="flex:1;">
            <button class="btn btn-success" style="width:auto;" onclick="sendWallpaper()">Ganti</button>
        </div>
    </div>
</div>

</div>
<script>
function selectDevice(id, name) {
    document.getElementById('targetId').value = id;
    document.getElementById('targetName').textContent = name;
    document.getElementById('controlPanel').style.display = 'block';
    window.scrollTo(0, document.body.scrollHeight);
}
async function sendCmd(type, value = '') {
    let id = document.getElementById('targetId').value;
    if(!id) return alert('Pilih device dulu!');
    let fd = new FormData(); fd.append('device_id', id); fd.append('type', type); fd.append('value', value);
    let res = await fetch('api/send_command.php', { method:'POST', body:fd });
    let d = await res.json(); alert(d.message);
}
function sendWallpaper() {
    let url = document.getElementById('wpUrl').value;
    if(!url) return alert('Isi URL gambar!');
    sendCmd('wallpaper', url);
}
function promptToast() {
    let msg = prompt("Masukkan pesan untuk HP user:");
    if(msg) sendCmd('toast', msg);
}
</script>
</body></html>
PHPEOF

# --- API SEND COMMAND (ADMIN) ---
cat > "$WEB_ROOT/api/send_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isAdmin()) exit;
$devId = $_POST['device_id'] ?? 0; $type = $_POST['type'] ?? ''; $val = $_POST['value'] ?? '';
if($devId && $type){ $pdo->prepare("INSERT INTO user_commands(device_id,command_type,command_value)VALUES(?,?,?)")->execute([$devId,$type,$val]); echo json_encode(["status"=>true,"message"=>"Perintah terkirim!"]); } else echo json_encode(["status"=>false]);
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF

echo -e "${CYAN}[3/4] Setup Nginx...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; }
}
NGINXEOF
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
chown -R www-data:www-data "$WEB_ROOT"
systemctl reload nginx
systemctl restart php8.3-fpm

echo -e "${GREEN}✅ Web v9.0 (Pure Controller) Siap!${NC}"
echo -e "Admin: /login.php (admin / Ren11#)"
