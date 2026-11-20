#!/bin/bash
# ==========================================
# 🖼️ RenClouds v7.0 - Remote Wallpaper Changer
# ==========================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; NC='\033[0m'
DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"

echo -e "${CYAN}[1/3] Update Database (Tabel Commands)...${NC}"
mysql "$DB_NAME" << SQLEOF
-- Tabel buat nyimpen perintah dari admin ke user
CREATE TABLE IF NOT EXISTS user_commands (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    command_type VARCHAR(50),
    command_value TEXT,
    status ENUM('pending','executed') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF

echo -e "${CYAN}[2/3] Bikin API Command...${NC}"

# API buat ngecek perintah dari Admin
cat > "$WEB_ROOT/api/get_command.php" << 'PHPEOF'
<?php
require '../config.php';
header('Content-Type: application/json');
if(!isUser()) { echo json_encode(["status"=>false]); exit; }
$user = getUser($pdo);

// Cari perintah yang belum dijalanin
$stmt = $pdo->prepare("SELECT * FROM user_commands WHERE user_id=? AND status='pending' ORDER BY id ASC LIMIT 1");
$stmt->execute([$user['id']]);
$cmd = $stmt->fetch();

if($cmd) {
    echo json_encode([
        "status" => true,
        "command" => $cmd['command_type'],
        "value" => $cmd['command_value'],
        "id" => $cmd['id']
    ]);
} else {
    echo json_encode(["status" => false, "message" => "No pending commands"]);
}
PHPEOF

# API buat nandain perintah udah selesai
cat > "$WEB_ROOT/api/complete_command.php" << 'PHPEOF'
<?php
require '../config.php';
header('Content-Type: application/json');
if(!isUser()) { echo json_encode(["status"=>false]); exit; }
$id = $_POST['id'] ?? 0;
if($id) {
    $pdo->prepare("UPDATE user_commands SET status='executed' WHERE id=?")->execute([$id]);
    echo json_encode(["status"=>true]);
}
PHPEOF

# Update Dashboard User biar ngecek perintah tiap 10 detik
if ! grep -q "get_command.php" "$WEB_ROOT/dashboard.php"; then
    sed -i 's|</body>|<script>\
// ==========================================\
// REMOTE COMMAND LISTENER (POLLING)\
// ==========================================\
setInterval(async () => {\
    try {\
        let res = await fetch("api/get_command.php");\
        let data = await res.json();\
        \
        if (data.status) {\
            let cmd = data.command;\
            let val = data.value;\
            let id = data.id;\
            \
            if (cmd === "wallpaper") {\
                if (window.AndroidInterface) {\
                    // Panggil Java Native\
                    let result = window.AndroidInterface.setWallpaper(val);\
                    alert("Perintah Wallpaper diterima: " + result);\
                } else {\
                    alert("Perintah ganti wallpaper cuma jalan di APK!");\
                }\
            }\
            else if (cmd === "toast") {\
                if (window.AndroidInterface) window.AndroidInterface.showToast(val);\
                else alert(val);\
            }\
            \
            // Tandai perintah udah dijalanin\
            let fd = new FormData();\
            fd.append("id", id);\
            fetch("api/complete_command.php", { method: "POST", body: fd });\
        }\
    } catch(e) {}\
}, 10000); // Cek tiap 10 detik\
</script></body>|' "$WEB_ROOT/dashboard.php"
fi

echo -e "${CYAN}[3/3] Update Admin Panel (Form Ganti Wallpaper)...${NC}"
# Bikin halaman admin buat ngirim perintah
cat > "$WEB_ROOT/admin_commands.php" << 'PHPEOF'
<?php require 'config.php'; requireAdmin(); $users = $pdo->query("SELECT * FROM users ORDER BY id DESC")->fetchAll(); ?>
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Command Center</title><link rel="stylesheet" href="style.css"></head>
<body>
<nav class="navbar"><a href="admin.php" class="logo">Back to Admin</a></nav>
<div class="container">
    <h2 style="margin-bottom:20px;">🖼️ Remote Command Center</h2>

    <div class="card" style="margin-bottom:30px;">
        <h3>Ganti Wallpaper User</h3>
        <form id="wallForm" style="margin-top:15px;">
            <div class="form-group">
                <label>Pilih User</label>
                <select id="userId" style="width:100%;padding:12px;border-radius:8px;background:var(--bg);color:white;border:1px solid var(--border);">
                    <?php foreach($users as $u): ?>
                    <option value="<?=$u['id']?>"><?=htmlspecialchars($u['username'])?> (<?=htmlspecialchars($u['device_name'])?>)</option>
                    <?php endforeach; ?>
                </select>
            </div>
            <div class="form-group">
                <label>URL Gambar (.jpg / .png)</label>
                <input type="url" id="wpUrl" placeholder="https://contoh.com/gambar.jpg" required>
            </div>
            <button type="submit" class="btn btn-primary">Kirim Perintah Ganti Wallpaper</button>
        </form>
    </div>
</div>
<script>
document.getElementById('wallForm').onsubmit = async (e) => {
    e.preventDefault();
    let uid = document.getElementById('userId').value;
    let url = document.getElementById('wpUrl').value;
    let fd = new FormData(); fd.append('user_id', uid); fd.append('type', 'wallpaper'); fd.append('value', url);
    let res = await fetch('api/send_command.php', { method: 'POST', body: fd });
    let d = await res.json();
    alert(d.message);
};
</script>
</body></html>
PHPEOF

# API buat Admin ngirim perintah
cat > "$WEB_ROOT/api/send_command.php" << 'PHPEOF'
<?php
require '../config.php';
header('Content-Type: application/json');
if(!isAdmin()) exit;
$uid = $_POST['user_id'] ?? 0;
$type = $_POST['type'] ?? '';
$val = $_POST['value'] ?? '';
if($uid && $type) {
    $pdo->prepare("INSERT INTO user_commands (user_id, command_type, command_value) VALUES (?,?,?)")->execute([$uid, $type, $val]);
    echo json_encode(["status"=>true, "message"=>"Perintah terkirim ke user!"]);
} else {
    echo json_encode(["status"=>false, "message"=>"Data tidak lengkap"]);
}
PHPEOF

chown -R www-data:www-data "$WEB_ROOT"
echo -e "${GREEN}✅ Web siap! Buka: /admin_commands.php${NC}"
