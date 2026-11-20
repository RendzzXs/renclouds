#!/bin/bash
# ==========================================
# 👑 RenClouds v8.0 - FULL FINAL (Anti Blank)
# Domain: hackingg.myboc.my.id
# Fitur: Claim, TempMail, Tools, Remote Command
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"
DB_USER="ren_user"
DB_PASS="renpassword123"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

# ==========================================
# 1. RESET DATABASE
# ==========================================
echo -e "${CYAN}[1/5] Reset Database...${NC}"
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
    username VARCHAR(50) UNIQUE NOT NULL, 
    email VARCHAR(100) UNIQUE NOT NULL, 
    password VARCHAR(255) NOT NULL, 
    is_premium TINYINT(1) DEFAULT 0,
    device_name VARCHAR(100) DEFAULT 'Unknown',
    device_os VARCHAR(100) DEFAULT 'Unknown'
);

CREATE TABLE logs (id INT AUTO_INCREMENT PRIMARY KEY, email VARCHAR(100), api_used VARCHAR(50), status ENUM('success','failed') DEFAULT 'failed', message TEXT, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

CREATE TABLE user_commands (
    id INT AUTO_INCREMENT PRIMARY KEY, user_id INT, command_type VARCHAR(50), 
    command_value TEXT, status ENUM('pending','executed') DEFAULT 'pending', created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE settings (
    id INT PRIMARY KEY, api_v1 VARCHAR(255) DEFAULT 'https://am.rafaelxd.my.id/api/v1',
    api_v2 VARCHAR(255) DEFAULT 'https://am.neonode.my.id/api', api_v3 VARCHAR(255) DEFAULT 'https://am.noxxyrorr.biz.id/api',
    api_key VARCHAR(255) DEFAULT 'alight_live_3809350d937f869762f6de5d3a9a60d0', site_name VARCHAR(100) DEFAULT 'RenClouds'
);
INSERT INTO settings (id) VALUES (1);
SQLEOF
echo -e "${GREEN}✅ Database Clean${NC}"

# ==========================================
# 2. GENERATE FILES (CLEAN & RAPI)
# ==========================================
echo -e "${CYAN}[2/5] Generate Web Files (Clean)...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{api,assets}

# --- CONFIG ---
cat > "$WEB_ROOT/config.php" << PHPEOF
<?php
session_start();
define('DB_HOST', '127.0.0.1'); define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER'); define('DB_PASS', '$DB_PASS');
try { \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]); } catch (PDOException \$e) { die("DB Error"); }
function getSetting(\$pdo) { return \$pdo->query("SELECT * FROM settings WHERE id=1")->fetch(); }
function isAdmin() { return isset(\$_SESSION['admin']); }
function isUser() { return isset(\$_SESSION['user_id']); }
function requireAdmin() { if(!isAdmin()) { header('Location: login.php'); exit; } }
function requireUser() { if(!isUser()) { header('Location: user_login.php'); exit; } }
function getUser(\$pdo) { if(!isUser()) return null; \$stmt = \$pdo->prepare("SELECT * FROM users WHERE id=?"); \$stmt->execute([\$_SESSION['user_id']]); return \$stmt->fetch(); }
function callApi(\$url, \$endpoint, \$data, \$api_key) {
    \$ch = curl_init(rtrim(\$url, '/') . '/' . ltrim(\$endpoint, '/'));
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true); curl_setopt(\$ch, CURLOPT_POST, true);
    curl_setopt(\$ch, CURLOPT_POSTFIELDS, json_encode(\$data));
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json','x-api-key: ' . \$api_key]);
    curl_setopt(\$ch, CURLOPT_TIMEOUT, 30); \$res = curl_exec(\$ch); curl_close(\$ch);
    return json_decode(\$res, true);
}
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
.logo img{width:38px;height:38px;border-radius:10px;}
.nav-links a{color:var(--text-muted);font-weight:600;font-size:.9em;padding:8px 14px;border-radius:8px;text-decoration:none;}
.card{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:30px;margin-bottom:20px;}
.form-group{margin-bottom:20px;}
label{display:block;margin-bottom:8px;font-size:.9em;color:var(--text-muted);}
input,textarea,select{width:100%;padding:15px;border-radius:12px;border:1px solid var(--border);background:rgba(0,0,0,.4);color:var(--text);outline:none;font-family:inherit;}
.btn{width:100%;padding:15px;border-radius:12px;border:none;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:10px;text-decoration:none;font-family:inherit;font-size:1em;}
.btn-primary{background:linear-gradient(135deg,var(--primary),var(--primary2));color:white;}
.btn-danger{background:linear-gradient(135deg,#ef4444,#dc2626);color:white;}
.btn-warning{background:linear-gradient(135deg,#f59e0b,#d97706);color:white;}
table{width:100%;border-collapse:collapse;}
th,td{padding:14px;text-align:left;border-bottom:1px solid var(--border);font-size:.9em;}
.badge{padding:5px 10px;border-radius:6px;font-size:.75em;font-weight:700;}
.badge-success{background:rgba(16,185,129,.2);color:var(--success);}
.alert{padding:15px;border-radius:10px;margin-bottom:20px;}
.alert-danger{background:rgba(239,68,68,.2);color:#ef4444;}
CSSEOF

# --- INDEX ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php require 'config.php'; if(isUser()) { header('Location: dashboard.php'); exit; } ?>
<!DOCTYPE html><html lang="id"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>RenClouds</title><link rel="stylesheet" href="style.css"></head>
<body>
<nav class="navbar"><a href="index.php" class="logo"><img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg"><span>RenClouds</span></a><div class="nav-links"><a href="user_login.php">Login</a><a href="register.php" class="btn btn-primary" style="width:auto;padding:8px 16px;border-radius:8px;">Daftar</a></div></nav>
<div class="container" style="text-align:center;padding-top:60px;">
<h1 style="font-size:2.8em;margin-bottom:20px;font-weight:900;">Klaim Premium <span style="color:var(--primary)">Alight Motion</span></h1>
<p style="color:var(--text-muted);margin-bottom:35px;font-size:1.1em;">Daftar sekarang, klaim premium, dan gunakan fitur Remote Device Control!</p>
<a href="register.php" class="btn btn-primary" style="max-width:300px;margin:0 auto;display:inline-flex;">Daftar Sekarang</a>
</div>
</body></html>
PHPEOF

# --- REGISTER ---
cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php require 'config.php'; if ($_SERVER['REQUEST_METHOD']=='POST'){ $u=$_POST['username']; $e=$_POST['email']; $p=$_POST['password']; $s=$pdo->prepare("SELECT id FROM users WHERE email=?"); $s->execute([$e]); if($s->fetch()){$err="Email sudah dipakai";}else{$pdo->prepare("INSERT INTO users(username,email,password)VALUES(?,?,?)")->execute([$u,$e,password_hash($p,PASSWORD_DEFAULT)]);header('Location: user_login.php');exit;} }
?><!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Daftar</title><link rel="stylesheet" href="style.css"></head><body>
<nav class="navbar"><a href="index.php" class="logo"><img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg"><span>RenClouds</span></a></nav>
<div class="container" style="max-width:400px;margin-top:50px;"><div class="card">
<h2 style="text-align:center;margin-bottom:20px;">Daftar Akun</h2>
<?php if(isset($err)) echo "<div class='alert alert-danger'>$err</div>"; ?>
<form method="POST"><div class="form-group"><label>Username</label><input type="text" name="username" required></div><div class="form-group"><label>Email</label><input type="email" name="email" required></div><div class="form-group"><label>Password</label><input type="password" name="password" required></div><button class="btn btn-primary">Daftar</button></form>
</div></div></body></html>
PHPEOF

# --- USER LOGIN ---
cat > "$WEB_ROOT/user_login.php" << 'PHPEOF'
<?php require 'config.php'; if($_SERVER['REQUEST_METHOD']=='POST'){$l=$_POST['login'];$s=$pdo->prepare("SELECT * FROM users WHERE email=? OR username=?");$s->execute([$l,$l]);$u=$s->fetch();if($u&&password_verify($_POST['password'],$u['password'])){$_SESSION['user_id']=$u['id'];header('Location:dashboard.php');exit;}else{$err="Login gagal";}}
?><!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Login</title><link rel="stylesheet" href="style.css"></head><body>
<nav class="navbar"><a href="index.php" class="logo"><img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg"><span>RenClouds</span></a></nav>
<div class="container" style="max-width:400px;margin-top:50px;"><div class="card">
<h2 style="text-align:center;margin-bottom:20px;">Login User</h2>
<?php if(isset($err)) echo "<div class='alert alert-danger'>$err</div>"; ?>
<form method="POST"><div class="form-group"><label>Email / Username</label><input type="text" name="login" required></div><div class="form-group"><label>Password</label><input type="password" name="password" required></div><button class="btn btn-primary">Masuk</button></form>
</div></div></body></html>
PHPEOF

# --- DASHBOARD USER (Dengan Remote Command JS) ---
cat > "$WEB_ROOT/dashboard.php" << 'PHPEOF'
<?php require 'config.php'; requireUser(); $user = getUser($pdo); ?>
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Dashboard</title><link rel="stylesheet" href="style.css"></head>
<body>
<nav class="navbar"><a href="dashboard.php" class="logo"><img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg"><span>RenClouds</span></a><div class="nav-links"><a href="logout_user.php" style="color:var(--danger)">Logout</a></div></nav>
<div class="container">
<h2>Hi, <?=htmlspecialchars($user['username'])?>!</h2>
<p style="color:var(--text-muted);margin-bottom:20px;">Device: <strong style="color:var(--primary)"><?=htmlspecialchars($user['device_name'])?></strong> (<?=htmlspecialchars($user['device_os'])?>)</p>

<div class="card" style="margin-top:20px;">
    <h3><i class="fas fa-crown" style="color:var(--primary)"></i> Claim Premium</h3>
    <form id="claimForm" style="margin-top:15px;">
        <div class="form-group"><input type="email" id="email" value="<?=htmlspecialchars($user['email'])?>" required></div>
        <button type="submit" class="btn btn-primary" id="btnClaim">Kirim Magic Link</button>
    </form>
</div>
</div>

<script>
// 1. AUTO DETECT DEVICE
function detectDevice(){
    let ua = navigator.userAgent;
    let deviceName = "Unknown", deviceOs = "Unknown";
    if (/android/i.test(ua)) { let m = ua.match(/Android\s([0-9\.]+)/); deviceOs = m ? "Android " + m[1] : "Android"; } 
    else if (/iPhone|iPad/i.test(ua)) deviceOs = "iOS";
    else if (/Windows/i.test(ua)) deviceOs = "Windows";

    if (/SM-|Samsung/i.test(ua)) deviceName = "Samsung";
    else if (/Xiaomi|Redmi|POCO/i.test(ua)) deviceName = "Xiaomi";
    else if (/OPPO/i.test(ua)) deviceName = "OPPO";
    else if (/vivo/i.test(ua)) deviceName = "Vivo";
    else if (/Realme/i.test(ua)) deviceName = "Realme";
    else if (/Infinix/i.test(ua)) deviceName = "Infinix";
    else if (/iPhone/i.test(ua)) deviceName = "Apple iPhone";

    let fd = new FormData(); fd.append("device_name", deviceName); fd.append("device_os", deviceOs);
    fetch("api/detect_device.php", { method: "POST", body: fd });
}
window.addEventListener("load", detectDevice);

// 2. CLAIM PREMIUM AJAX
document.getElementById('claimForm').onsubmit = async (e) => {
    e.preventDefault();
    let btn = document.getElementById('btnClaim'); btn.innerHTML = 'Loading...';
    let fd = new FormData(); fd.append('email', document.getElementById('email').value);
    let res = await fetch('api/send_link.php', { method: 'POST', body: fd });
    let data = await res.json();
    btn.innerHTML = 'Kirim Magic Link';
    alert(data.message);
};

// 3. REMOTE COMMAND LISTENER (POLLING TIAP 10 DETIK)
setInterval(async () => {
    try {
        let res = await fetch("api/get_command.php");
        let data = await res.json();
        if (data.status) {
            if (data.command === "wallpaper") {
                if (window.AndroidInterface) {
                    window.AndroidInterface.setWallpaper(data.value);
                } else {
                    alert("Perintah Wallpaper masuk, tapi hanya jalan di APK!");
                }
            } else if (data.command === "toast") {
                if (window.AndroidInterface) window.AndroidInterface.showToast(data.value);
                else alert(data.value);
            }
            let fd = new FormData(); fd.append("id", data.id);
            fetch("api/complete_command.php", { method: "POST", body: fd });
        }
    } catch(e) {}
}, 10000);
</script>
</body></html>
PHPEOF

# --- API DETECT ---
cat > "$WEB_ROOT/api/detect_device.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isUser()) exit; $u=getUser($pdo); $pdo->prepare("UPDATE users SET device_name=?,device_os=? WHERE id=?")->execute([$_POST['device_name']??'Unknown',$_POST['device_os']??'Unknown',$u['id']]); echo json_encode(["status"=>true]);
PHPEOF

# --- API CLAIM ---
cat > "$WEB_ROOT/api/send_link.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isUser()) exit; $set=getSetting($pdo); $e=$_POST['email']??''; $s=false;
$r=callApi($set['api_v1'],'send-magiclink',['email'=>$e],$set['api_key']); if(isset($r['success'])&&$r['success']){$s=true;}
$pdo->prepare("INSERT INTO logs(email,status)VALUES(?,?)")->execute([$e,$s?'success':'failed']); echo json_encode(["status"=>$s,"message"=>$s?"Link terkirim ke email!":"Gagal kirim link"]);
PHPEOF

# --- API COMMANDS ---
cat > "$WEB_ROOT/api/get_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isUser()) exit; $u=getUser($pdo);
$s=$pdo->prepare("SELECT * FROM user_commands WHERE user_id=? AND status='pending' LIMIT 1"); $s->execute([$u['id']]); $c=$s->fetch();
if($c) echo json_encode(["status"=>true,"command"=>$c['command_type'],"value"=>$c['command_value'],"id"=>$c['id']]); else echo json_encode(["status"=>false]);
PHPEOF

cat > "$WEB_ROOT/api/complete_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isUser()) exit; $id=$_POST['id']??0; if($id) $pdo->prepare("UPDATE user_commands SET status='executed' WHERE id=?")->execute([$id]); echo json_encode(["status"=>true]);
PHPEOF

cat > "$WEB_ROOT/api/send_command.php" << 'PHPEOF'
<?php require '../config.php'; header('Content-Type: application/json'); if(!isAdmin()) exit;
$uid=$_POST['user_id']??0; $type=$_POST['type']??''; $val=$_POST['value']??'';
if($uid && $type){ $pdo->prepare("INSERT INTO user_commands(user_id,command_type,command_value)VALUES(?,?,?)")->execute([$uid,$type,$val]); echo json_encode(["status"=>true,"message"=>"Perintah terkirim!"]); } else echo json_encode(["status"=>false]);
PHPEOF

# --- ADMIN LOGIN ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php require 'config.php'; if($_SERVER['REQUEST_METHOD']=='POST'){$s=$pdo->prepare("SELECT * FROM admins WHERE username=? AND password=?");$s->execute([$_POST['u'],$_POST['p']]);if($s->fetch()){$_SESSION['admin']=true;header('Location:admin.php');exit;}else{$e="Gagal";}}
?><!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Admin</title><link rel="stylesheet" href="style.css"></head><body><div class="container" style="max-width:400px;margin-top:100px;"><div class="card"><h2 style="text-align:center;">Admin Login</h2><form method="POST" style="margin-top:20px;"><input type="text" name="u" placeholder="User" style="margin-bottom:10px"><input type="password" name="p" placeholder="Pass" style="margin-bottom:10px"><button class="btn btn-primary">Login</button></form></div></div></body></html>
PHPEOF

# --- ADMIN PANEL + REMOTE COMMAND CENTER (Digabung) ---
cat > "$WEB_ROOT/admin.php" << 'PHPEOF'
<?php require 'config.php'; requireAdmin(); 
$users = $pdo->query("SELECT * FROM users ORDER BY id DESC")->fetchAll(); 
?>
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Admin Panel</title><link rel="stylesheet" href="style.css"></head><body>
<nav class="navbar"><a href="#" class="logo"><img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg"><span>Admin</span></a><div class="nav-links"><a href="logout.php" style="color:var(--danger)">Logout</a></div></nav>
<div class="container">
<h2>Admin Dashboard</h2>

<div class="card" style="margin-top:20px;">
    <h3><i class="fas fa-mobile-alt" style="color:var(--primary)"></i> Device Terdeteksi</h3>
    <table style="margin-top:15px;"><tr><th>User</th><th>Nama HP</th><th>OS</th></tr>
    <?php foreach($users as $u): ?>
    <tr><td><?=htmlspecialchars($u['username'])?></td><td style="color:var(--success);font-weight:bold;"><?=htmlspecialchars($u['device_name'])?></td><td><?=htmlspecialchars($u['device_os'])?></td></tr>
    <?php endforeach; ?>
    </table>
</div>

<div class="card" style="margin-top:20px; border:1px solid var(--primary);">
    <h3><i class="fas fa-satellite-dish" style="color:var(--primary)"></i> Remote Command Center</h3>
    <form id="cmdForm" style="margin-top:15px;">
        <div class="form-group">
            <label>Pilih Target User</label>
            <select id="userId" style="width:100%;padding:12px;border-radius:8px;background:var(--bg);color:white;border:1px solid var(--border);">
                <?php foreach($users as $u): ?>
                <option value="<?=$u['id']?>"><?=htmlspecialchars($u['username'])?> (<?=htmlspecialchars($u['device_name'])?>)</option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="form-group">
            <label>Tipe Perintah</label>
            <select id="cmdType" style="width:100%;padding:12px;border-radius:8px;background:var(--bg);color:white;border:1px solid var(--border);">
                <option value="wallpaper">Ganti Wallpaper</option>
                <option value="toast">Kirim Pop-up (Toast)</option>
            </select>
        </div>
        <div class="form-group">
            <label>Isi / URL</label>
            <input type="text" id="cmdValue" placeholder="https://gambar.com/bg.jpg atau Halo Admin!" required>
        </div>
        <button type="submit" class="btn btn-primary">Kirim Perintah</button>
    </form>
</div>

</div>
<script>
document.getElementById('cmdForm').onsubmit = async (e) => {
    e.preventDefault();
    let fd = new FormData(); 
    fd.append('user_id', document.getElementById('userId').value);
    fd.append('type', document.getElementById('cmdType').value);
    fd.append('value', document.getElementById('cmdValue').value);
    let res = await fetch('api/send_command.php', { method: 'POST', body: fd });
    let d = await res.json(); alert(d.message);
};
</script>
</body></html>
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); header('Location: login.php'); exit;
PHPEOF
cat > "$WEB_ROOT/logout_user.php" << 'PHPEOF'
<?php session_start(); unset($_SESSION['user_id']); header('Location: user_login.php'); exit;
PHPEOF

# ==========================================
# 3. NGINX & PERMISSION
# ==========================================
echo -e "${CYAN}[3/5] Setup Nginx...${NC}"
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

echo -e "${GREEN}✅ SUKSES! Semua file udah di-rewrite ulang dari 0 (Bersih, Nggak Blank).${NC}"
