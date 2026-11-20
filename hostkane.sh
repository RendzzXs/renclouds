#!/bin/bash

# ============================================
# Script Ganti Hostname VPS (Interaktif)
# ============================================

# Cek root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Script harus dijalankan sebagai root!"
    echo "   Gunakan: sudo bash $0"
    exit 1
fi

# Ambil hostname lama
OLD_HOSTNAME=$(hostname)

# Kalau ada argumen, pakai itu
if [ -n "$1" ]; then
    NEW_HOSTNAME="$1"
else
    # Kalau tidak ada argumen, prompt interaktif
    read -rp "Masukkan hostname baru (sekarang: $OLD_HOSTNAME): " NEW_HOSTNAME

    # Kalau user langsung Enter (kosong), pakai default
    if [ -z "$NEW_HOSTNAME" ]; then
        NEW_HOSTNAME="$OLD_HOSTNAME"
        echo "ℹ️  Tidak ada perubahan. Hostname tetap: $NEW_HOSTNAME"
        exit 0
    fi
fi

# Validasi format hostname (RFC 1123)
if ! echo "$NEW_HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'; then
    echo "❌ Format hostname tidak valid!"
    echo "   Hanya huruf, angka, dan tanda minus (-)"
    echo "   Tidak boleh diawali/diakhiri tanda minus"
    echo "   Panjang maksimal 63 karakter"
    exit 1
fi

echo ""
echo "🔄 Mengganti hostname dari '$OLD_HOSTNAME' ke '$NEW_HOSTNAME'..."

# Backup /etc/hosts
cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

# Ganti hostname (systemd)
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
echo "   Hostname lama : $OLD_HOSTNAME"
echo "   Hostname baru : $(hostname)"
echo "   FQDN          : $(hostname -f 2>/dev/null || echo 'N/A')"
echo ""
echo "ℹ️  Logout & login ulang agar prompt SSH berubah."
