#!/bin/bash
# ==========================================
# 🛠️ UPDATE: RenClouds v4.0 - TWA AssetLinks + Tools Hub
# Jalankan di server yang SUDAH terinstall RenClouds
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; WHITE='\033[1;37m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

read -p "👉 Masukkan Domain (contoh: am.domainkamu.com): " DOMAIN
read -p "👉 Package Name APK (contoh: com.renclouds.app): " PKG_NAME
read -p "👉 SHA256 Fingerprint APK (kosongkan jika belum build): " FINGERPRINT
[[ -z "$FINGERPRINT" ]] && FINGERPRINT="00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"

WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="renclouds_db"

# ==========================================
# 1. UPDATE DATABASE (Tabel AssetLinks + Tools Settings)
# ==========================================
echo -e "${CYAN}[1/4] Update Database...${NC}"
mysql "$DB_NAME" << SQLEOF
ALTER TABLE settings ADD COLUMN IF NOT EXISTS apk_package VARCHAR(100) DEFAULT '$PKG_NAME';
ALTER TABLE settings ADD COLUMN IF NOT EXISTS apk_fingerprint VARCHAR(200) DEFAULT '$FINGERPRINT';
ALTER TABLE settings ADD COLUMN IF NOT EXISTS tools_enabled TINYINT(1) DEFAULT 1;
ALTER TABLE settings ADD COLUMN IF NOT EXISTS fcm_server_key VARCHAR(255) DEFAULT '';

CREATE TABLE IF NOT EXISTS tools_usage (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    tool_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQLEOF
echo -e "${GREEN}  ✅ DB Updated${NC}"

# ==========================================
# 2. AUTO-GENERATE assetlinks.json
# ==========================================
echo -e "${CYAN}[2/4] Setup AssetLinks (TWA Verification)...${NC}"

mkdir -p "$WEB_ROOT/.well-known"
cat > "$WEB_ROOT/.well-known/assetlinks.json" << EOF
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "$PKG_NAME",
    "sha256_cert_fingerprints": ["$FINGERPRINT"]
  }
}]
EOF

# Update Nginx untuk allow .well-known
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
if ! grep -q "assetlinks.json" "$NGINX_CONF"; then
    sed -i '/location ~ \/\\.ht/i\    location /.well-known/assetlinks.json {\n        default_type application/json;\n        allow all;\n    }' "$NGINX_CONF"
    nginx -t >/dev/null 2>&1 && systemctl reload nginx
fi

# ==========================================
# 3. BIKIN HALAMAN TOOLS HUB
# ==========================================
echo -e "${CYAN}[3/4] Generate Tools Hub Page...${NC}"

# --- TOOLS.PHP ---
cat > "$WEB_ROOT/tools.php" << 'PHPEOF'
<?php require 'config.php'; requireUser();
$set = getSetting($pdo);
$user = getUser($pdo);
if(!$set['tools_enabled']){ header('Location: dashboard.php'); exit; }
?>
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tools Hub - <?= htmlspecialchars($set['site_name']) ?></title>
<link rel="stylesheet" href="style.css">
<style>
.tools-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:15px;margin-top:20px;}
.tool-card{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:20px;text-align:center;cursor:pointer;transition:.3s;position:relative;overflow:hidden;}
.tool-card:hover{border-color:var(--primary);transform:translateY(-4px);box-shadow:0 10px 30px rgba(99,102,241,.3);}
.tool-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px;background:linear-gradient(90deg,var(--primary),var(--primary2));opacity:0;transition:.3s;}
.tool-card:hover::before{opacity:1;}
.tool-icon{width:55px;height:55px;border-radius:14px;display:flex;align-items:center;justify-content:center;font-size:1.5em;margin:0 auto 12px;background:rgba(99,102,241,.15);color:var(--primary);}
.tool-card h4{font-size:.9em;font-weight:700;margin-bottom:5px;}
.tool-card p{font-size:.75em;color:var(--text-muted);line-height:1.4;}
.tool-modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.85);z-index:9999;align-items:center;justify-content:center;padding:20px;}
.tool-modal.active{display:flex;}
.tool-modal-content{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:25px;max-width:500px;width:100%;max-height:85vh;overflow-y:auto;}
.tool-modal-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;}
.tool-modal-header h3{font-size:1.2em;}
.tool-modal-close{background:none;border:none;color:var(--text-muted);font-size:1.8em;cursor:pointer;line-height:1;}
.app-badge{display:inline-flex;align-items:center;gap:6px;background:rgba(16,185,129,.15);color:var(--success);padding:5px 12px;border-radius:50px;font-size:.75em;font-weight:700;margin-bottom:15px;}
.output-box{background:rgba(0,0,0,.5);border:1px solid var(--border);border-radius:10px;padding:15px;font-family:monospace;font-size:.85em;margin-top:15px;word-break:break-all;color:var(--success);min-height:50px;}
</style>
</head>
<body>
<?php include 'pwa-init.php'; ?>

<nav class="navbar">
    <a href="dashboard.php" class="logo">
        <img src="https://h.uguu.se/OTWLMWKtuAMa.jpeg" alt="Logo">
        <span>RenClouds</span>
    </a>
    <div class="nav-links">
        <a href="dashboard.php"><i class="fas fa-home"></i> Home</a>
        <a href="logout_user.php" style="color:var(--danger);"><i class="fas fa-sign-out-alt"></i> Logout</a>
    </div>
</nav>

<div class="container" style="max-width:900px;">
    <div style="text-align:center;padding:25px 0;">
        <div class="app-badge"><i class="fas fa-mobile-alt"></i> APK Mode Active</div>
        <h1 style="font-size:1.8em;font-weight:900;margin-bottom:8px;">🛠️ <span style="background:linear-gradient(135deg,var(--primary),var(--primary2));-webkit-background-clip:text;-webkit-text-fill-color:transparent;">Tools Hub</span></h1>
        <p style="color:var(--text-muted);font-size:.95em;">Kumpulan tools bermanfaat khusus pengguna APK RenClouds</p>
    </div>

    <div class="tools-grid" id="toolsGrid"></div>

    <div style="text-align:center;margin:40px 0;color:var(--text-muted);font-size:.85em;">
        <i class="fas fa-info-circle"></i> Tools khusus tersedia saat dibuka melalui APK RenClouds
    </div>
</div>

<!-- MODAL -->
<div class="tool-modal" id="toolModal">
    <div class="tool-modal-content">
        <div class="tool-modal-header">
            <h3 id="toolTitle">Tool</h3>
            <button class="tool-modal-close" onclick="closeToolModal()">&times;</button>
        </div>
        <div id="toolBody"></div>
    </div>
</div>

<script>
// ============ DETEKSI APK / TWA ============
function isInAPK() {
    return document.referrer.includes('android-app://') ||
           window.matchMedia('(display-mode: standalone)').matches ||
           navigator.standalone === true ||
           /wv|TWA/.test(navigator.userAgent);
}
if (!isInAPK()) {
    // Kalau buka di browser biasa, tetap boleh akses tapi kasih hint
    console.log('Buka via APK untuk pengalaman penuh');
}

// ============ DAFTAR TOOLS ============
const tools = [
    { id: 'qr', name: 'QR Generator', icon: 'fa-qrcode', desc: 'Buat QR code dari teks/link', category: 'utility' },
    { id: 'shortlink', name: 'Short Link', icon: 'fa-link', desc: 'Pendekkan URL panjang', category: 'utility' },
    { id: 'password', name: 'PW Generator', icon: 'fa-key', desc: 'Bikin password kuat', category: 'security' },
    { id: 'base64', name: 'Base64', icon: 'fa-code', desc: 'Encode/decode base64', category: 'developer' },
    { id: 'uuid', name: 'UUID Gen', icon: 'fa-fingerprint', desc: 'Generate UUID v4', category: 'developer' },
    { id: 'random', name: 'Random Number', icon: 'fa-dice', desc: 'Angka random', category: 'utility' },
    { id: 'color', name: 'Color Picker', icon: 'fa-palette', desc: 'Ambil kode hex warna', category: 'design' },
    { id: 'timer', name: 'Timer', icon: 'fa-clock', desc: 'Timer hitung mundur', category: 'utility' },
    { id: 'speech', name: 'Text to Speech', icon: 'fa-volume-up', desc: 'Ubah teks jadi suara', category: 'utility' },
    { id: 'translate', name: 'Translate', icon: 'fa-language', desc: 'Terjemah ke Indonesia', category: 'utility' },
    { id: 'barcode', name: 'Barcode', icon: 'fa-barcode', desc: 'Generate barcode', category: 'utility' },
    { id: 'ipinfo', name: 'IP Info', icon: 'fa-globe', desc: 'Lihat info IP kamu', category: 'network' },
];

// ============ RENDER TOOLS ============
const grid = document.getElementById('toolsGrid');
tools.forEach(t => {
    const card = document.createElement('div');
    card.className = 'tool-card';
    card.innerHTML = `
        <div class="tool-icon"><i class="fas ${t.icon}"></i></div>
        <h4>${t.name}</h4>
        <p>${t.desc}</p>
    `;
    card.onclick = () => openTool(t.id, t.name);
    grid.appendChild(card);
});

// ============ MODAL ============
function openTool(id, name) {
    document.getElementById('toolTitle').textContent = name;
    const body = document.getElementById('toolBody');
    const modals = {
        qr: `<div class="form-group"><label>Teks / URL</label><input type="text" id="qrInput" placeholder="https://contoh.com" value="https://renclouds.com"></div><button class="btn btn-primary" onclick="genQR()"><i class="fas fa-qrcode"></i> Generate QR</button><div id="qrResult" style="text-align:center;margin-top:20px;"></div>`,
        shortlink: `<div class="form-group"><label>URL Panjang</label><input type="url" id="slInput" placeholder="https://contoh.com/url-panjang"></div><button class="btn btn-primary" onclick="genShort()"><i class="fas fa-link"></i> Pendekkan</button><div class="output-box" id="slResult">Hasil muncul di sini...</div>`,
        password: `<div class="form-group"><label>Panjang Password</label><input type="number" id="pwLen" value="16" min="6" max="64"></div><div class="form-group"><label><input type="checkbox" id="pwSym" checked> Pakai Simbol</label></div><button class="btn btn-primary" onclick="genPW()"><i class="fas fa-key"></i> Generate</button><div class="output-box" id="pwResult">Klik generate...</div>`,
        base64: `<div class="form-group"><label>Input</label><textarea id="b64Input" rows="4" placeholder="Teks atau base64..."></textarea></div><div style="display:flex;gap:10px;"><button class="btn btn-primary" onclick="b64Encode()">Encode</button><button class="btn btn-success" onclick="b64Decode()">Decode</button></div><div class="output-box" id="b64Result">Hasil...</div>`,
        uuid: `<button class="btn btn-primary" onclick="genUUID()"><i class="fas fa-fingerprint"></i> Generate UUID</button><div class="output-box" id="uuidResult">Klik generate...</div>`,
        random: `<div class="form-group"><label>Min</label><input type="number" id="rMin" value="1"></div><div class="form-group"><label>Max</label><input type="number" id="rMax" value="100"></div><button class="btn btn-primary" onclick="genRandom()"><i class="fas fa-dice"></i> Generate</button><div class="output-box" id="rResult">Klik generate...</div>`,
        color: `<div class="form-group"><label>Pilih Warna</label><input type="color" id="colInput" value="#6366f1" style="width:100%;height:60px;padding:5px;border-radius:12px;"></div><div class="output-box" id="colResult">Pilih warna di atas</div>`,
        timer: `<div class="form-group"><label>Detik</label><input type="number" id="tSec" value="10" min="1"></div><button class="btn btn-primary" onclick="startTimer()"><i class="fas fa-play"></i> Mulai</button><div class="output-box" id="tResult" style="font-size:2em;text-align:center;">00:00</div>`,
        speech: `<div class="form-group"><label>Teks</label><textarea id="spText" rows="3" placeholder="Tulis teks..."></textarea></div><button class="btn btn-primary" onclick="speak()"><i class="fas fa-volume-up"></i> Bicara</button>`,
        translate: `<div class="form-group"><label>Teks</label><textarea id="trText" rows="3" placeholder="Tulis teks..."></textarea></div><button class="btn btn-primary" onclick="translate()"><i class="fas fa-language"></i> Terjemah ke Indonesia</button><div class="output-box" id="trResult">Hasil...</div>`,
        barcode: `<div class="form-group"><label>Kode</label><input type="text" id="bcInput" value="1234567890"></div><button class="btn btn-primary" onclick="genBarcode()"><i class="fas fa-barcode"></i> Generate</button><div id="bcResult" style="text-align:center;margin-top:15px;"></div>`,
        ipinfo: `<button class="btn btn-primary" onclick="getIP()"><i class="fas fa-globe"></i> Lihat IP Saya</button><div class="output-box" id="ipResult">Klik untuk lihat...</div>`,
    };
    body.innerHTML = modals[id] || '<p>Tool not found</p>';
    document.getElementById('toolModal').classList.add('active');
}
function closeToolModal() { document.getElementById('toolModal').classList.remove('active'); }

// ============ TOOL FUNCTIONS ============
function genQR() {
    const text = encodeURIComponent(document.getElementById('qrInput').value);
    document.getElementById('qrResult').innerHTML = `<img src="https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${text}" style="border-radius:12px;">`;
}
async function genShort() {
    const url = document.getElementById('slInput').value;
    if (!url) return;
    document.getElementById('slResult').textContent = 'Loading...';
    try {
        const r = await fetch('https://tinyurl.com/api-create.php?url=' + encodeURIComponent(url));
        const t = await r.text();
        document.getElementById('slResult').textContent = t;
    } catch(e) { document.getElementById('slResult').textContent = 'Gagal: ' + e.message; }
}
function genPW() {
    const len = document.getElementById('pwLen').value;
    const sym = document.getElementById('pwSym').checked;
    let chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    if (sym) chars += '!@#$%^&*()_+-=[]{}';
    let p = '';
    for (let i=0;i<len;i++) p += chars[Math.floor(Math.random()*chars.length)];
    document.getElementById('pwResult').textContent = p;
}
function b64Encode() { try { document.getElementById('b64Result').textContent = btoa(document.getElementById('b64Input').value); } catch(e){ document.getElementById('b64Result').textContent = 'Error: '+e.message; } }
function b64Decode() { try { document.getElementById('b64Result').textContent = atob(document.getElementById('b64Input').value); } catch(e){ document.getElementById('b64Result').textContent = 'Error: '+e.message; } }
function genUUID() {
    const u = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random()*16|0; const v = c==='x'?r:(r&0x3|0x8); return v.toString(16); });
    document.getElementById('uuidResult').textContent = u;
}
function genRandom() {
    const min = parseInt(document.getElementById('rMin').value);
    const max = parseInt(document.getElementById('rMax').value);
    document.getElementById('rResult').textContent = Math.floor(Math.random()*(max-min+1))+min;
}
document.addEventListener('input', e => {
    if (e.target.id === 'colInput') document.getElementById('colResult').textContent = e.target.value;
});
let tmr;
function startTimer() {
    clearInterval(tmr);
    let s = parseInt(document.getElementById('tSec').value);
    const el = document.getElementById('tResult');
    tmr = setInterval(() => {
        if (s <= 0) { clearInterval(tmr); el.textContent = '⏰ Waktu Habis!'; return; }
        el.textContent = String(Math.floor(s/60)).padStart(2,'0')+':'+String(s%60).padStart(2,'0');
        s--;
    }, 1000);
}
function speak() {
    const t = document.getElementById('spText').value;
    if (!t) return;
    const u = new SpeechSynthesisUtterance(t);
    u.lang = 'id-ID';
    speechSynthesis.speak(u);
}
async function translate() {
    const text = document.getElementById('trText').value;
    if (!text) return;
    document.getElementById('trResult').textContent = 'Translating...';
    try {
        const r = await fetch(`https://api.mymemory.translated.net/get?q=${encodeURIComponent(text)}&langpair=auto|id`);
        const d = await r.json();
        document.getElementById('trResult').textContent = d.responseData.translatedText;
    } catch(e) { document.getElementById('trResult').textContent = 'Gagal: ' + e.message; }
}
function genBarcode() {
    const code = document.getElementById('bcInput').value;
    document.getElementById('bcResult').innerHTML = `<img src="https://barcode.tec-it.com/barcode.ashx?data=${encodeURIComponent(code)}&code=Code128&dpi=96" style="max-width:100%;border-radius:12px;">`;
}
async function getIP() {
    document.getElementById('ipResult').textContent = 'Loading...';
    try {
        const r = await fetch('https://ipapi.co/json/');
        const d = await r.json();
        document.getElementById('ipResult').textContent = `IP: ${d.ip}\nKota: ${d.city}\nProvinsi: ${d.region}\nNegara: ${d.country_name}\nISP: ${d.org}\nTimezone: ${d.timezone}`;
    } catch(e) { document.getElementById('ipResult').textContent = 'Gagal: ' + e.message; }
}
</script>
</body>
</html>
PHPEOF

echo -e "${GREEN}  ✅ Tools Hub Created${NC}"

# ==========================================
# 4. UPDATE DASHBOARD (Tambah Tombol Tools + Deteksi APK)
# ==========================================
echo -e "${CYAN}[4/4] Update Dashboard + Admin...${NC}"

# Tambah tombol Tools Hub di dashboard (kalau belum ada)
if ! grep -q "tools.php" "$WEB_ROOT/dashboard.php"; then
    sed -i 's|<div class="card">\s*<h3 style="margin-bottom:15px;"><i class="fas fa-cog"></i> Pengaturan</h3>|<div class="card" style="background:linear-gradient(135deg,rgba(99,102,241,.15),rgba(139,92,246,.15));border:1px solid var(--primary);">\
<h3 style="margin-bottom:10px;"><i class="fas fa-tools" style="color:var(--primary)"></i> Tools Hub 🛠️</h3>\
<p style="color:var(--text-muted);font-size:.9em;margin-bottom:15px;">Akses 12+ tools bermanfaat eksklusif pengguna APK RenClouds!</p>\
<a href="tools.php" class="btn btn-primary"><i class="fas fa-rocket"></i> Buka Tools Hub</a>\
</div>\
<div class="card">\
<h3 style="margin-bottom:15px;"><i class="fas fa-cog"></i> Pengaturan</h3>|' "$WEB_ROOT/dashboard.php"
fi

# Update Admin: form set Fingerprint APK (biar bisa ganti tanpa edit file)
if ! grep -q "apk_fingerprint" "$WEB_ROOT/admin.php"; then
    # Form AssetLinks di admin
    sed -i 's|<div class="card" style="margin-top:20px;">\s*<h3 style="margin-bottom:15px;"><i class="fas fa-bell"></i> Send Notification (Push)</h3>|<div class="card" style="margin-top:20px;">\
<h3 style="margin-bottom:15px;"><i class="fas fa-mobile-alt"></i> APK / AssetLinks Config</h3>\
<form method="POST">\
<div class="form-group"><label>Package Name</label><input type="text" name="apk_package" value="<?= htmlspecialchars($set["apk_package"] ?? "") ?>" required></div>\
<div class="form-group"><label>SHA256 Fingerprint</label><textarea name="apk_fingerprint" rows="2" placeholder="XX:XX:XX:..." required><?= htmlspecialchars($set["apk_fingerprint"] ?? "") ?></textarea></div>\
<button class="btn btn-primary" name="save_apk"><i class="fas fa-save"></i> Simpan & Regenerate assetlinks.json</button>\
</form>\
<p style="font-size:.8em;color:var(--text-muted);margin-top:10px;"><i class="fas fa-info-circle"></i> File otomatis ke-update di <code>/.well-known/assetlinks.json</code></p>\
</div>\
<div class="card" style="margin-top:20px;">\
<h3 style="margin-bottom:15px;"><i class="fas fa-bell"></i> Send Notification (Push)</h3>|' "$WEB_ROOT/admin.php"
    
    # Handler PHP di atas admin.php
    sed -i 's|if(isset($_POST\[.save_settings.\])){|if(isset($_POST["save_apk"])){\
    $pkg = $_POST["apk_package"]; $fp = $_POST["apk_fingerprint"];\
    $pdo->prepare("UPDATE settings SET apk_package=?,apk_fingerprint=? WHERE id=1")->execute([$pkg,$fp]);\
    $assetFile = "/var/www/$_SERVER[HTTP_HOST]/.well-known/assetlinks.json";\
    $assetFile = str_replace("www.$_SERVER[HTTP_HOST]","",$assetFile);\
    $content = json_encode([["relation"=>["delegate_permission/common.handle_all_urls"],"target"=>["namespace"=>"android_app","package_name"=>$pkg,"sha256_cert_fingerprints"=>[$fp]]]], JSON_PRETTY_PRINT\|JSON_UNESCAPED_SLASHES);\
    @file_put_contents($assetFile, $content);\
    $set = getSetting($pdo); $ok = "APK config disimpan & assetlinks.json regenerated!";\
}\
if(isset($_POST["save_settings"])){|' "$WEB_ROOT/admin.php"
fi

chown -R www-data:www-data "$WEB_ROOT"
chown -R www-data:www-data "$WEB_ROOT/.well-known"
systemctl reload nginx

echo -e "${GREEN}  ✅ All Updated${NC}"

# ==========================================
# SELESAI
# ==========================================
clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RenClouds v4.0 UPDATED!                    ║${NC}"
echo -e "${GREEN}║  🛠️ Tools Hub • TWA AssetLinks • APK Ready     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📁 AssetLinks File:${NC} $WEB_ROOT/.well-known/assetlinks.json"
echo -e "${CYAN}🔗 Test URL:${NC} https://$DOMAIN/.well-known/assetlinks.json"
echo -e "${CYAN}🛠️ Tools Hub:${NC} https://$DOMAIN/tools.php"
echo ""
echo -e "${YELLOW}⚙️ Konfigurasi AssetLinks:${NC}"
echo -e "   • Package: $PKG_NAME"
echo -e "   • Fingerprint: $FINGERPRINT"
echo ""
echo -e "${WHITE}📝 Setelah build APK di PWABuilder:${NC}"
echo -e "   1. Copy SHA256 fingerprint dari PWABuilder"
echo -e "   2. Login admin → scroll ke 'APK Config'"
echo -e "   3. Paste fingerprint → Simpan"
echo -e "   4. File assetlinks.json otomatis regenerate"
echo ""
echo -e "${GREEN}🚀 Test Flow:${NC}"
echo -e "   1. Install APK di HP → buka"
echo -e "   2. Login user → klik 'Buka Tools Hub'"
echo -e "   3. Nikmati 12+ tools premium!"
echo ""
