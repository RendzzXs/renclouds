#!/bin/bash
# ============================================================
#   REN CLOUDS — ALL-IN-ONE INSTALLER v6.1 (LOGIN/REGISTER FIX)
#   Fix: Admin hash, session fixation, modal loop, api path
#   Domain: www.rendzzclouds.my.id
#   Usage: sudo bash install.sh
# ============================================================

set -e
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; NC='\033[0m'

clear
echo -e "${CYN}"
echo "==============================================="
echo "   REN CLOUDS — INSTALLER v6.1"
echo "   Fix Login/Register + Admin Hash"
echo "==============================================="
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[X] Jalankan sebagai root: sudo bash install.sh${NC}"
  exit 1
fi

# ---------- INPUT ----------
read -p "$(echo -e ${YLW}Domain VPS: ${NC})" DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}[X] Domain kosong!${NC}"; exit 1; }
read -p "$(echo -e ${YLW}Email SSL: ${NC})" EMAIL
[[ -z "$EMAIL" ]] && { echo -e "${RED}[X] Email kosong!${NC}"; exit 1; }
read -p "$(echo -e ${YLW}Password database renclouds: ${NC})" DB_PASS
[[ -z "$DB_PASS" ]] && { echo -e "${RED}[X] Password DB kosong!${NC}"; exit 1; }

echo -e "${GRN}[OK] Domain: $DOMAIN${NC}"

# ---------- INSTALL PAKET ----------
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt upgrade -y
apt install -y nginx php-fpm php-mysql php-curl php-mbstring php-xml \
  php-zip php-gd unzip curl wget git mariadb-server certbot \
  python3-certbot-nginx ufw fail2ban

PHP_VER=$(php -v | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
PHP_SOCK="unix:/run/php/php${PHP_VER}-fpm.sock"
echo -e "${GRN}[OK] PHP ${PHP_VER}${NC}"

# ---------- DATABASE ----------
systemctl enable --now mariadb

# FIX: pakai `sudo mysql` agar tidak gagal di MariaDB baru
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS renclouds CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'renclouds'@'localhost' IDENTIFIED BY '${DB_PASS}';
ALTER USER 'renclouds'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON renclouds.* TO 'renclouds'@'localhost';
FLUSH PRIVILEGES;
USE renclouds;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(120) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  role ENUM('user','admin') DEFAULT 'user',
  vps_quota INT DEFAULT 1,
  theme VARCHAR(10) DEFAULT 'light',
  bio TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS vps (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  hostname VARCHAR(100) NOT NULL,
  ip_address VARCHAR(45),
  os VARCHAR(50) DEFAULT 'Ubuntu 22.04',
  ram VARCHAR(20) DEFAULT '1GB',
  cpu VARCHAR(20) DEFAULT '1 vCPU',
  status ENUM('active','suspended','pending','rejected') DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS prompts (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  title VARCHAR(150),
  content TEXT,
  is_public TINYINT(1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS chat (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tickets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  subject VARCHAR(200),
  message TEXT,
  status ENUM('open','closed') DEFAULT 'open',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS announcements (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(200),
  content TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
SQL

# ============================================================
# FIX #1: Generate hash admin yang VALID lewat PHP
# ============================================================
ADMIN_HASH=$(php -r "echo password_hash('Ren12#', PASSWORD_DEFAULT);")
echo -e "${GRN}[OK] Admin hash generated: ${ADMIN_HASH:0:20}...${NC}"

# FIX #4: Pakai ON DUPLICATE KEY UPDATE agar re-install tetap sinkron
sudo mysql renclouds <<SQL
INSERT INTO users (username,email,password,role,vps_quota)
VALUES ('admin','admin@${DOMAIN}','${ADMIN_HASH}','admin',999)
ON DUPLICATE KEY UPDATE password=VALUES(password), role='admin', vps_quota=999;

INSERT IGNORE INTO announcements (title,content) VALUES
('Selamat Datang di RenClouds!','Nikmati VPS gratis, prompt AI, dan public chat real-time.');
SQL

# Verifikasi hash admin benar-benar valid
VERIFY=$(php -r "\$h='${ADMIN_HASH}'; echo password_verify('Ren12#', \$h) ? 'VALID' : 'INVALID';")
if [[ "$VERIFY" != "VALID" ]]; then
  echo -e "${RED}[X] FATAL: Hash admin tidak valid!${NC}"; exit 1
fi
echo -e "${GRN}[OK] Database + admin siap (hash terverifikasi).${NC}"

# ---------- WEB ROOT ----------
WEBROOT="/var/www/renclouds"
mkdir -p "$WEBROOT/api"
cd "$WEBROOT"

# ==================================================
#  config.php
# ==================================================
cat > config.php <<'PHP'
<?php
// FIX: session start aman + cookie security
if (session_status() === PHP_SESSION_NONE) {
    ini_set('session.cookie_httponly', 1);
    ini_set('session.use_only_cookies', 1);
    ini_set('session.cookie_samesite', 'Lax');
    ini_set('session.gc_maxlifetime', 86400);
    session_start();
}
define('DB_HOST','localhost');
define('DB_NAME','renclouds');
define('DB_USER','renclouds');
define('DB_PASS','__DB_PASS__');

function db(){
  static $pdo=null;
  if(!$pdo){
    try{
      $pdo=new PDO('mysql:host='.DB_HOST.';dbname='.DB_NAME.';charset=utf8mb4',
        DB_USER,DB_PASS,
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]);
    }catch(PDOException $e){ die('DB Error: '.$e->getMessage()); }
  }
  return $pdo;
}
function is_logged(){ return isset($_SESSION['user']); }
function is_admin(){ return is_logged() && ($_SESSION['user']['role']??'')==='admin'; }
function require_login(){ if(!is_logged()){ header('Location: index.php'); exit; } }
function require_admin(){ if(!is_admin()){ header('Location: dashboard.php?err=forbidden'); exit; } }
function e($s){ return htmlspecialchars($s ?? '',ENT_QUOTES,'UTF-8'); }
function theme(){ return $_SESSION['user']['theme'] ?? 'light'; }

function admin_badge($size=18){
  return '<svg class="verified-badge" width="'.$size.'" height="'.$size.'" viewBox="0 0 24 24" style="display:inline-block;vertical-align:middle;margin-left:4px;filter:drop-shadow(0 0 3px rgba(251,191,36,.8))">
    <path fill="url(#goldGrad)" stroke="#d97706" stroke-width="1.2"
      d="M12 1.5l2.6 2.1 3.3-.4 1.2 3.1 3.1 1.2-.4 3.3 2.1 2.6-2.1 2.6.4 3.3-3.1 1.2-1.2 3.1-3.3-.4L12 22.5l-2.6-2.1-3.3.4-1.2-3.1-3.1-1.2.4-3.3L-.9 12l2.1-2.6-.4-3.3 3.1-1.2 1.2-3.1 3.3.4L12 1.5z"/>
    <path fill="#fff" d="M10.6 16.2l-3.3-3.3 1.4-1.4 1.9 1.9 4.7-4.7 1.4 1.4-6.1 6.1z"/>
    <defs><linearGradient id="goldGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#fde68a"/><stop offset="50%" stop-color="#fbbf24"/>
      <stop offset="100%" stop-color="#f59e0b"/></linearGradient></defs>
  </svg>';
}
PHP
sed -i "s|__DB_PASS__|${DB_PASS}|g" config.php

# ==================================================
#  index.php — FIX LOGIN/REGISTER + MODAL TANPA RELOAD
# ==================================================
cat > index.php <<'PHP'
<?php
require __DIR__ . '/config.php';

// FIX: kalau sudah login, langsung redirect
if (is_logged()) {
  header('Location: '.($_SESSION['user']['role']==='admin'?'admin.php':'dashboard.php'));
  exit;
}

$tab   = $_GET['tab'] ?? 'login';
$error = '';
$ok    = isset($_GET['ok']) ? 'Registrasi berhasil, silakan login.' : '';

if ($_SERVER['REQUEST_METHOD']==='POST') {
  $a = $_POST['action'] ?? '';

  // ============ LOGIN ============
  if ($a==='login') {
    $tab = 'login';
    $u = trim($_POST['username'] ?? '');
    $p = $_POST['password'] ?? '';

    if ($u==='' || $p==='') {
      $error = 'Username dan password wajib diisi.';
    } else {
      try {
        $st = db()->prepare('SELECT * FROM users WHERE username=? OR email=? LIMIT 1');
        $st->execute([$u,$u]);
        $user = $st->fetch();

        if ($user && password_verify($p, $user['password'])) {
          // FIX #2: cegah session fixation
          session_regenerate_id(true);
          // FIX: jangan simpan password di session
          unset($user['password']);
          $_SESSION['user'] = $user;

          header('Location: '.($user['role']==='admin'?'admin.php':'dashboard.php'));
          exit;
        } else {
          $error = 'Username atau password salah.';
        }
      } catch (Exception $ex) {
        $error = 'Login error: '.$ex->getMessage();
      }
    }
  }

  // ============ REGISTER ============
  if ($a==='register') {
    $tab = 'register';
    $u  = trim($_POST['username'] ?? '');
    $em = trim($_POST['email'] ?? '');
    $p  = $_POST['password'] ?? '';

    if (strlen($u) < 3) {
      $error = 'Username minimal 3 karakter.';
    } elseif (!preg_match('/^[a-zA-Z0-9_.-]+$/', $u)) {
      $error = 'Username hanya boleh huruf, angka, titik, underscore, strip.';
    } elseif (!filter_var($em, FILTER_VALIDATE_EMAIL)) {
      $error = 'Email tidak valid.';
    } elseif (strlen($p) < 6) {
      $error = 'Password minimal 6 karakter.';
    } else {
      try {
        $st = db()->prepare('SELECT id FROM users WHERE username=? OR email=? LIMIT 1');
        $st->execute([$u,$em]);
        if ($st->fetch()) {
          $error = 'Username atau email sudah dipakai.';
        } else {
          db()->prepare('INSERT INTO users(username,email,password) VALUES(?,?,?)')
              ->execute([$u, $em, password_hash($p, PASSWORD_DEFAULT)]);
          header('Location: index.php?tab=login&ok=1');
          exit;
        }
      } catch (Exception $ex) {
        $error = 'Register error: '.$ex->getMessage();
      }
    }
  }
}

if (isset($_GET['err'])) {
  $error = $_GET['err']==='bad' ? 'Username/password salah.' : 'Terjadi kesalahan.';
}
$t = theme();
?>
<!DOCTYPE html>
<html lang="id" data-theme="<?= $t ?>">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RenClouds · Free VPS Panel & AI Prompt</title>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<style>
:root{--bg:#f5f7fb;--card:#fff;--text:#0f172a;--muted:#64748b;--border:rgba(0,0,0,.05);--shadow:rgba(0,0,0,.02)}
[data-theme="dark"]{--bg:#0b1220;--card:#111a2e;--text:#e2e8f0;--muted:#94a3b8;--border:rgba(255,255,255,.06);--shadow:rgba(0,0,0,.4)}
*{margin:0;padding:0;box-sizing:border-box;font-family:'Inter',sans-serif}
html{scroll-behavior:smooth}
body{background:var(--bg);color:var(--text);line-height:1.6;overflow-x:hidden;transition:background .3s,color .3s}

.navbar{display:flex;align-items:center;justify-content:space-between;padding:.8rem 2rem;
  background:color-mix(in srgb,var(--card) 85%,transparent);backdrop-filter:blur(14px);
  border-bottom:1px solid var(--border);position:sticky;top:0;z-index:100}
.logo{display:flex;align-items:center;gap:.6rem;font-weight:800;font-size:1.4rem;text-decoration:none;color:var(--text)}
.logo i{font-size:1.7rem;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.logo span{background:linear-gradient(135deg,#6366f1,#a855f7,#ec4899);-webkit-background-clip:text;background-clip:text;color:transparent}
.nav-right{display:flex;align-items:center;gap:.7rem}
.theme-toggle{width:40px;height:40px;border-radius:10px;background:var(--card);border:1px solid var(--border);color:var(--text);cursor:pointer;font-size:1rem;transition:.2s}
.theme-toggle:hover{transform:scale(1.1);background:#6366f1;color:#fff}
.nav-btn{display:inline-flex;align-items:center;gap:.5rem;padding:.6rem 1.3rem;border-radius:12px;font-weight:600;font-size:.9rem;text-decoration:none;transition:.2s;border:none;cursor:pointer}
.nav-btn-login{background:transparent;color:var(--text);border:1px solid var(--border)}
.nav-btn-login:hover{border-color:#6366f1;color:#6366f1}
.nav-btn-primary{background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;box-shadow:0 8px 20px -6px rgba(99,102,241,.5)}
.nav-btn-primary:hover{transform:translateY(-2px)}

.hero{max-width:1200px;margin:0 auto;padding:4rem 2rem 3rem;text-align:center}
.badge{display:inline-flex;align-items:center;gap:.5rem;background:rgba(34,197,94,.1);color:#15803d;font-weight:600;font-size:.85rem;padding:.45rem 1.1rem;border-radius:100px;margin-bottom:1.5rem;border:1px solid rgba(34,197,94,.25)}
[data-theme="dark"] .badge{color:#4ade80}
.badge i{color:#22c55e}
.hero h1{font-size:3.6rem;font-weight:800;line-height:1.15;letter-spacing:-1.8px;margin-bottom:1.2rem;color:var(--text)}
.hero h1 span{background:linear-gradient(135deg,#6366f1,#a855f7,#ec4899);-webkit-background-clip:text;background-clip:text;color:transparent}
.hero p{font-size:1.15rem;color:var(--muted);max-width:740px;margin:0 auto 2.5rem}
.hero-buttons{display:flex;gap:1rem;justify-content:center;flex-wrap:wrap;margin-bottom:2rem}
.btn-hero{display:inline-flex;align-items:center;gap:.6rem;padding:.9rem 1.8rem;border-radius:14px;font-weight:600;font-size:1rem;text-decoration:none;transition:.2s;cursor:pointer;border:none}
.btn-primary{background:linear-gradient(135deg,#22c55e,#16a34a);color:#fff;box-shadow:0 10px 25px -5px rgba(34,197,94,.45)}
.btn-primary:hover{transform:translateY(-2px)}
.btn-secondary{background:var(--card);color:var(--text);border:1px solid var(--border)}
.btn-secondary:hover{border-color:#6366f1;color:#6366f1}
.hero-stats{display:flex;justify-content:center;gap:3rem;flex-wrap:wrap;margin-top:2rem}
.stat{text-align:center}
.stat .num{font-size:1.8rem;font-weight:800;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .label{font-size:.85rem;color:var(--muted);font-weight:500}

.features{max-width:1200px;margin:0 auto;padding:2rem 2rem 4rem}
.section-title{text-align:center;margin-bottom:3rem}
.section-title h2{font-size:2.2rem;font-weight:800;letter-spacing:-.8px;color:var(--text);margin-bottom:.6rem}
.section-title p{color:var(--muted);font-size:1.05rem;max-width:600px;margin:0 auto}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(270px,1fr));gap:1.6rem}
.card{background:var(--card);padding:2rem 1.7rem;border-radius:22px;border:1px solid var(--border);box-shadow:0 4px 20px var(--shadow);transition:.25s ease}
.card:hover{transform:translateY(-5px);border-color:rgba(99,102,241,.25)}
.card-icon{width:60px;height:60px;display:flex;align-items:center;justify-content:center;border-radius:16px;margin-bottom:1.2rem;font-size:1.7rem;background:linear-gradient(135deg,rgba(99,102,241,.12),rgba(168,85,247,.12));color:#6366f1}
.card h3{font-size:1.15rem;font-weight:700;margin-bottom:.5rem;color:var(--text)}
.card p{color:var(--muted);font-size:.92rem}

.reveal{opacity:0;transform:translateY(40px);transition:opacity .8s cubic-bezier(.16,1,.3,1),transform .8s cubic-bezier(.16,1,.3,1)}
.reveal.active{opacity:1;transform:translateY(0)}
.stagger>*{opacity:0;transform:translateY(30px);transition:opacity .6s cubic-bezier(.16,1,.3,1),transform .6s cubic-bezier(.16,1,.3,1)}
.stagger.active>*{opacity:1;transform:translateY(0)}
.stagger.active>*:nth-child(1){transition-delay:.05s}
.stagger.active>*:nth-child(2){transition-delay:.15s}
.stagger.active>*:nth-child(3){transition-delay:.25s}
.stagger.active>*:nth-child(4){transition-delay:.35s}
.stagger.active>*:nth-child(5){transition-delay:.45s}
.stagger.active>*:nth-child(6){transition-delay:.55s}

.modal-overlay{position:fixed;inset:0;background:rgba(15,23,42,.6);backdrop-filter:blur(6px);display:none;align-items:center;justify-content:center;z-index:999;padding:20px}
.modal-overlay.active{display:flex}
.modal{background:var(--card);width:100%;max-width:430px;border-radius:24px;padding:2.5rem;box-shadow:0 25px 60px rgba(0,0,0,.4);position:relative;animation:pop .3s ease}
@keyframes pop{from{transform:scale(.95);opacity:0}to{transform:scale(1);opacity:1}}
.modal-close{position:absolute;top:1rem;right:1rem;width:36px;height:36px;border-radius:10px;background:var(--bg);border:none;cursor:pointer;color:var(--muted);font-size:1.1rem}
.modal-close:hover{color:var(--text)}
.modal-logo{text-align:center;font-size:1.8rem;font-weight:800;margin-bottom:.3rem;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.modal-sub{text-align:center;color:var(--muted);font-size:.9rem;margin-bottom:1.6rem}
.tabs{display:flex;background:var(--bg);border-radius:12px;padding:4px;margin-bottom:1.5rem}
.tabs button{flex:1;text-align:center;padding:.6rem;border-radius:9px;border:none;background:transparent;font-weight:600;font-size:.9rem;color:var(--muted);transition:.2s;cursor:pointer;font-family:inherit}
.tabs button.active{background:var(--card);color:#6366f1;box-shadow:0 2px 8px rgba(0,0,0,.06)}
.field{margin-bottom:1rem}
.field label{display:block;font-size:.85rem;font-weight:600;color:var(--text);margin-bottom:.4rem}
.field input{width:100%;padding:.75rem 1rem;border:1px solid var(--border);border-radius:12px;font-size:.95rem;background:var(--bg);color:var(--text);transition:.2s}
.field input:focus{outline:none;border-color:#6366f1;box-shadow:0 0 0 3px rgba(99,102,241,.15)}
.btn-submit{width:100%;padding:.85rem;border:none;border-radius:12px;font-weight:700;font-size:1rem;color:#fff;cursor:pointer;background:linear-gradient(135deg,#6366f1,#a855f7);transition:.2s;box-shadow:0 8px 20px -6px rgba(99,102,241,.5)}
.btn-submit:hover{transform:translateY(-2px)}
.msg{padding:.7rem 1rem;border-radius:10px;font-size:.85rem;margin-bottom:1rem;display:flex;gap:.5rem;align-items:center}
.err{background:#fef2f2;color:#dc2626;border:1px solid #fecaca}
[data-theme="dark"] .err{background:#7f1d1d;color:#fecaca;border-color:#991b1b}
.ok{background:#f0fdf4;color:#16a34a;border:1px solid #bbf7d0}
[data-theme="dark"] .ok{background:#14532d;color:#86efac;border-color:#166534}

footer{background:var(--card);border-top:1px solid var(--border);padding:2.5rem 2rem;text-align:center;color:var(--muted);font-size:.88rem}
footer .socials{display:flex;justify-content:center;gap:1rem;margin-top:1rem}
footer .socials a{width:40px;height:40px;display:flex;align-items:center;justify-content:center;border-radius:10px;background:var(--bg);color:var(--muted);font-size:1.1rem;transition:.2s}
footer .socials a:hover{background:#6366f1;color:#fff;transform:translateY(-3px)}

@media(max-width:768px){
  .hero h1{font-size:2.4rem}.hero p{font-size:1rem}.hero-stats{gap:1.8rem}
  .navbar{padding:.7rem 1.2rem}.logo{font-size:1.2rem}.nav-btn-login{display:none}
  .section-title h2{font-size:1.8rem}
}
</style>
</head>
<body>

<nav class="navbar">
  <a href="#" class="logo"><i class="fas fa-cloud-bolt"></i> <span>RenClouds</span></a>
  <div class="nav-right">
    <button class="theme-toggle" onclick="toggleTheme()" title="Toggle Dark Mode">
      <i class="fas fa-moon" id="themeIcon"></i>
    </button>
    <button class="nav-btn nav-btn-login" onclick="openModal('login')">
      <i class="fas fa-right-to-bracket"></i> Login
    </button>
    <button class="nav-btn nav-btn-primary" onclick="openModal('register')">
      <i class="fas fa-user-plus"></i> Register
    </button>
  </div>
</nav>

<section class="hero">
  <div class="badge reveal"><i class="fas fa-circle"></i> Server Online · Gratis Sepenuhnya</div>
  <h1 class="reveal">Free VPS Panel <span>RenClouds</span><br>Deploy Instan, Selalu Online</h1>
  <p class="reveal">Dapatkan VPS gratis dengan panel modern, performa tinggi, dan setup kilat. Kelola bot, website, atau project kamu langsung dari browser — plus AI Assistant 24/7 & Public Chat Real-Time.</p>
  <div class="hero-buttons reveal">
    <button class="btn-hero btn-primary" onclick="openModal('register')">
      <i class="fas fa-gift"></i> Ambil VPS Gratis
    </button>
    <a href="#fitur" class="btn-hero btn-secondary">
      <i class="fas fa-circle-info"></i> Lihat Fitur
    </a>
  </div>
  <div class="hero-stats stagger">
    <div class="stat"><div class="num">10K+</div><div class="label">Pengguna Aktif</div></div>
    <div class="stat"><div class="num">99.9%</div><div class="label">Uptime Server</div></div>
    <div class="stat"><div class="num">24/7</div><div class="label">Support Admin</div></div>
    <div class="stat"><div class="num">0 Rp</div><div class="label">Biaya Selamanya</div></div>
  </div>
</section>

<section class="features" id="fitur">
  <div class="section-title reveal">
    <h2>Fitur Unggulan RenClouds</h2>
    <p>Semua yang kamu butuhkan untuk menjalankan project di cloud — cepat, aman, dan gratis.</p>
  </div>
  <div class="grid stagger">
    <div class="card"><div class="card-icon"><i class="fas fa-bolt"></i></div><h3>Deploy Instan</h3><p>Buat server VPS hanya dalam hitungan detik. Tanpa antre, tanpa konfigurasi ribet.</p></div>
    <div class="card"><div class="card-icon"><i class="fas fa-server"></i></div><h3>Panel Modern</h3><p>Panel kontrol intuitif untuk mengelola file, database, dan resource langsung dari browser.</p></div>
    <div class="card"><div class="card-icon"><i class="fas fa-robot"></i></div><h3>AI Assistant 24/7</h3><p>Integrasi AI: catat, cari info, dan berpikir bersama AI kapan pun kamu butuh.</p></div>
    <div class="card"><div class="card-icon"><i class="fas fa-comments"></i></div><h3>Public Chat Real-Time</h3><p>Ngobrol bareng member lain & admin. Admin punya badge emas bergerigi otomatis.</p></div>
    <div class="card"><div class="card-icon"><i class="fas fa-moon"></i></div><h3>Dark Mode</h3><p>Mode gelap yang nyaman untuk mata, tinggal toggle di navbar.</p></div>
    <div class="card"><div class="card-icon"><i class="fas fa-infinity"></i></div><h3>Gratis Selamanya</h3><p>Tanpa biaya tersembunyi, tanpa masa aktif. Nikmati VPS gratis selama-lamanya.</p></div>
  </div>
</section>

<footer>
  <p>&copy; <?= date('Y') ?> RenClouds. All rights reserved. Dibuat dengan <i class="fas fa-heart" style="color:#ec4899"></i> untuk komunitas.</p>
  <div class="socials">
    <a href="https://t.me/renclzaz" target="_blank"><i class="fab fa-telegram"></i></a>
    <a href="https://t.me/rencloudspanelfree" target="_blank"><i class="fab fa-telegram-plane"></i></a>
    <a href="https://youtube.com/@renmodz45?si=slqTL-hiHaz5WZAV" target="_blank"><i class="fab fa-youtube"></i></a>
  </div>
</footer>

<div class="modal-overlay" id="authModal">
  <div class="modal">
    <button class="modal-close" onclick="closeModal()"><i class="fas fa-times"></i></button>
    <div class="modal-logo"><i class="fas fa-cloud-bolt"></i> RenClouds</div>
    <div class="modal-sub">Free VPS Panel &amp; AI Prompt</div>

    <?php if($error): ?>
      <div class="msg err"><i class="fas fa-triangle-exclamation"></i> <?= e($error) ?></div>
    <?php endif; ?>
    <?php if($ok): ?>
      <div class="msg ok"><i class="fas fa-check"></i> <?= e($ok) ?></div>
    <?php endif; ?>

    <div class="tabs">
      <button type="button" data-tab="login" class="<?= $tab==='login'?'active':'' ?>" onclick="switchTab('login')">Login</button>
      <button type="button" data-tab="register" class="<?= $tab==='register'?'active':'' ?>" onclick="switchTab('register')">Register</button>
    </div>

    <form method="post" id="form-login" style="<?= $tab==='login'?'':'display:none' ?>">
      <input type="hidden" name="action" value="login">
      <div class="field"><label>Username / Email</label><input name="username" required autocomplete="username"></div>
      <div class="field"><label>Password</label><input type="password" name="password" required autocomplete="current-password"></div>
      <button class="btn-submit"><i class="fas fa-right-to-bracket"></i> Login</button>
    </form>

    <form method="post" id="form-register" style="<?= $tab==='register'?'':'display:none' ?>">
      <input type="hidden" name="action" value="register">
      <div class="field"><label>Username</label><input name="username" required minlength="3" autocomplete="username"></div>
      <div class="field"><label>Email</label><input type="email" name="email" required autocomplete="email"></div>
      <div class="field"><label>Password</label><input type="password" name="password" required minlength="6" autocomplete="new-password"></div>
      <button class="btn-submit"><i class="fas fa-user-plus"></i> Daftar</button>
    </form>
  </div>
</div>

<script>
function toggleTheme(){
  const html = document.documentElement;
  const next = html.getAttribute('data-theme')==='dark'?'light':'dark';
  html.setAttribute('data-theme', next);
  fetch('api/set_theme.php?theme='+next).catch(()=>{});
  document.getElementById('themeIcon').className = next==='dark'?'fas fa-sun':'fas fa-moon';
}
<?php if($t==='dark'): ?>
document.getElementById('themeIcon').className = 'fas fa-sun';
<?php endif; ?>

// FIX #3: modal tanpa reload, tab switch via JS
function openModal(tab){
  document.getElementById('authModal').classList.add('active');
  switchTab(tab);
}
function closeModal(){
  document.getElementById('authModal').classList.remove('active');
  if(location.search) history.replaceState(null,'',location.pathname);
}
function switchTab(tab){
  document.querySelectorAll('.tabs button').forEach(b=>{
    b.classList.toggle('active', b.dataset.tab===tab);
  });
  document.getElementById('form-login').style.display    = tab==='login'    ? '' : 'none';
  document.getElementById('form-register').style.display = tab==='register' ? '' : 'none';
  history.replaceState(null,'','?tab='+tab);
}
<?php if($error || $ok): ?>
document.getElementById('authModal').classList.add('active');
<?php endif; ?>
document.getElementById('authModal').addEventListener('click', function(e){
  if(e.target===this) closeModal();
});

// Scroll animations
document.addEventListener('DOMContentLoaded', function(){
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('active');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -60px 0px' });

  document.querySelectorAll('.reveal, .stagger').forEach(el => observer.observe(el));

  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e){
      const targetId = this.getAttribute('href');
      if (targetId === '#') return;
      const target = document.querySelector(targetId);
      if (target) { e.preventDefault(); target.scrollIntoView({behavior:'smooth',block:'start'}); }
    });
  });
});
</script>
</body>
</html>
PHP

# ==================================================
#  api/set_theme.php — FIX path pakai __DIR__
# ==================================================
cat > api/set_theme.php <<'PHP'
<?php
require __DIR__ . '/../config.php';
$t = $_GET['theme'] ?? 'light';
if($t!=='dark'&&$t!=='light') $t='light';
if(is_logged()){
  db()->prepare('UPDATE users SET theme=? WHERE id=?')->execute([$t,$_SESSION['user']['id']]);
  $_SESSION['user']['theme']=$t;
}
header('Content-Type: application/json');
echo json_encode(['ok'=>true]);
PHP

# ==================================================
#  dashboard.php (User Panel)
# ==================================================
cat > dashboard.php <<'PHP'
<?php
require __DIR__ . '/config.php';
require_login();
$u = $_SESSION['user'];
$page = $_GET['page'] ?? 'home';

if ($_SERVER['REQUEST_METHOD']==='POST') {
  $act = $_POST['act'] ?? '';
  if ($act==='logout') { session_destroy(); header('Location: index.php'); exit; }
  if ($act==='add_vps') {
    $h = trim($_POST['hostname'] ?? '');
    if ($h) db()->prepare('INSERT INTO vps(user_id,hostname) VALUES(?,?)')->execute([$u['id'],$h]);
    header('Location: dashboard.php?page=vps'); exit;
  }
  if ($act==='add_prompt') {
    $t = trim($_POST['title'] ?? ''); $c = trim($_POST['content'] ?? ''); $pub = isset($_POST['public'])?1:0;
    if ($t && $c) db()->prepare('INSERT INTO prompts(user_id,title,content,is_public) VALUES(?,?,?,?)')->execute([$u['id'],$t,$c,$pub]);
    header('Location: dashboard.php?page=prompt'); exit;
  }
  if ($act==='send_chat') {
    $m = trim($_POST['message'] ?? '');
    if ($m) db()->prepare('INSERT INTO chat(user_id,message) VALUES(?,?)')->execute([$u['id'],$m]);
    header('Location: dashboard.php?page=chat'); exit;
  }
  if ($act==='set_theme') {
    $t = $_POST['theme'] ?? 'light';
    if($t!=='dark'&&$t!=='light') $t='light';
    db()->prepare('UPDATE users SET theme=? WHERE id=?')->execute([$t,$u['id']]);
    $_SESSION['user']['theme']=$t;
    header('Location: dashboard.php?page=profile'); exit;
  }
  if ($act==='add_ticket') {
    $s = trim($_POST['subject'] ?? ''); $m = trim($_POST['message'] ?? '');
    if ($s && $m) db()->prepare('INSERT INTO tickets(user_id,subject,message) VALUES(?,?,?)')->execute([$u['id'],$s,$m]);
    header('Location: dashboard.php?page=ticket'); exit;
  }
}

$vps = db()->prepare('SELECT * FROM vps WHERE user_id=? ORDER BY created_at DESC');
$vps->execute([$u['id']]); $vps=$vps->fetchAll();

$prompts = db()->prepare('SELECT * FROM prompts WHERE user_id=? ORDER BY created_at DESC');
$prompts->execute([$u['id']]); $prompts=$prompts->fetchAll();

$chat = db()->query("SELECT c.*,u.username,u.role FROM chat c JOIN users u ON u.id=c.user_id ORDER BY c.id DESC LIMIT 100")->fetchAll();
$chat = array_reverse($chat);

$tickets = db()->prepare('SELECT * FROM tickets WHERE user_id=? ORDER BY id DESC');
$tickets->execute([$u['id']]); $tickets=$tickets->fetchAll();

$ann = db()->query('SELECT * FROM announcements ORDER BY id DESC LIMIT 3')->fetchAll();

$t = theme();
?>
<!DOCTYPE html>
<html lang="id" data-theme="<?= $t ?>">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Dashboard · RenClouds</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root{--bg:#f5f7fb;--card:#fff;--text:#0f172a;--muted:#64748b;--border:rgba(0,0,0,.05)}
[data-theme="dark"]{--bg:#0b1220;--card:#111a2e;--text:#e2e8f0;--muted:#94a3b8;--border:rgba(255,255,255,.06)}
*{margin:0;padding:0;box-sizing:border-box;font-family:'Inter',sans-serif}
body{background:var(--bg);color:var(--text);min-height:100vh;transition:background .3s,color .3s}
.topbar{background:var(--card);border-bottom:1px solid var(--border);padding:.9rem 2rem;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:10}
.logo{font-weight:800;font-size:1.2rem;color:#6366f1;display:flex;align-items:center;gap:.5rem}
.userbox{display:flex;align-items:center;gap:1rem;font-size:.9rem}
.avatar{width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700}
.btn{display:inline-flex;align-items:center;gap:.5rem;padding:.55rem 1.1rem;border-radius:10px;font-weight:600;font-size:.88rem;text-decoration:none;border:none;cursor:pointer;transition:.2s}
.btn-primary{background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;box-shadow:0 6px 16px -6px rgba(99,102,241,.5)}
.btn-primary:hover{transform:translateY(-2px)}
.btn-danger{background:#fef2f2;color:#dc2626;border:1px solid #fecaca}
.btn-danger:hover{background:#fee2e2}
.theme-toggle{width:36px;height:36px;border-radius:10px;background:var(--bg);border:1px solid var(--border);color:var(--text);cursor:pointer;font-size:.95rem;transition:.2s}
.theme-toggle:hover{transform:scale(1.1);background:#6366f1;color:#fff}
.layout{display:flex;min-height:calc(100vh - 62px)}
.sidebar{width:240px;background:var(--card);border-right:1px solid var(--border);padding:1.2rem .8rem}
.sidebar a{display:flex;align-items:center;gap:.8rem;padding:.8rem 1rem;border-radius:12px;color:var(--muted);text-decoration:none;font-weight:500;font-size:.9rem;margin-bottom:.3rem;transition:.2s}
.sidebar a:hover,.sidebar a.active{background:linear-gradient(135deg,rgba(99,102,241,.1),rgba(168,85,247,.1));color:#6366f1}
.sidebar a i{width:20px;text-align:center}
.content{flex:1;padding:2rem;max-width:1100px;margin:0 auto}
.card{background:var(--card);border-radius:20px;padding:1.6rem;border:1px solid var(--border);box-shadow:0 4px 20px rgba(0,0,0,.03);margin-bottom:1.2rem;animation:fadeUp .5s ease}
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
.card h3{font-size:1.05rem;margin-bottom:1rem;display:flex;align-items:center;gap:.5rem}
.card h3 i{color:#6366f1}
.hero{background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;border-radius:20px;padding:2rem;margin-bottom:1.5rem;animation:fadeUp .5s ease}
.hero h2{font-size:1.6rem;margin-bottom:.4rem}
.hero p{opacity:.9;font-size:.95rem}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem;margin-bottom:1.5rem}
.stat{background:var(--card);border-radius:16px;padding:1.2rem;border:1px solid var(--border);animation:fadeUp .5s ease}
.stat .num{font-size:1.8rem;font-weight:800;background:linear-gradient(135deg,#6366f1,#a855f7);-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .lbl{font-size:.82rem;color:var(--muted);font-weight:500}
table{width:100%;border-collapse:collapse;font-size:.88rem}
th,td{padding:.7rem .5rem;text-align:left;border-bottom:1px solid var(--border)}
th{color:var(--muted);font-weight:600;font-size:.78rem;text-transform:uppercase}
.badge{display:inline-block;padding:.2rem .7rem;border-radius:100px;font-size:.75rem;font-weight:600}
.bg-active{background:#f0fdf4;color:#16a34a}
.bg-pending{background:#fffbeb;color:#d97706}
.bg-suspended{background:#fef2f2;color:#dc2626}
.bg-rejected{background:#fef2f2;color:#991b1b}
input,textarea,select{width:100%;padding:.7rem 1rem;border:1px solid var(--border);border-radius:10px;font-size:.9rem;font-family:inherit;margin-bottom:.6rem;background:var(--bg);color:var(--text)}
input:focus,textarea:focus,select:focus{outline:none;border-color:#6366f1;box-shadow:0 0 0 3px rgba(99,102,241,.15)}
.chat-box{height:420px;overflow-y:auto;background:var(--bg);border-radius:14px;padding:1rem;border:1px solid var(--border);margin-bottom:1rem}
.chat-msg{display:flex;gap:.6rem;margin-bottom:.8rem;align-items:flex-start}
.chat-msg .av{width:34px;height:34px;border-radius:50%;background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:.8rem;flex-shrink:0}
.chat-msg.admin .av{background:linear-gradient(135deg,#fbbf24,#f59e0b)}
.chat-msg .body{background:var(--card);padding:.55rem .9rem;border-radius:12px;font-size:.88rem;box-shadow:0 1px 3px rgba(0,0,0,.04);max-width:75%}
.chat-msg.admin .body{background:linear-gradient(135deg,#fffbeb,#fef3c7);border:1px solid #fde68a;color:#78350f}
.chat-msg .name{font-weight:700;font-size:.82rem;margin-bottom:.15rem;display:flex;align-items:center;gap:.2rem}
.chat-msg.admin .name{color:#b45309}
.chat-msg .time{font-size:.7rem;color:var(--muted);margin-top:.2rem}
.chat-form{display:flex;gap:.5rem}
.chat-form input{flex:1;margin:0}
.chat-form button{padding:.7rem 1.2rem;border:none;border-radius:10px;background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;font-weight:600;cursor:pointer;transition:.2s}
.chat-form button:hover{transform:translateY(-2px)}
.empty{text-align:center;color:var(--muted);padding:2rem;font-size:.9rem}
@media(max-width:768px){
  .layout{flex-direction:column}
  .sidebar{width:100%;border-right:none;border-bottom:1px solid var(--border);display:flex;overflow-x:auto;padding:.6rem}
  .sidebar a{white-space:nowrap;margin-bottom:0;margin-right:.3rem}
  .sidebar hr{display:none}
  .content{padding:1rem}
}
</style>
</head>
<body>

<div class="topbar">
  <div class="logo"><i class="fas fa-cloud-bolt"></i> RenClouds</div>
  <div class="userbox">
    <button class="theme-toggle" onclick="toggleTheme()"><i class="fas fa-moon" id="themeIcon"></i></button>
    <div class="avatar"><?= strtoupper(substr($u['username'],0,1)) ?></div>
    <span><strong><?= e($u['username']) ?></strong></span>
    <form method="post" style="display:inline">
      <input type="hidden" name="act" value="logout">
      <button class="btn btn-danger"><i class="fas fa-right-from-bracket"></i> Logout</button>
    </form>
  </div>
</div>

<div class="layout">
  <aside class="sidebar">
    <a href="?page=home" class="<?= $page==='home'?'active':'' ?>"><i class="fas fa-house"></i> Beranda</a>
    <a href="?page=vps" class="<?= $page==='vps'?'active':'' ?>"><i class="fas fa-server"></i> Get VPS</a>
    <a href="?page=prompt" class="<?= $page==='prompt'?'active':'' ?>"><i class="fas fa-terminal"></i> Prompt AI</a>
    <a href="?page=chat" class="<?= $page==='chat'?'active':'' ?>"><i class="fas fa-comments"></i> Public Chat</a>
    <a href="?page=ticket" class="<?= $page==='ticket'?'active':'' ?>"><i class="fas fa-ticket"></i> Tiket Support</a>
    <a href="?page=profile" class="<?= $page==='profile'?'active':'' ?>"><i class="fas fa-user"></i> Profil</a>
    <hr style="border:none;border-top:1px solid var(--border);margin:.8rem 0">
    <a href="index.php"><i class="fas fa-arrow-left"></i> Keluar</a>
  </aside>

  <main class="content">
  <?php if($page==='home'): ?>
    <div class="hero">
      <h2>Selamat datang, <?= e($u['username']) ?>! 👋</h2>
      <p>Kelola VPS gratis, simpan prompt AI, dan ngobrol di Public Chat.</p>
    </div>
    <div class="grid">
      <div class="stat"><div class="num"><?= count($vps) ?></div><div class="lbl">VPS Aktif</div></div>
      <div class="stat"><div class="num"><?= count($prompts) ?></div><div class="lbl">Prompt Tersimpan</div></div>
      <div class="stat"><div class="num"><?= $u['vps_quota'] ?></div><div class="lbl">Kuota VPS</div></div>
    </div>
    <?php foreach($ann as $a): ?>
      <div class="card" style="border-left:4px solid #6366f1">
        <h3><i class="fas fa-bullhorn"></i> <?= e($a['title']) ?></h3>
        <p style="color:var(--muted);font-size:.9rem"><?= nl2br(e($a['content'])) ?></p>
      </div>
    <?php endforeach; ?>

  <?php elseif($page==='vps'): ?>
    <div class="card">
      <h3><i class="fas fa-server"></i> Request VPS Gratis</h3>
      <form method="post">
        <input type="hidden" name="act" value="add_vps">
        <input name="hostname" placeholder="Hostname contoh mybot.renclouds.com" required>
        <button class="btn btn-primary"><i class="fas fa-paper-plane"></i> Kirim Request</button>
      </form>
    </div>
    <div class="card">
      <h3><i class="fas fa-list"></i> Daftar VPS Kamu</h3>
      <?php if(!$vps): ?>
        <div class="empty"><i class="fas fa-inbox" style="font-size:2rem;display:block;margin-bottom:.5rem"></i>Belum ada VPS.</div>
      <?php else: ?>
      <table>
        <thead><tr><th>Hostname</th><th>IP</th><th>OS</th><th>Status</th></tr></thead>
        <tbody>
        <?php foreach($vps as $v): ?>
          <tr>
            <td><strong><?= e($v['hostname']) ?></strong></td>
            <td><?= e($v['ip_address'] ?: '-') ?></td>
            <td><?= e($v['os']) ?></td>
            <td><span class="badge bg-<?= $v['status'] ?>"><?= e($v['status']) ?></span></td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
      <?php endif; ?>
    </div>

  <?php elseif($page==='prompt'): ?>
    <div class="card">
      <h3><i class="fas fa-plus-circle"></i> Simpan Prompt AI</h3>
      <form method="post">
        <input type="hidden" name="act" value="add_prompt">
        <input name="title" placeholder="Judul prompt" required>
        <textarea name="content" rows="4" placeholder="Isi prompt..." required></textarea>
        <label style="display:flex;align-items:center;gap:.5rem;font-size:.9rem;margin-bottom:.6rem">
          <input type="checkbox" name="public" style="width:auto"> Publik (bisa dilihat user lain)
        </label>
        <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan</button>
      </form>
    </div>
    <div class="card">
      <h3><i class="fas fa-bookmark"></i> Prompt Tersimpan</h3>
      <?php if(!$prompts): ?>
        <div class="empty">Belum ada prompt.</div>
      <?php else: foreach($prompts as $p): ?>
        <div style="background:var(--bg);border:1px solid var(--border);border-radius:12px;padding:1rem;margin-bottom:.8rem">
          <strong style="color:#6366f1"><?= e($p['title']) ?><?= $p['is_public']?' <span style="font-size:.7rem;background:#22c55e;color:#fff;padding:.1rem .5rem;border-radius:100px">PUBLIK</span>':'' ?></strong>
          <p style="font-size:.85rem;color:var(--muted);margin-top:.3rem;white-space:pre-wrap"><?= e($p['content']) ?></p>
        </div>
      <?php endforeach; endif; ?>
    </div>

  <?php elseif($page==='chat'): ?>
    <div class="card">
      <h3><i class="fas fa-comments"></i> Public Chat <span style="background:#ef4444;color:#fff;font-size:.7rem;padding:.15rem .55rem;border-radius:100px;margin-left:.4rem">LIVE</span></h3>
      <div class="chat-box" id="chatBox">
        <?php if(!$chat): ?>
          <div class="empty">Belum ada pesan. Jadilah yang pertama!</div>
        <?php else: foreach($chat as $c): $isAdmin = $c['role']==='admin'; ?>
          <div class="chat-msg <?= $isAdmin?'admin':'' ?>">
            <div class="av"><?= strtoupper(substr($c['username'],0,1)) ?></div>
            <div class="body">
              <div class="name"><?= e($c['username']) ?><?= $isAdmin ? admin_badge(16) : '' ?></div>
              <div><?= nl2br(e($c['message'])) ?></div>
              <div class="time"><?= date('H:i', strtotime($c['created_at'])) ?></div>
            </div>
          </div>
        <?php endforeach; endif; ?>
      </div>
      <form method="post" class="chat-form">
        <input type="hidden" name="act" value="send_chat">
        <input name="message" placeholder="Tulis pesan..." required autocomplete="off">
        <button><i class="fas fa-paper-plane"></i> Kirim</button>
      </form>
    </div>
    <script>
      const box = document.getElementById('chatBox');
      if (box) box.scrollTop = box.scrollHeight;
      setInterval(() => {
        fetch('api/chat_feed.php').then(r=>r.text()).then(html=>{
          if (box && html.trim()) { box.innerHTML = html; box.scrollTop = box.scrollHeight; }
        }).catch(()=>{});
      }, 3000);
    </script>

  <?php elseif($page==='ticket'): ?>
    <div class="card">
      <h3><i class="fas fa-ticket"></i> Buat Tiket Support</h3>
      <form method="post">
        <input type="hidden" name="act" value="add_ticket">
        <input name="subject" placeholder="Subjek" required>
        <textarea name="message" rows="3" placeholder="Masalah..." required></textarea>
        <button class="btn btn-primary"><i class="fas fa-paper-plane"></i> Kirim</button>
      </form>
    </div>
    <div class="card">
      <h3><i class="fas fa-inbox"></i> Tiket Saya</h3>
      <?php if(!$tickets): ?>
        <div class="empty">Belum ada tiket.</div>
      <?php else: foreach($tickets as $tk): ?>
        <div style="background:var(--bg);border:1px solid var(--border);border-radius:12px;padding:1rem;margin-bottom:.8rem">
          <strong><?= e($tk['subject']) ?></strong>
          <span class="badge <?= $tk['status']==='open'?'bg-pending':'bg-active' ?>"><?= $tk['status'] ?></span>
          <p style="font-size:.85rem;color:var(--muted);margin-top:.3rem"><?= nl2br(e($tk['message'])) ?></p>
        </div>
      <?php endforeach; endif; ?>
    </div>

  <?php elseif($page==='profile'): ?>
    <div class="card">
      <h3><i class="fas fa-user"></i> Profil</h3>
      <p><strong>Username:</strong> <?= e($u['username']) ?></p>
      <p><strong>Email:</strong> <?= e($u['email']) ?></p>
      <p><strong>Role:</strong> <?= e($u['role']) ?></p>
      <p><strong>Kuota VPS:</strong> <?= (int)$u['vps_quota'] ?></p>
    </div>
    <div class="card">
      <h3><i class="fas fa-palette"></i> Tema</h3>
      <form method="post">
        <input type="hidden" name="act" value="set_theme">
        <select name="theme">
          <option value="light" <?= $t==='light'?'selected':'' ?>>Light</option>
          <option value="dark" <?= $t==='dark'?'selected':'' ?>>Dark</option>
        </select>
        <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan Tema</button>
      </form>
    </div>

  <?php endif; ?>
  </main>
</div>

<script>
function toggleTheme(){
  const html = document.documentElement;
  const next = html.getAttribute('data-theme')==='dark'?'light':'dark';
  html.setAttribute('data-theme', next);
  fetch('api/set_theme.php?theme='+next).catch(()=>{});
  document.getElementById('themeIcon').className = next==='dark'?'fas fa-sun':'fas fa-moon';
}
<?php if($t==='dark'): ?>
document.getElementById('themeIcon').className = 'fas fa-sun';
<?php endif; ?>
</script>
</body>
</html>
PHP

# ==================================================
#  api/chat_feed.php
# ==================================================
cat > api/chat_feed.php <<'PHP'
<?php
require __DIR__ . '/../config.php';
require_login();

$chat = db()->query("SELECT c.*,u.username,u.role FROM chat c JOIN users u ON u.id=c.user_id ORDER BY c.id DESC LIMIT 100")->fetchAll();
$chat = array_reverse($chat);
if(!$chat){ echo '<div class="empty">Belum ada pesan. Jadilah yang pertama!</div>'; exit; }

foreach($chat as $c){
  $isAdmin = $c['role']==='admin';
  echo '<div class="chat-msg '.($isAdmin?'admin':'').'">';
  echo '<div class="av">'.strtoupper(substr($c['username'],0,1)).'</div>';
  echo '<div class="body">';
  echo '<div class="name">'.e($c['username']).($isAdmin?admin_badge(16):'').'</div>';
  echo '<div>'.nl2br(e($c['message'])).'</div>';
  echo '<div class="time">'.date('H:i', strtotime($c['created_at'])).'</div>';
  echo '</div></div>';
}
PHP

# ==================================================
#  admin.php (Admin Panel)
# ==================================================
cat > admin.php <<'PHP'
<?php
require __DIR__ . '/config.php';
require_admin();
$u = $_SESSION['user'];

if ($_SERVER['REQUEST_METHOD']==='POST') {
  $act = $_POST['act'] ?? '';
  if ($act==='logout') { session_destroy(); header('Location: index.php'); exit; }
  if ($act==='del_user' && isset($_POST['id'])) {
    db()->prepare('DELETE FROM users WHERE id=? AND role!="admin"')->execute([(int)$_POST['id']]);
    header('Location: admin.php?page=users'); exit;
  }
  if ($act==='vps_status' && isset($_POST['id'], $_POST['status'])) {
    db()->prepare('UPDATE vps SET status=? WHERE id=?')->execute([$_POST['status'], (int)$_POST['id']]);
    header('Location: admin.php?page=vps'); exit;
  }
  if ($act==='send_chat') {
    $m = trim($_POST['message'] ?? '');
    if ($m) db()->prepare('INSERT INTO chat(user_id,message) VALUES(?,?)')->execute([$u['id'],$m]);
    header('Location: admin.php?page=chat'); exit;
  }
  if ($act==='del_chat' && isset($_POST['id'])) {
    db()->prepare('DELETE FROM chat WHERE id=?')->execute([(int)$_POST['id']]);
    header('Location: admin.php?page=chat'); exit;
  }
  if ($act==='del_ticket' && isset($_POST['id'])) {
    db()->prepare('DELETE FROM tickets WHERE id=?')->execute([(int)$_POST['id']]);
    header('Location: admin.php?page=tickets'); exit;
  }
  if ($act==='ticket_status' && isset($_POST['id'], $_POST['status'])) {
    db()->prepare('UPDATE tickets SET status=? WHERE id=?')->execute([$_POST['status'], (int)$_POST['id']]);
    header('Location: admin.php?page=tickets'); exit;
  }
  if ($act==='add_ann') {
    $t = trim($_POST['title'] ?? ''); $c = trim($_POST['content'] ?? '');
    if ($t && $c) db()->prepare('INSERT INTO announcements(title,content) VALUES(?,?)')->execute([$t,$c]);
    header('Location: admin.php?page=ann'); exit;
  }
  if ($act==='del_ann' && isset($_POST['id'])) {
    db()->prepare('DELETE FROM announcements WHERE id=?')->execute([(int)$_POST['id']]);
    header('Location: admin.php?page=ann'); exit;
  }
}

$page = $_GET['page'] ?? 'home';
$stats = [
  'users'   => db()->query('SELECT COUNT(*) c FROM users')->fetch()['c'],
  'vps'     => db()->query('SELECT COUNT(*) c FROM vps')->fetch()['c'],
  'prompts' => db()->query('SELECT COUNT(*) c FROM prompts')->fetch()['c'],
  'chat'    => db()->query('SELECT COUNT(*) c FROM chat')->fetch()['c'],
  'tickets' => db()->query('SELECT COUNT(*) c FROM tickets')->fetch()['c'],
];

$users   = db()->query('SELECT * FROM users ORDER BY id DESC')->fetchAll();
$vpsAll  = db()->query('SELECT v.*,u.username FROM vps v JOIN users u ON u.id=v.user_id ORDER BY v.id DESC')->fetchAll();
$chatAll = db()->query('SELECT c.*,u.username,u.role FROM chat c JOIN users u ON u.id=c.user_id ORDER BY c.id DESC LIMIT 100')->fetchAll();
$chatAll = array_reverse($chatAll);
$ticketsAll = db()->query('SELECT t.*,u.username FROM tickets t JOIN users u ON u.id=t.user_id ORDER BY t.id DESC')->fetchAll();
$annAll = db()->query('SELECT * FROM announcements ORDER BY id DESC')->fetchAll();

$t = theme();
?>
<!DOCTYPE html>
<html lang="id" data-theme="<?= $t ?>">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Admin · RenClouds</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root{--bg:#f5f7fb;--card:#fff;--text:#0f172a;--muted:#64748b;--border:rgba(0,0,0,.05)}
[data-theme="dark"]{--bg:#0b1220;--card:#111a2e;--text:#e2e8f0;--muted:#94a3b8;--border:rgba(255,255,255,.06)}
*{margin:0;padding:0;box-sizing:border-box;font-family:'Inter',sans-serif}
body{background:var(--bg);color:var(--text);min-height:100vh;transition:background .3s,color .3s}
.topbar{background:var(--card);border-bottom:1px solid var(--border);padding:.9rem 2rem;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:10}
.logo{font-weight:800;font-size:1.2rem;background:linear-gradient(135deg,#f59e0b,#fbbf24);-webkit-background-clip:text;background-clip:text;color:transparent;display:flex;align-items:center;gap:.5rem}
.userbox{display:flex;align-items:center;gap:1rem;font-size:.9rem}
.avatar{width:36px;height:36px;border-radius:50%;background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700}
.btn{display:inline-flex;align-items:center;gap:.5rem;padding:.55rem 1.1rem;border-radius:10px;font-weight:600;font-size:.88rem;text-decoration:none;border:none;cursor:pointer;transition:.2s}
.btn-primary{background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#fff;box-shadow:0 6px 16px -6px rgba(245,158,11,.5)}
.btn-primary:hover{transform:translateY(-2px)}
.btn-danger{background:#fef2f2;color:#dc2626;border:1px solid #fecaca}
.btn-danger:hover{background:#fee2e2}
.btn-sm{padding:.35rem .7rem;font-size:.78rem;border-radius:8px}
.theme-toggle{width:36px;height:36px;border-radius:10px;background:var(--bg);border:1px solid var(--border);color:var(--text);cursor:pointer;font-size:.95rem;transition:.2s}
.theme-toggle:hover{transform:scale(1.1);background:#f59e0b;color:#fff}
.layout{display:flex;min-height:calc(100vh - 62px)}
.sidebar{width:240px;background:var(--card);border-right:1px solid var(--border);padding:1.2rem .8rem}
.sidebar a{display:flex;align-items:center;gap:.8rem;padding:.8rem 1rem;border-radius:12px;color:var(--muted);text-decoration:none;font-weight:500;font-size:.9rem;margin-bottom:.3rem;transition:.2s}
.sidebar a:hover,.sidebar a.active{background:linear-gradient(135deg,rgba(245,158,11,.1),rgba(251,191,36,.1));color:#b45309}
.sidebar a i{width:20px;text-align:center}
.content{flex:1;padding:2rem;max-width:1200px;margin:0 auto}
.card{background:var(--card);border-radius:20px;padding:1.6rem;border:1px solid var(--border);box-shadow:0 4px 20px rgba(0,0,0,.03);margin-bottom:1.2rem;animation:fadeUp .5s ease}
@keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
.card h3{font-size:1.05rem;margin-bottom:1rem;display:flex;align-items:center;gap:.5rem}
.card h3 i{color:#f59e0b}
.hero{background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#fff;border-radius:20px;padding:2rem;margin-bottom:1.5rem;display:flex;align-items:center;gap:1rem;animation:fadeUp .5s ease}
.hero h2{font-size:1.5rem;margin-bottom:.4rem}
.hero p{opacity:.92;font-size:.92rem}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:1rem;margin-bottom:1.5rem}
.stat{background:var(--card);border-radius:16px;padding:1.2rem;border:1px solid var(--border);animation:fadeUp .5s ease}
.stat .num{font-size:1.8rem;font-weight:800;background:linear-gradient(135deg,#f59e0b,#fbbf24);-webkit-background-clip:text;background-clip:text;color:transparent}
.stat .lbl{font-size:.82rem;color:var(--muted);font-weight:500}
table{width:100%;border-collapse:collapse;font-size:.88rem}
th,td{padding:.7rem .5rem;text-align:left;border-bottom:1px solid var(--border)}
th{color:var(--muted);font-weight:600;font-size:.78rem;text-transform:uppercase}
.badge{display:inline-block;padding:.2rem .7rem;border-radius:100px;font-size:.75rem;font-weight:600}
.bg-active{background:#f0fdf4;color:#16a34a}
.bg-pending{background:#fffbeb;color:#d97706}
.bg-suspended{background:#fef2f2;color:#dc2626}
.bg-rejected{background:#fef2f2;color:#991b1b}
.bg-admin{background:linear-gradient(135deg,#fef3c7,#fde68a);color:#b45309}
.bg-open{background:#fffbeb;color:#d97706}
.bg-closed{background:#f0fdf4;color:#16a34a}
input,textarea,select{width:100%;padding:.7rem 1rem;border:1px solid var(--border);border-radius:10px;font-size:.9rem;font-family:inherit;margin-bottom:.6rem;background:var(--bg);color:var(--text)}
input:focus,textarea:focus,select:focus{outline:none;border-color:#f59e0b;box-shadow:0 0 0 3px rgba(245,158,11,.15)}
.chat-box{height:440px;overflow-y:auto;background:var(--bg);border-radius:14px;padding:1rem;border:1px solid var(--border);margin-bottom:1rem}
.chat-msg{display:flex;gap:.6rem;margin-bottom:.8rem;align-items:flex-start}
.chat-msg .av{width:34px;height:34px;border-radius:50%;background:linear-gradient(135deg,#6366f1,#a855f7);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:.8rem;flex-shrink:0}
.chat-msg.admin .av{background:linear-gradient(135deg,#fbbf24,#f59e0b)}
.chat-msg .body{background:var(--card);padding:.55rem .9rem;border-radius:12px;font-size:.88rem;box-shadow:0 1px 3px rgba(0,0,0,.04);max-width:75%}
.chat-msg.admin .body{background:linear-gradient(135deg,#fffbeb,#fef3c7);border:1px solid #fde68a;color:#78350f}
.chat-msg .name{font-weight:700;font-size:.82rem;margin-bottom:.15rem;display:flex;align-items:center;gap:.2rem}
.chat-msg.admin .name{color:#b45309}
.chat-msg .time{font-size:.7rem;color:var(--muted);margin-top:.2rem}
.chat-form{display:flex;gap:.5rem}
.chat-form input{flex:1;margin:0}
.chat-form button{padding:.7rem 1.2rem;border:none;border-radius:10px;background:linear-gradient(135deg,#f59e0b,#fbbf24);color:#fff;font-weight:600;cursor:pointer;transition:.2s}
.chat-form button:hover{transform:translateY(-2px)}
.empty{text-align:center;color:var(--muted);padding:2rem;font-size:.9rem}
@media(max-width:768px){
  .layout{flex-direction:column}
  .sidebar{width:100%;border-right:none;border-bottom:1px solid var(--border);display:flex;overflow-x:auto;padding:.6rem}
  .sidebar a{white-space:nowrap;margin-bottom:0;margin-right:.3rem}
  .sidebar hr{display:none}
  .content{padding:1rem}
}
</style>
</head>
<body>

<div class="topbar">
  <div class="logo"><i class="fas fa-crown"></i> RenClouds Admin</div>
  <div class="userbox">
    <button class="theme-toggle" onclick="toggleTheme()"><i class="fas fa-moon" id="themeIcon"></i></button>
    <div class="avatar"><i class="fas fa-crown"></i></div>
    <span><strong><?= e($u['username']) ?></strong> <?= admin_badge(18) ?></span>
    <form method="post" style="display:inline">
      <input type="hidden" name="act" value="logout">
      <button class="btn btn-danger"><i class="fas fa-right-from-bracket"></i> Logout</button>
    </form>
  </div>
</div>

<div class="layout">
  <aside class="sidebar">
    <a href="?page=home" class="<?= $page==='home'?'active':'' ?>"><i class="fas fa-house"></i> Dashboard</a>
    <a href="?page=users" class="<?= $page==='users'?'active':'' ?>"><i class="fas fa-users"></i> Users</a>
    <a href="?page=vps" class="<?= $page==='vps'?'active':'' ?>"><i class="fas fa-server"></i> VPS</a>
    <a href="?page=chat" class="<?= $page==='chat'?'active':'' ?>"><i class="fas fa-comments"></i> Chat</a>
    <a href="?page=tickets" class="<?= $page==='tickets'?'active':'' ?>"><i class="fas fa-ticket"></i> Tiket</a>
    <a href="?page=ann" class="<?= $page==='ann'?'active':'' ?>"><i class="fas fa-bullhorn"></i> Pengumuman</a>
    <hr style="border:none;border-top:1px solid var(--border);margin:.8rem 0">
    <a href="dashboard.php"><i class="fas fa-user"></i> Mode User</a>
    <a href="index.php"><i class="fas fa-arrow-left"></i> Keluar</a>
  </aside>

  <main class="content">
  <?php if($page==='home'): ?>
    <div class="hero">
      <i class="fas fa-crown" style="font-size:2.5rem;opacity:.8"></i>
      <div>
        <h2>Selamat datang, Admin <?= e($u['username']) ?>! 👑</h2>
        <p>Kendali penuh RenClouds. Kelola user, VPS, chat, tiket, dan pengumuman.</p>
      </div>
    </div>
    <div class="grid">
      <div class="stat"><div class="num"><?= $stats['users'] ?></div><div class="lbl">Users</div></div>
      <div class="stat"><div class="num"><?= $stats['vps'] ?></div><div class="lbl">VPS</div></div>
      <div class="stat"><div class="num"><?= $stats['prompts'] ?></div><div class="lbl">Prompt</div></div>
      <div class="stat"><div class="num"><?= $stats['chat'] ?></div><div class="lbl">Chat</div></div>
      <div class="stat"><div class="num"><?= $stats['tickets'] ?></div><div class="lbl">Tiket</div></div>
    </div>
    <div class="card">
      <h3><i class="fas fa-bolt"></i> Quick Action</h3>
      <a href="?page=chat" class="btn btn-primary"><i class="fas fa-comments"></i> Chat</a>
      <a href="?page=users" class="btn btn-primary"><i class="fas fa-users"></i> Users</a>
      <a href="?page=vps" class="btn btn-primary"><i class="fas fa-server"></i> VPS</a>
      <a href="?page=ann" class="btn btn-primary"><i class="fas fa-bullhorn"></i> Buat Pengumuman</a>
    </div>

  <?php elseif($page==='users'): ?>
    <div class="card">
      <h3><i class="fas fa-users"></i> Daftar Users</h3>
      <table>
        <thead><tr><th>ID</th><th>Username</th><th>Email</th><th>Role</th><th>Aksi</th></tr></thead>
        <tbody>
        <?php foreach($users as $usr): ?>
          <tr>
            <td><?= $usr['id'] ?></td>
            <td><strong><?= e($usr['username']) ?></strong><?= $usr['role']==='admin'?admin_badge(16):'' ?></td>
            <td><?= e($usr['email']) ?></td>
            <td><span class="badge <?= $usr['role']==='admin'?'bg-admin':'bg-active' ?>"><?= e($usr['role']) ?></span></td>
            <td>
              <?php if($usr['role']!=='admin'): ?>
              <form method="post" style="display:inline" onsubmit="return confirm('Hapus?')">
                <input type="hidden" name="act" value="del_user">
                <input type="hidden" name="id" value="<?= $usr['id'] ?>">
                <button class="btn btn-danger btn-sm"><i class="fas fa-trash"></i></button>
              </form>
              <?php else: ?>-<?php endif; ?>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>

  <?php elseif($page==='vps'): ?>
    <div class="card">
      <h3><i class="fas fa-server"></i> Semua VPS Request</h3>
      <table>
        <thead><tr><th>ID</th><th>User</th><th>Hostname</th><th>Status</th><th>Ubah</th></tr></thead>
        <tbody>
        <?php foreach($vpsAll as $v): ?>
          <tr>
            <td><?= $v['id'] ?></td>
            <td><?= e($v['username']) ?></td>
            <td><?= e($v['hostname']) ?></td>
            <td><span class="badge bg-<?= $v['status'] ?>"><?= $v['status'] ?></span></td>
            <td>
              <form method="post" style="display:flex;gap:.3rem">
                <input type="hidden" name="act" value="vps_status">
                <input type="hidden" name="id" value="<?= $v['id'] ?>">
                <select name="status" style="width:auto;padding:.3rem;font-size:.78rem;margin:0">
                  <option value="pending" <?= $v['status']==='pending'?'selected':'' ?>>pending</option>
                  <option value="active" <?= $v['status']==='active'?'selected':'' ?>>active</option>
                  <option value="suspended" <?= $v['status']==='suspended'?'selected':'' ?>>suspended</option>
                  <option value="rejected" <?= $v['status']==='rejected'?'selected':'' ?>>rejected</option>
                </select>
                <button class="btn btn-primary btn-sm"><i class="fas fa-check"></i></button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>

  <?php elseif($page==='chat'): ?>
    <div class="card">
      <h3><i class="fas fa-comments"></i> Public Chat Admin <span style="background:#fbbf24;color:#fff;font-size:.7rem;padding:.15rem .55rem;border-radius:100px;margin-left:.4rem">GOLD</span></h3>
      <div class="chat-box" id="adminChat">
        <?php if(!$chatAll): ?>
          <div class="empty">Belum ada pesan.</div>
        <?php else: foreach($chatAll as $c): $isAdmin = $c['role']==='admin'; ?>
          <div class="chat-msg <?= $isAdmin?'admin':'' ?>">
            <div class="av"><?= strtoupper(substr($c['username'],0,1)) ?></div>
            <div class="body">
              <div class="name"><?= e($c['username']) ?><?= $isAdmin ? admin_badge(16) : '' ?></div>
              <div><?= nl2br(e($c['message'])) ?></div>
              <div class="time"><?= date('d M H:i', strtotime($c['created_at'])) ?></div>
            </div>
            <form method="post" style="margin-left:auto" onsubmit="return confirm('Hapus pesan?')">
              <input type="hidden" name="act" value="del_chat">
              <input type="hidden" name="id" value="<?= $c['id'] ?>">
              <button class="btn btn-danger btn-sm" style="opacity:.5"><i class="fas fa-trash"></i></button>
            </form>
          </div>
        <?php endforeach; endif; ?>
      </div>
      <form method="post" class="chat-form">
        <input type="hidden" name="act" value="send_chat">
        <input name="message" placeholder="Balas sebagai Admin..." required autocomplete="off">
        <button><i class="fas fa-paper-plane"></i> Kirim</button>
      </form>
    </div>
    <script>
      const box = document.getElementById('adminChat');
      if (box) box.scrollTop = box.scrollHeight;
      setInterval(() => {
        fetch('api/chat_feed.php').then(r=>r.text()).then(html=>{
          if (box && html.trim()) { box.innerHTML = html; box.scrollTop = box.scrollHeight; }
        }).catch(()=>{});
      }, 3000);
    </script>

  <?php elseif($page==='tickets'): ?>
    <div class="card">
      <h3><i class="fas fa-ticket"></i> Semua Tiket Support</h3>
      <table>
        <thead><tr><th>ID</th><th>User</th><th>Subjek</th><th>Status</th><th>Aksi</th></tr></thead>
        <tbody>
        <?php foreach($ticketsAll as $tk): ?>
          <tr>
            <td><?= $tk['id'] ?></td>
            <td><?= e($tk['username']) ?></td>
            <td><?= e($tk['subject']) ?></td>
            <td><span class="badge bg-<?= $tk['status'] ?>"><?= $tk['status'] ?></span></td>
            <td>
              <form method="post" style="display:inline">
                <input type="hidden" name="act" value="ticket_status">
                <input type="hidden" name="id" value="<?= $tk['id'] ?>">
                <select name="status" style="width:auto;padding:.3rem;font-size:.78rem;margin:0" onchange="this.form.submit()">
                  <option value="open" <?= $tk['status']==='open'?'selected':'' ?>>open</option>
                  <option value="closed" <?= $tk['status']==='closed'?'selected':'' ?>>closed</option>
                </select>
              </form>
              <form method="post" style="display:inline" onsubmit="return confirm('Hapus?')">
                <input type="hidden" name="act" value="del_ticket">
                <input type="hidden" name="id" value="<?= $tk['id'] ?>">
                <button class="btn btn-danger btn-sm"><i class="fas fa-trash"></i></button>
              </form>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>

  <?php elseif($page==='ann'): ?>
    <div class="card">
      <h3><i class="fas fa-bullhorn"></i> Buat Pengumuman</h3>
      <form method="post">
        <input type="hidden" name="act" value="add_ann">
        <input name="title" placeholder="Judul pengumuman" required>
        <textarea name="content" rows="3" placeholder="Isi pengumuman..." required></textarea>
        <button class="btn btn-primary"><i class="fas fa-paper-plane"></i> Kirim</button>
      </form>
    </div>
    <div class="card">
      <h3><i class="fas fa-list"></i> Semua Pengumuman</h3>
      <?php if(!$annAll): ?>
        <div class="empty">Belum ada pengumuman.</div>
      <?php else: foreach($annAll as $a): ?>
        <div style="background:var(--bg);border:1px solid var(--border);border-radius:12px;padding:1rem;margin-bottom:.8rem">
          <strong style="color:#f59e0b"><?= e($a['title']) ?></strong>
          <p style="font-size:.85rem;color:var(--muted);margin-top:.3rem"><?= nl2br(e($a['content'])) ?></p>
          <form method="post" style="display:inline" onsubmit="return confirm('Hapus?')">
            <input type="hidden" name="act" value="del_ann">
            <input type="hidden" name="id" value="<?= $a['id'] ?>">
            <button class="btn btn-danger btn-sm" style="margin-top:.5rem"><i class="fas fa-trash"></i> Hapus</button>
          </form>
        </div>
      <?php endforeach; endif; ?>
    </div>

  <?php endif; ?>
  </main>
</div>

<script>
function toggleTheme(){
  const html = document.documentElement;
  const next = html.getAttribute('data-theme')==='dark'?'light':'dark';
  html.setAttribute('data-theme', next);
  fetch('api/set_theme.php?theme='+next).catch(()=>{});
  document.getElementById('themeIcon').className = next==='dark'?'fas fa-sun':'fas fa-moon';
}
<?php if($t==='dark'): ?>
document.getElementById('themeIcon').className = 'fas fa-sun';
<?php endif; ?>
</script>
</body>
</html>
PHP

# ---------- NGINX ----------
NGINX_CONF="/etc/nginx/sites-available/renclouds"
cat > "$NGINX_CONF" <<NGX
server {
  listen 80;
  server_name ${DOMAIN} www.${DOMAIN};
  root ${WEBROOT};
  index index.php;
  client_max_body_size 50M;

  location / { try_files \$uri \$uri/ /index.php?\$query_string; }
  location ~ \.php\$ {
    include snippets/fastcgi-php.conf;
    fastcgi_pass ${PHP_SOCK};
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }
  location ~ /\.ht { deny all; }
}
NGX

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/renclouds
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
echo -e "${GRN}[OK] Nginx aktif.${NC}"

# ---------- SSL ----------
echo -e "${CYN}[*] Minta SSL...${NC}"
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect || \
  echo -e "${YLW}[!] SSL gagal, lanjut tanpa SSL.${NC}"

# ---------- FIREWALL ----------
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
systemctl enable --now fail2ban
echo -e "${GRN}[OK] Firewall & Fail2Ban aktif.${NC}"

chown -R www-data:www-data "$WEBROOT"
chmod -R 755 "$WEBROOT"

cat > /root/renclouds-info.txt <<INFO
==========================================
 REN CLOUDS — INFORMASI (v6.1)
==========================================
URL         : https://${DOMAIN}
Admin URL   : https://${DOMAIN}/admin.php
Username    : admin
Password    : Ren12#
DB Pass     : ${DB_PASS}
==========================================
JANGAN SEBAR AKUN ADMIN!
INFO

echo -e "\n${GRN}==============================================="
echo -e "   INSTALASI SELESAI v6.1 (LOGIN FIXED)"
echo -e "===============================================${NC}"
echo -e "  Web      : ${CYN}https://${DOMAIN}${NC}"
echo -e "  Admin    : ${CYN}https://${DOMAIN}/admin.php${NC}"
echo -e "  Username : ${YLW}admin${NC}"
echo -e "  Password : ${YLW}Ren12#${NC}"
echo -e "  Info     : ${CYN}/root/renclouds-info.txt${NC}"
echo -e "\n${RED}JANGAN SEBAR AKUN ADMIN!${NC}\n"
