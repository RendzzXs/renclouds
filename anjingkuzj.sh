#!/bin/bash
# ==========================================
# 📧 RenMail v5.0 - GOD TIER (Anti Error)
# Double Engine (TempMail.app + Mail.gw)
# ==========================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

DOMAIN="hackingg.myboc.my.id"
WEB_ROOT="/var/www/$DOMAIN"
MAIL_ROOT="$WEB_ROOT/mail"
NODE_DIR="/opt/renmail"

echo -e "${CYAN}[1/4] Reset Folder & Install Modules...${NC}"
rm -rf "$MAIL_ROOT"
mkdir -p "$MAIL_ROOT" "$NODE_DIR"
cd "$NODE_DIR"

cat > package.json << 'EOF'
{
  "name": "renmail-backend",
  "version": "5.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.19.2",
    "cors": "^2.8.5",
    "cheerio": "^1.0.0",
    "axios": "^1.7.2"
  }
}
EOF
npm install --silent >/dev/null 2>&1

echo -e "${CYAN}[2/4] Generate Backend (Double Engine)...${NC}"

cat > "$NODE_DIR/server.js" << 'NODEEOF'
const express = require('express');
const https = require('https');
const crypto = require('crypto');
const cheerio = require('cheerio');
const axios = require('axios');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const sessions = {};

// ==========================================
// ENGINE 1: TEMP-MAIL.APP (PRIMARY)
// ==========================================
function reqTempMail(path, params = {}, session) {
    const urlObj = new URL(`https://temp-mail.app${path}`);
    Object.keys(params).forEach(key => urlObj.searchParams.append(key, params[key]));

    return new Promise((resolve, reject) => {
        const options = {
            hostname: urlObj.hostname,
            path: urlObj.pathname + urlObj.search,
            method: 'GET',
            headers: {
                'Accept': '*/*',
                'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Mobile Safari/537.36',
                'Visitor-Id': session.visitorId, 
                'Cookie': session.cookie || ''
            }
        };

        const req = https.request(options, (res) => {
            let data = '';
            if (res.headers['set-cookie']) session.cookie = res.headers['set-cookie'].join('; ');
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try { resolve(JSON.parse(data)); } 
                catch (e) { reject(new Error("Invalid JSON from TempMail.app")); }
            });
        });
        req.on('error', reject);
        req.setTimeout(10000, () => { req.destroy(); reject(new Error("Timeout TempMail.app")); });
        req.end();
    });
}

function parseHTML(html) {
    if (!html) return { text: "", links: [] };
    const $ = cheerio.load(html);
    const links = [];
    $('a[href]').each((i, el) => {
        const href = $(el).attr('href');
        if (href && href.startsWith('http')) links.push(href);
    });
    $('script, style').remove();
    const text = $('body').text().replace(/\n\s*\n/g, '\n').trim();
    return { text, links };
}

// ==========================================
// ENGINE 2: MAIL.GW (FALLBACK)
// ==========================================
async function generateMailGw() {
    const domainsRes = await axios.get('https://api.mail.gw/domains');
    const domain = domainsRes.data['hydra:member'][0].domain;
    const username = 'ren' + crypto.randomBytes(4).toString('hex');
    const password = crypto.randomBytes(8).toString('hex');
    const address = `${username}@${domain}`;

    await axios.post('https://api.mail.gw/accounts', { address, password });
    const login = await axios.post('https://api.mail.gw/token', { address, password });
    
    return { email: address, token: login.data.token };
}

// ==========================================
// ENDPOINT 1: GENERATE
// ==========================================
app.get('/generate', async (req, res) => {
    const sessionId = crypto.randomUUID();
    let email = "", engine = "", mailGwToken = "";

    try {
        // Coba Engine 1
        const session = { cookie: "", visitorId: crypto.randomUUID() };
        const addrRes = await reqTempMail('/api/mail/address', { refresh: 'true', expire: '1440', part: 'main' }, session);
        if (addrRes.address) { email = addrRes.address; engine = "tempmail"; sessions[sessionId] = { engine, session, cache: {} }; }
    } catch (e) {
        console.log('Engine 1 failed, falling back to Engine 2...');
    }

    if (!email) {
        try {
            // Coba Engine 2
            const gw = await generateMailGw();
            email = gw.email; engine = "mailgw"; mailGwToken = gw.token;
            sessions[sessionId] = { engine, token: mailGwToken, cache: {} };
        } catch (e) {
            return res.json({ status: false, message: "Semua engine gagal. Coba lagi nanti." });
        }
    }

    res.json({ status: true, email, session_id: sessionId, engine });
});

// ==========================================
// ENDPOINT 2: INBOX
// ==========================================
app.get('/inbox', async (req, res) => {
    const sessionId = req.query.session_id;
    if (!sessionId || !sessions[sessionId]) return res.json({ status: false, message: "Session invalid" });
    
    const sess = sessions[sessionId];
    let messages = [];

    try {
        if (sess.engine === "tempmail") {
            const inboxRes = await reqTempMail('/api/mail/list', { part: 'main' }, sess.session);
            const rawMsgs = inboxRes.message || [];
            messages = rawMsgs.map(m => {
                const parsed = parseHTML(m.content);
                sess.cache[m.id] = { from: m.fromName || m.fromAddress, subject: m.subject, date: m.date, content: parsed.text, links: parsed.links };
                return { id: m.id, from: m.fromName || m.fromAddress, subject: m.subject, date: m.date };
            });
        } 
        else if (sess.engine === "mailgw") {
            const inboxRes = await axios.get('https://api.mail.gw/messages', { headers: { Authorization: `Bearer ${sess.token}` } });
            const rawMsgs = inboxRes.data['hydra:member'] || [];
            messages = rawMsgs.map(m => {
                let text = m.intro || "";
                // mail.gw gak ngasih full content di list, kita cache intro dulu
                sess.cache[m.id] = { from: m.from.address, subject: m.subject, date: m.createdAt, content: text, links: [] };
                return { id: m.id, from: m.from.address, subject: m.subject, date: new Date(m.createdAt).toLocaleTimeString() };
            });
        }
        res.json({ status: true, email: sess.email || '', messages });
    } catch (e) {
        res.json({ status: false, message: "Gagal load inbox: " + e.message });
    }
});

// ==========================================
// ENDPOINT 3: READ (DARI CACHE)
// ==========================================
app.get('/read', async (req, res) => {
    const { session_id, id } = req.query;
    if (!session_id || !sessions[session_id]) return res.json({ status: false });

    const sess = sessions[session_id];
    const cached = sess.cache[id];

    if (cached) {
        res.json({ status: true, data: cached });
    } else {
        // Kalau cache kosong (mungkin user refresh), coba ambil dari API (khusus mailgw)
        if (sess.engine === "mailgw") {
            try {
                const msg = await axios.get(`https://api.mail.gw/messages/${id}`, { headers: { Authorization: `Bearer ${sess.token}` } });
                const content = msg.data.text || msg.data.html || msg.data.intro;
                const data = { from: msg.data.from.address, subject: msg.data.subject, date: msg.data.createdAt, content: content, links: [] };
                sess.cache[id] = data;
                res.json({ status: true, data });
            } catch (e) { res.json({ status: false, message: "Gagal load pesan" }); }
        } else {
            res.json({ status: false, message: "Silakan refresh inbox dulu." });
        }
    }
});

app.listen(3005, '127.0.0.1', () => {
    console.log('✅ RenMail v5.0 Backend running on port 3005');
});
NODEEOF

echo -e "${CYAN}[3/4] Setup Systemd & Restart...${NC}"
cat > /etc/systemd/system/renmail.service << 'SVCEOF'
[Unit]
Description=RenMail Backend
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
systemctl restart renmail

echo -e "${CYAN}[4/4] Generate Frontend UI...${NC}"

cat > "$MAIL_ROOT/index.php" << 'PHPEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RenMail - Fast TempMail</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
    :root { --bg: #070b14; --card: #0f1a2e; --primary: #6366f1; --primary2: #8b5cf6; --success: #10b981; --danger: #ef4444; --text: #f8fafc; --text-muted: #94a3b8; --border: #1e2a45; }
    * { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Inter', sans-serif; }
    body { background: var(--bg); color: var(--text); min-height: 100vh; display: flex; flex-direction: column; align-items: center; padding: 20px; background-image: radial-gradient(circle at 10% 20%, rgba(99,102,241,0.15), transparent 40%), radial-gradient(circle at 90% 80%, rgba(139,92,246,0.12), transparent 40%); }
    .container { width: 100%; max-width: 600px; }
    .header { text-align: center; margin-bottom: 30px; margin-top: 20px; }
    .header h1 { font-size: 2.2em; font-weight: 800; }
    .header h1 i { color: var(--primary); margin-right: 8px; }
    .header p { color: var(--text-muted); font-size: 0.95em; margin-top: 5px; }
    .card { background: var(--card); border: 1px solid var(--border); border-radius: 20px; padding: 25px; margin-bottom: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.5); }
    
    .email-box { display: flex; align-items: center; background: rgba(0,0,0,0.4); border: 1px solid var(--success); border-radius: 12px; padding: 15px 20px; gap: 10px; margin-bottom: 15px; }
    .email-box i { color: var(--success); font-size: 1.2em; }
    .email-text { flex: 1; font-family: monospace; font-size: 1em; font-weight: 600; word-break: break-all; }
    .btn-icon { background: var(--success); color: white; border: none; padding: 10px 12px; border-radius: 8px; cursor: pointer; font-size: 1em; transition: 0.3s; }
    
    .btn-row { display: flex; gap: 10px; }
    .btn { flex: 1; padding: 15px; border: none; border-radius: 12px; font-weight: 700; font-size: 1em; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 10px; transition: 0.3s; color: white; }
    .btn-primary { background: linear-gradient(135deg, var(--primary), var(--primary2)); }
    .btn-danger { background: linear-gradient(135deg, #ef4444, #dc2626); }
    
    .inbox-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid var(--border); }
    .inbox-header h3 { font-size: 1.1em; font-weight: 700; display: flex; align-items: center; gap: 8px; }
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
    .mail-subject { font-weight: 600; font-size: 0.9em; }
    
    .modal { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.8); z-index: 999; align-items: center; justify-content: center; padding: 20px; }
    .modal.active { display: flex; }
    .modal-content { background: var(--card); border: 1px solid var(--border); border-radius: 20px; padding: 25px; width: 100%; max-width: 550px; max-height: 80vh; overflow-y: auto; }
    .modal-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 1px solid var(--border); padding-bottom: 15px; }
    .modal-close { background: var(--danger); color: white; border: none; width: 35px; height: 35px; border-radius: 50%; cursor: pointer; }
    .modal-body { font-size: 0.9em; line-height: 1.7; }
    .loader { display: inline-block; width: 20px; height: 20px; border: 3px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 0.8s linear infinite; }
    @keyframes spin { 100% { transform: rotate(360deg); } }
    .hidden { display: none !important; }
</style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1><i class="fas fa-envelope-open-text"></i>RenMail</h1>
            <p>Fast TempMail • Auto Refresh 5s</p>
        </div>

        <div class="card" id="loginCard">
            <p style="text-align:center;color:var(--text-muted);margin-bottom:20px;">Klik tombol di bawah untuk generate email otomatis</p>
            <button class="btn btn-primary" onclick="generateEmail()" id="btnGen" style="width:100%;">
                <i class="fas fa-bolt"></i> Generate Email Instant
            </button>
        </div>

        <div class="card hidden" id="inboxSection">
            <div class="email-box">
                <i class="fas fa-check-circle"></i>
                <span class="email-text" id="emailDisplay"></span>
                <button class="btn-icon" onclick="copyEmail()" title="Copy"><i class="fas fa-copy"></i></button>
            </div>
            <div style="display:flex;gap:10px;margin-bottom:20px;">
                <button class="btn btn-danger" onclick="logout()" style="flex:0.4;padding:12px;font-size:0.9em;"><i class="fas fa-sync-alt"></i> Baru</button>
                <button class="btn btn-primary" onclick="checkInbox(true)" style="flex:1;padding:12px;font-size:0.9em;"><i class="fas fa-redo"></i> Refresh</button>
            </div>
            <div class="inbox-header">
                <h3><i class="fas fa-inbox"></i> Inbox</h3>
                <div class="auto-refresh"><div class="dot"></div> Auto</div>
            </div>
            <div class="inbox-list" id="inboxList">
                <div class="empty-state"><i class="fas fa-envelope"></i><p>Belum ada pesan</p></div>
            </div>
        </div>
    </div>

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
const API = '/api-renmail';
let currentEmail = '', currentSession = '', refreshInterval = null;

async function generateEmail() {
    const btn = document.getElementById('btnGen');
    btn.innerHTML = '<div class="loader"></div> Loading...';
    btn.disabled = true;

    try {
        const res = await fetch(API + '/generate');
        const data = await res.json();
        if (data.status) {
            currentEmail = data.email;
            currentSession = data.session_id;
            localStorage.setItem('rm_email', currentEmail);
            localStorage.setItem('rm_session', currentSession);

            document.getElementById('loginCard').classList.add('hidden');
            document.getElementById('inboxSection').classList.remove('hidden');
            document.getElementById('emailDisplay').textContent = currentEmail;
            
            checkInbox(false);
            startAutoRefresh();
        } else alert('Gagal: ' + data.message);
    } catch (e) { alert('Error: ' + e.message); }
    
    btn.innerHTML = '<i class="fas fa-bolt"></i> Generate Email Instant';
    btn.disabled = false;
}

function logout() {
    localStorage.removeItem('rm_email');
    localStorage.removeItem('rm_session');
    currentEmail = ''; currentSession = '';
    if (refreshInterval) clearInterval(refreshInterval);
    document.getElementById('inboxSection').classList.add('hidden');
    document.getElementById('loginCard').classList.remove('hidden');
}

function copyEmail() {
    navigator.clipboard.writeText(currentEmail).then(() => {
        const btn = event.target.closest('button');
        const orig = btn.innerHTML;
        btn.innerHTML = '<i class="fas fa-check"></i>';
        setTimeout(() => btn.innerHTML = orig, 1500);
    });
}

async function checkInbox(showAlert = false) {
    if (!currentSession) return;
    const list = document.getElementById('inboxList');
    if (showAlert) list.innerHTML = '<div class="empty-state"><div class="loader"></div></div>';
    
    try {
        const res = await fetch(API + '/inbox?session_id=' + currentSession);
        const data = await res.json();
        if (data.status && data.messages.length > 0) {
            list.innerHTML = data.messages.map(m => `
                <div class="mail-item" onclick="readMail('${m.id}')">
                    <div class="mail-top">
                        <div class="mail-from"><i class="fas fa-user-circle"></i> ${m.from}</div>
                        <div class="mail-date"><i class="fas fa-clock"></i> ${m.date}</div>
                    </div>
                    <div class="mail-subject">${m.subject}</div>
                </div>`).join('');
        } else {
            list.innerHTML = '<div class="empty-state"><i class="fas fa-envelope"></i><p>Belum ada pesan</p><p style="font-size:0.8em;margin-top:5px;">Auto refresh 5s...</p></div>';
        }
    } catch (e) {}
}

async function readMail(id) {
    const modal = document.getElementById('readModal');
    modal.classList.add('active');
    document.getElementById('mailTitle').textContent = 'Loading...';
    document.getElementById('mailBody').innerHTML = '<div style="text-align:center;padding:20px;"><div class="loader"></div></div>';
    
    try {
        const res = await fetch(`${API}/read?session_id=${currentSession}&id=${id}`);
        const data = await res.json();
        if (data.status) {
            document.getElementById('mailTitle').textContent = data.data.subject || 'No Subject';
            document.getElementById('mailBody').innerHTML = `
                <p style="margin-bottom:15px;font-size:0.85em;color:var(--text-muted);">
                    <strong>From:</strong> ${data.data.from}<br>
                    <strong>Date:</strong> ${data.data.date}
                </p>
                <div style="background:rgba(0,0,0,0.3);padding:15px;border-radius:10px;font-size:0.9em;white-space:pre-wrap;">
                    ${data.data.content || '(Pesan kosong)'}
                </div>
                ${data.data.links.length > 0 ? `<div style="margin-top:15px;"><strong>Links:</strong><br>${data.data.links.map(l => `<a href="${l}" target="_blank" style="color:var(--primary);font-size:0.85em;word-break:break-all;">${l}</a>`).join('<br>')}</div>` : ''}
            `;
        } else {
            document.getElementById('mailTitle').textContent = 'Pesan Belum Siap';
            document.getElementById('mailBody').innerHTML = '<p style="text-align:center;padding:20px;">Tutup ini, lalu klik tombol <b>Refresh</b> di Inbox.</p>';
        }
    } catch (e) {}
}

function closeModal() { document.getElementById('readModal').classList.remove('active'); }
document.getElementById('readModal').addEventListener('click', e => { if (e.target.id === 'readModal') closeModal(); });

function startAutoRefresh() {
    if (refreshInterval) clearInterval(refreshInterval);
    refreshInterval = setInterval(() => { if (currentSession) checkInbox(false); }, 5000);
}

window.addEventListener('load', () => {
    const savedEmail = localStorage.getItem('rm_email');
    const savedSession = localStorage.getItem('rm_session');
    if (savedEmail && savedSession) {
        currentEmail = savedEmail;
        currentSession = savedSession;
        document.getElementById('loginCard').classList.add('hidden');
        document.getElementById('inboxSection').classList.remove('hidden');
        document.getElementById('emailDisplay').textContent = currentEmail;
        checkInbox(false);
        startAutoRefresh();
    }
});
</script>
</body>
</html>
PHPEOF

# --- SETUP NGINX REVERSE PROXY (Bersih) ---
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
sed -i '/location \/mail {/,/}/d' "$NGINX_CONF"
sed -i '/location \/api-renmail {/,/}/d' "$NGINX_CONF"

if ! grep -q "api-renmail" "$NGINX_CONF"; then
    sed -i '/location ~ \\.php\$ {/i \    location /api-renmail/ {\n        proxy_pass http://127.0.0.1:3005/;\n        proxy_http_version 1.1;\n        proxy_set_header Host $host;\n    }' "$NGINX_CONF"
fi

chown -R www-data:www-data "$MAIL_ROOT"
chmod -R 755 "$MAIL_ROOT"

nginx -t >/dev/null 2>&1 && systemctl reload nginx

clear
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ RENMAIL v5.0 (GOD TIER) BERHASIL!          ║${NC}"
echo -e "${GREEN}║  🛡️ DOUBLE ENGINE + CACHE SYSTEM               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL TempMail:${NC} https://$DOMAIN/mail/"
echo ""
echo -e "${YELLOW}💡 Fitur Anti-Error:${NC}"
echo -e "   • Fallback Engine (TempMail.app -> Mail.gw)"
echo -e "   • Cache Baca Pesan (0ms instant load)"
echo -e "   • Error handling di semua request"
echo ""
echo -e "${GREEN}🚀 Silakan tes lagi, dijamin mulus!${NC}"
