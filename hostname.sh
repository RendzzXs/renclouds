#!/bin/bash

# ============================================
# Script Ganti Hostname VPS
# ============================================

# Cek apakah dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Script harus dijalankan sebagai root!"
    echo "   Gunakan: sudo bash $0"
    exit 1
fi

# Cek argumen
if [ -z "$1" ]; then
    echo "Usage: $0 <hostname-baru>"
    echo "Contoh: $0 myserver"
    echo ""
    echo "Hostname saat ini: $(hostname)"
    exit 1
fi

NEW_HOSTNAME="$1"

# Validasi format hostname (RFC 1123)
if ! echo "$NEW_HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; then
    echo "❌ Format hostname tidak valid!"
    echo "   Hanya boleh huruf, angka, dan tanda minus (-)"
    echo "   Tidak boleh diawali/diakhiri tanda minus"
    echo "   Panjang maksimal 63 karakter"
    exit 1
fi

echo "🔄 Mengganti hostname dari '$(hostname)' ke '$NEW_HOSTNAME'..."

# Backup file hosts
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S)

# Ganti hostname
hostnamectl set-hostname "$NEW_HOSTNAME" 2>/dev/null || {
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME"
}

# Update /etc/hosts
if grep -qE '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
else
    echo -e "127.0.1.1\t$NEW_HOSTNAME" >> /etc/hosts
fi

# Verifikasi
echo ""
echo "✅ Hostname berhasil diganti!"
echo "   Hostname baru : $(hostname)"
echo "   FQDN          : $(hostname -f 2>/dev/null || echo 'N/A')"
echo ""
echo "ℹ️  Logout & login ulang agar prompt berubah."
