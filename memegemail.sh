#!/bin/bash
# ==========================================
# 📧 RenMail v3.0 - Node.js Backend
# Custom / Random • Auto Refresh • Anti-Error
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
MAIL_ROOT="$WEB_ROOT/mail"
NODE_DIR="/opt/renmail"
NODE_PORT="3005"

echo -e "${CYAN}[1/5] Install Node.js & Dependencies...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
    apt install -y nodejs >/dev/null 2>&1
fi

mkdir -p "$NODE_DIR"
cd "$NODE_DIR"

# --- PACKAGE.JSON ---
cat > package.json << 'EOF'
{
  "name": "renmail-backend",
  "version": "3.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "axios": "^1.7.2",
    "cors": "^2.8.5"
  }
}
EOF

echo -e "${CYAN}[2/5] Install NPM Modules...${NC}"
npm install --silent >/dev/null 2>&1

# --- NODE SERVER ---
cat > server.js << 'NODEEOF'
const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const API = 'https://www.1secmail.com/api/v1/';

// Generate random string
function randomStr(len = 8) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < len; i++) result += chars.charAt(Math.floor(Math.random() * chars.length));
    return result;
}

// ==========================================
// 1. GENERATE / OPEN EMAIL (CUSTOM ATAU RANDOM)
// ==========================================
app.post('/open', async (req, res) => {
    try {
        let { username } = req.body;
        
        // Kalau kosong, generate random
        if (!username || username.trim() === '') {
            username = 'ren' + randomStr(6);
        } else {
            // Bersihin karakter aneh
            username = username.toLowerCase().replace(/[^a-z0-9]/g, '');
            if (username.length < 3) return res.json({ status: false, message: 'Minimal 3 karakter' });
        }

        // Ambil domain yang tersedia dari 1secmail
        const domainRes = await axios.get(API + '?action=getDomainList');
        const domains = domainRes.data;
        if (!domains || domains.length === 0) return res.json({ status: false, message: 'Gagal ambil domain' });
        
        const domain = domains[0]; // pake domain pertama (biasanya 1secmail.com)
        const email = `${username}@${domain}`;

        res.json({ status: true, email: email, username: username });
    } catch (e) {
        res.json({ status: false, message: 'Server Error: ' + e.message });
    }
});

// ==========================================
// 2. CEK INBOX
// ==========================================
app.get('/inbox', async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) return res.json({ status: false, message: 'Email kosong' });

        const [user, domain] = email.split('@');
        const url = API + `?action=getMessages&login=${user}&domain=${domain}`;
        
        const response = await axios.get(url);
        const messages = response.data;

        // Format data
        const formatted = messages.map(m => ({
            id: m.id,
            from: m.from,
            subject: m.subject,
            date: m.date
        }));

        res.json({ status: true, messages: formatted });
    } catch (e) {
        res.json({ status: false, message: e.message });
    }
});

// ==========================================
// 3. BACA PESAN
// ==========================================
app.get('/read', async (req, res) => {
    try {
        const { email, id } = req.query;
        if (!email || !id) return res.json({ status: false, message: 'Data kurang' });

        const [user, domain] = email.split('@');
        const url = API + `?action=readMessage&login=${user}&domain=${domain}&id=${id}`;
        
        const response = await axios.get(url);
        res.json({ status: true, data: response.data });
    } catch (e) {
        res.json({ status: false, message: e.message });
    }
});

app.listen(3005, '127.0.0.1', () => {
    console.log('✅ RenMail Backend running on port 3005');
});
NODEEOF

echo -e "${CYAN}[3/5] Setup Systemd Service...${NC}"
cat > /etc/systemd/system/renmail.service << 'SVCEOF'
[Unit]
Description=RenMail Node Backend
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node /opt/renmail/server.js
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable --now renmail >/dev/null 2>&1

echo -e "${CYAN}[4/5] Generate Web Frontend...${NC}"
mkdir -p "$MAIL_ROOT"

# --- FRONTEND (HTML/CSS/JS) ---
cat > "$MAIL_ROOT/index.php" << 'PHPEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RenMail - Premium TempMail</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
    :root {
        --bg: #070b14;
        --card: #0f1a2e;
        --primary: #6366f1;
        --primary2: #8b5cf6;
        --success: #10b981;
        --danger: #ef4444;
        --text: #f8fafc;
        --text-muted: #94a3b8;
        --border: #1e2a45;
    }
    * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
    body {
        background: var(--bg);
        color: var(--text);
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-start;
        padding: 20px;
        background-image: 
            radial-gradient(circle at 10% 20%, rgba(99,102,241,0.15), transparent 40%),
            radial-gradient(circle at 90% 80%, rgba(139,92,246,0.12), transparent 40%);
    }
    .container { width: 100%; max-width: 600px; }
    .header { text-align: center; margin-bottom: 30px; margin-top: 20px; }
    .header h1 { font-size: 2.2em; font-weight: 800; letter-spacing: -1px; }
    .header h1 i { color: var(--primary); margin-right: 8px; }
    .header p { color: var(--text-muted); font-size: 0.95em; margin-top: 5px; }

    .card {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 20px;
        padding: 25px;
        margin-bottom: 20px;
        box-shadow: 0 10px 40px rgba(0,0,0,0.5);
    }

    /* INPUT CUSTOM USERNAME */
    .input-group {
        display: flex;
        align-items: center;
        background: rgba(0,0,0,0.4);
        border: 1px solid var(--primary);
        border-radius: 12px;
        padding: 5px 15px;
        gap: 10px;
        margin-bottom: 15px;
    }
    .input-group i { color: var(--primary); font-size: 1.2em; }
    .input-group input {
        flex: 1;
        background: transparent;
        border: none;
        color: var(--text);
        padding: 15px 0;
        font-size: 1em;
        font-weight: 600;
        outline: none;
        font-family: monospace;
    }
    .input-group input::placeholder { color: var(--text-muted); font-family: 'Inter', sans-serif; font-weight: 400; }
    
    .hint-text { font-size: 0.8em; color: var(--text-muted); margin-bottom: 15px; text-align: center; }

    .btn-row { display: flex; gap: 10px; }
    .btn {
        flex: 1;
        padding: 15px;
        border: none;
        border-radius: 12px;
        font-weight: 700;
        font-size: 1em;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 10px;
        transition: 0.3s;
        font-family: inherit;
        color: white;
    }
    .btn-primary { background: linear-gradient(135deg, var(--primary), var(--primary2)); box-shadow: 0 4px 15px rgba(99,102,241,0.3); }
    .btn-primary:hover { transform: translateY(-2px); box-shadow: 0 8px 25px rgba(99,102,241,0.5); }
    .btn-success { background: linear-gradient(135deg, #10b981, #059669); }
    .btn-danger { background: linear-gradient(135deg, #ef4444, #dc2626); }
    .btn-warning { background: linear-gradient(135deg, #f59e0b, #d97706); }

    /* INBOX SECTION */
    #inboxSection { display: none; }
    
    .email-box {
        display: flex;
        align-items: center;
        background: rgba(0,0,0,0.4);
        border: 1px solid var(--success);
        border-radius: 12px;
        padding: 15px 20px;
        gap: 10px;
        margin-bottom: 15px;
    }
    .email-box i { color: var(--success); font-size: 1.2em; }
    .email-text { flex: 1; font-family: monospace; font-size: 1em; font-weight: 600; color: var(--text); word-break: break-all; }
    .btn-icon { background: var(--success); color: white; border: none; padding: 10px 12px; border-radius: 8px; cursor: pointer; font-size: 1em; transition: 0.3s; }
    .btn-icon:hover { background: #059669; }

    .inbox-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid var(--border); }
    .inbox-header h3 { font-size: 1.1em; font-weight: 700; display: flex; align-items: center; gap: 8px; }
    .inbox-header h3 i { color: var(--primary); }
    
    .auto-refresh { display: flex; align-items: center; gap: 5px; font-size: 0.75em; color: var(--success); background: rgba(16,185,129,0.1); padding: 5px 10px; border-radius: 20px; border: 1px solid rgba(16,185,129,0.3); }
    .auto-refresh .dot { width: 6px; height: 6px; background: var(--success); border-radius: 50%; animation: pulse 1.5s infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.3; } }

    .inbox-list { display: flex; flex-direction: column; gap: 10px; min-height: 100px; }
    .empty-state { text-align: center; padding: 40px 20px; color: var(--text-muted); }
    .empty-state i { font-size: 3em; margin-bottom: 15px; opacity: 0.3; display: block; }
    
    .mail-item { background: rgba(0,0,0,0.3); border: 1px solid var(--border); border-radius: 12px; padding: 15px; cursor: pointer; transition: 0.3s; }
    .mail-item:hover { border-color: var(--primary); background: rgba(99,102,241,0.05); }
    .mail-top { display: flex; justify-content: space-between; margin-bottom: 5px; }
    .mail-from { font-weight: 700; font-size: 0.9em; color: var(--primary); }
    .mail-date { font-size: 0.75em; color: var(--text-muted); }
    .mail-subject { font-weight: 600; font-size: 0.9em; margin-bottom: 5px; }
    .mail-intro { font-size: 0.85em; color: var(--text-muted); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

    /* MODAL */
    .modal { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.8); z-index: 999; align-items: center; justify-content: center; padding: 20px; }
    .modal.active { display: flex; }
    .modal-content { background: var(--card); border: 1px solid var(--border); border-radius: 20px; padding: 25px; width: 100%; max-width: 550px; max-height: 80vh; overflow-y: auto; }
    .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid var(--border); padding-bottom: 15px; }
    .modal-header h3 { font-size: 1.2em; font-weight: 800; }
    .modal-close { background: var(--danger); color: white; border: none; width: 35px; height: 35px; border-radius: 50%; cursor: pointer; font-size: 1.2em; display: flex; align-items: center; justify-content: center; }
    .modal-body { font-size: 0.9em; line-height: 1.7; color: var(--text); word-wrap: break-word; }

    .loader { display: inline-block; width: 20px; height: 20px; border: 3px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 0.8s linear infinite; }
    @keyframes spin { 100% { transform: rotate(360deg); } }

    @media (max-width: 500px) { .header h1 { font-size: 1.8em; } .card { padding: 20px; } .btn { font-size: 0.85em; padding: 12px; } }
</style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-envelope-open-text"></i>RenMail</h1>
            <p>Custom / Random • Permanen • Auto Refresh 5s</p>
        </div>

        <!-- LOGIN CARD -->
        <div class="card" id="loginCard">
            <div class="input-group">
                <i class="fas fa-user"></i>
                <input type="text" id="usernameInput" placeholder="Ketik nama (atau kosongin buat random)..." onkeypress="if(event.key==='Enter') openInbox()">
            </div>
            <p class="hint-text"><i class="fas fa-info-circle"></i> Biarin kosong buat dapet email random</p>
            <button class="btn btn-primary" onclick="openInbox()" id="btnOpen" style="width:100%;">
                <i class="fas fa-sign-in-alt"></i> Buka Inbox
            </button>
        </div>

        <!-- INBOX CARD -->
        <div class="card" id="inboxSection">
            <div class="email-box">
                <i class="fas fa-check-circle"></i>
                <span class="email-text" id="emailDisplay"></span>
                <button class="btn-icon" onclick="copyEmail()" title="Copy"><i class="fas fa-copy"></i></button>
            </div>
            
            <div style="display:flex;gap:10px;margin-bottom:20px;">
                <button class="btn btn-danger" onclick="logout()" style="flex:0.4;padding:12px;font-size:0.9em;"><i class="fas fa-sign-out-alt"></i> Ganti</button>
                <button class="btn btn-success" onclick="checkInbox(true)" style="flex:1;padding:12px;font-size:0.9em;"><i class="fas fa-sync-alt"></i> Refresh</button>
            </div>

            <div class="inbox-header">
                <h3><i class="fas fa-inbox"></i> Inbox</h3>
                <div class="auto-refresh" id="autoBadge"><div class="dot"></div> Auto Refresh</div>
            </div>
            <div class="inbox-list" id="inboxList">
                <div class="empty-state"><i class="fas fa-envelope"></i><p>Belum ada pesan masuk</p></div>
            </div>
        </div>
    </div>

    <!-- MODAL BACA PESAN -->
    <div class="modal" id="readModal">
        <div class="modal-content">
            <div class="modal-header">
                <h3 id="mailTitle">Baca Pesan</h3>
                <button class="modal-close" onclick="closeModal()"><i class="fas fa-times"></i></button>
            </div>
            <div class="modal-body" id="mailBody"></div>
        </div>
    </div>

<script>
// Base URL ke Node.js Backend
const API_URL = '/api-renmail'; 

let currentEmail = '';
let refreshInterval = null;

// ============== BUKA INBOX ==============
async function openInbox() {
    const username = document.getElementById('usernameInput').value.trim();
    const btn = document.getElementById('btnOpen');
    
    btn.innerHTML = '<div class="loader"></div> Menghubungkan...';
    btn.disabled = true;

    try {
        const res = await fetch(API_URL + '/open', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: username })
        });
        const data = await res.json();
        
        if (data.status) {
            currentEmail = data.email;
            
            // Simpan di localstorage biar permanen
            localStorage.setItem('renmail_email', currentEmail);

            document.getElementById('loginCard').style.display = 'none';
            document.getElementById('inboxSection').style.display = 'block';
            document.getElementById('emailDisplay').textContent = currentEmail;
            document.getElementById('inboxList').innerHTML = '<div class="empty-state"><i class="fas fa-hourglass-half"></i><p>Menunggu pesan...</p></div>';
            
            startAutoRefresh();
        } else {
            alert('Gagal: ' + data.message);
        }
    } catch (e) {
        alert('Error koneksi: ' + e.message);
    }
    
    btn.innerHTML = '<i class="fas fa-sign-in-alt"></i> Buka Inbox';
    btn.disabled = false;
}

// ============== LOGOUT / GANTI EMAIL ==============
function logout() {
    localStorage.removeItem('renmail_email');
    currentEmail = '';
    if (refreshInterval) clearInterval(refreshInterval);
    
    document.getElementById('inboxSection').style.display = 'none';
    document.getElementById('loginCard').style.display = 'block';
    document.getElementById('usernameInput').value = '';
}

// ============== COPY EMAIL ==============
function copyEmail() {
    if (!currentEmail) return;
    navigator.clipboard.writeText(currentEmail).then(() => {
        const btn = event.target.closest('button');
        const originalHTML = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-check"></i>';
        setTimeout(() => btn.innerHTML = originalHTML, 1500);
    });
}

// ============== CHECK INBOX ==============
async function checkInbox(showAlert = false) {
    if (!currentEmail) return;
    const list = document.getElementById('inboxList');
    if (showAlert) list.innerHTML = '<div class="empty-state"><div class="loader"></div></div>';
    
    try {
        const res = await fetch(API_URL + '/inbox?email=' + encodeURIComponent(currentEmail));
        const data = await res.json();
        
        if (data.status && data.messages.length > 0) {
            list.innerHTML = data.messages.map(m => `
                <div class="mail-item" onclick="readMail('${m.id}')">
                    <div class="mail-top">
                        <div class="mail-from"><i class="fas fa-user-circle"></i> ${m.from}</div>
                        <div class="mail-date"><i class="fas fa-clock"></i> ${m.date}</div>
                    </div>
                    <div class="mail-subject">${m.subject}</div>
                </div>
            `).join('');
        } else {
            list.innerHTML = '<div class="empty-state"><i class="fas fa-envelope"></i><p>Belum ada pesan masuk</p><p style="font-size:0.8em;margin-top:5px;">Auto refresh tiap 5 detik...</p></div>';
        }
    } catch (e) {
        if (showAlert) list.innerHTML = '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><p>Gagal load inbox</p></div>';
    }
}

// ============== READ MAIL ==============
async function readMail(id) {
    const modal = document.getElementById('readModal');
    const body = document.getElementById('mailBody');
    const title = document.getElementById('mailTitle');
    
    modal.classList.add('active');
    title.textContent = 'Loading...';
    body.innerHTML = '<div style="text-align:center;padding:20px;"><div class="loader"></div></div>';
    
    try {
        const res = await fetch(API_URL + `/read?email=${encodeURIComponent(currentEmail)}&id=${id}`);
        const data = await res.json();
        if (data.status) {
            title.textContent = data.data.subject || 'No Subject';
            let content = data.data.textBody || data.data.body || '';
            if (!content && data.data.htmlBody) content = data.data.htmlBody;
            
            // Bersihin script jahat
            content = content.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
            
            body.innerHTML = `
                <p style="margin-bottom:15px;font-size:0.85em;color:var(--text-muted);">
                    <strong>From:</strong> ${data.data.from}<br>
                    <strong>Date:</strong> ${data.data.date}
                </p>
                <div style="background:rgba(0,0,0,0.3);padding:15px;border-radius:10px;font-size:0.9em;">
                    ${content || '(Pesan kosong)'}
                </div>
            `;
        } else {
            title.textContent = 'Error';
            body.innerHTML = '<p>Gagal load pesan</p>';
        }
    } catch (e) {
        title.textContent = 'Error';
        body.innerHTML = '<p>' + e.message + '</p>';
    }
}

function closeModal() { document.getElementById('readModal').classList.remove('active'); }
document.getElementById('readModal').addEventListener('click', (e) => { if (e.target.id === 'readModal') closeModal(); });

// ============== AUTO REFRESH 5s ==============
function startAutoRefresh() {
    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(() => {
        if (currentEmail) checkInbox(false);
    }, 5000);
}

// ============== AUTO LOGIN (LOCALSTORAGE) ==============
window.addEventListener('load', () => {
    const savedEmail = localStorage.getItem('renmail_email');
    if (savedEmail) {
        currentEmail = savedEmail;
        document.getElementById('loginCard').style.display = 'none';
        document.getElementById('inboxSection').style.display = 'block';
        document.getElementById('emailDisplay').textContent = currentEmail;
        checkInbox(false);
        startAutoRefresh();
    }
});
</script>
</body>
</html>
PHPEOF

# --- SETUP NGINX REVERSE PROXY ---
echo -e "${CYAN}[5/5] Setup Nginx Reverse Proxy...${NC}"
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

# Hapus config /mail lama kalau ada
sed -i '/location \/mail {/,/}/d' "$NGINX_CONF"
sed -i '/location \/api-renmail {/,/}/d' "$NGINX_CONF"

# Tambahin proxy
cat << NGINXEOF > /tmp/renmail_nginx.conf
    # RENMAIL API PROXY
    location /api-renmail/ {
        proxy_pass http://127.0.0.1:3005/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
NGINXEOF

# Sisipin ke dalam blok server (sebelum kurung kurawal terakhir)
sed -i '/location ~ \\.php\$ {/i \    # RENMAIL PROXY\n    location /api-renmail/ { proxy_pass http://127.0.0.1:3005/; proxy_http_version 1.1; proxy_set_header Host $host; }' "$NGINX_CONF"

# Pastiin folder /mail bisa diakses
chown -R www-data:www-data "$MAIL_ROOT"
chmod -R 755 "$MAIL_ROOT"

# Restart semua service
nginx -t >/dev/null 2>&1 && systemctl reload nginx
systemctl restart php8.3-fpm
systemctl restart renmail

clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RENMAIL v3.0 BERHASIL TERINSTALL!          ║${NC}"
echo -e "${GREEN}║  📧 Node.js • Custom/Random • Auto Refresh     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL TempMail:${NC} https://$DOMAIN/mail/"
echo ""
echo -e "${YELLOW}💡 Fitur:${NC}"
echo -e "   • Ketik nama sendiri ATAU kosongin buat random"
echo -e "   • Pake API 1secmail (stabil, anti-limit)"
echo -e "   • Backend Node.js asli (request beneran)"
echo -e "   • Auto-refresh 5s + dot hijau"
echo -e "   • LocalStorage (permanen di browser)"
echo ""
echo -e "${GREEN}🚀 Buka di browser!${NC}"
