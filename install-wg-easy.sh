#!/usr/bin/env bash
# wg-easy v15 Installer (Docker + Compose) – interaktiv
# Geeignet für Debian/Ubuntu (VM oder Proxmox-LXC)
# Autor: ChatGPT (für Michael)
set -euo pipefail

########################
# Helpers & Preconditions
########################
need_root() { [[ $EUID -eq 0 ]] || { echo "[x] Bitte als root ausführen."; exit 1; }; }
need_root

say()  { echo -e "\033[36m[i]\033[0m $*"; }
ok()   { echo -e "\033[32m[✓]\033[0m $*"; }
warn() { echo -e "\033[33m[!]\033[0m $*"; }
err()  { echo -e "\033[31m[x]\033[0m $*"; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Befehl fehlt: $1"; exit 1; }; }

is_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 1<=10#$1 && 10#$1<=65535 )); }

default_iface() {
  ip -4 route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1
}

public_ipv4_guess() {
  (curl -4 -m 3 -fsS https://ifconfig.me || curl -4 -m 3 -fsS https://api.ipify.org || true) | tr -d '\n\r'
}

########################
# Defaults
########################
APP_DIR="/etc/docker/containers/wg-easy"
IMG="ghcr.io/wg-easy/wg-easy:15"     # stabile Major-Tag
WEB_PORT_DEFAULT="51821"
WG_PORT_DEFAULT="51820"
DNS_DEFAULT="1.1.1.1,9.9.9.9"
HOST_IF_DEFAULT="$(default_iface || echo eth0)"
PUB_IP_DEFAULT="$(public_ipv4_guess || true)"

########################
# Abfragen
########################
echo
say "Basis-Parameter abfragen …"
read -r -p "Public Host/IP (für Clients sichtbar) [${PUB_IP_DEFAULT:-<deine-IP>}] : " WG_HOST
WG_HOST="${WG_HOST:-${PUB_IP_DEFAULT:-}}"
[[ -z "$WG_HOST" ]] && { err "Host/IP darf nicht leer sein."; exit 1; }

read -r -p "WireGuard UDP-Port [${WG_PORT_DEFAULT}]: " WG_PORT
WG_PORT="${WG_PORT:-$WG_PORT_DEFAULT}"
is_port "$WG_PORT" || { err "Ungültiger Port: $WG_PORT"; exit 1; }

read -r -p "Web-UI TCP-Port (LAN) [${WEB_PORT_DEFAULT}]: " WEB_PORT
WEB_PORT="${WEB_PORT:-$WEB_PORT_DEFAULT}"
is_port "$WEB_PORT" || { err "Ungültiger Port: $WEB_PORT"; exit 1; }

read -r -p "DNS-Server für Clients (kommagetrennt) [${DNS_DEFAULT}]: " DNS_SERVERS
DNS_SERVERS="${DNS_SERVERS:-$DNS_DEFAULT}"

read -r -p "Web-UI ohne Reverse Proxy erlauben (HTTP) – INSECURE=true? [y/N]: " INSEC
if [[ "${INSEC,,}" == "y" || "${INSEC,,}" == "yes" ]]; then
  INSECURE_VAL="true"
else
  INSECURE_VAL="false"
fi

# Admin-Creds (Unattended Setup v15)
read -r -p "Admin-Benutzername [admin]: " INIT_USER
INIT_USER="${INIT_USER:-admin}"
read -r -s -p "Admin-Passwort: " INIT_PASS; echo
read -r -s -p "Admin-Passwort (Wiederholen): " INIT_PASS2; echo
[[ "$INIT_PASS" == "$INIT_PASS2" ]] || { err "Passwörter stimmen nicht überein."; exit 1; }
[[ -z "$INIT_PASS" ]] && { err "Leeres Passwort ist nicht erlaubt."; exit 1; }

# Optional: Netze & IPv6
echo
say "Optional: eigenes VPN-Netz setzen (sonst nimmst du die Defaults im UI)."
read -r -p "IPv4-CIDR für das VPN (leer = Standard, z. B. 10.8.0.0/24): " INIT_IPV4_CIDR
read -r -p "IPv6 im VPN aktivieren? [y/N]: " IPV6_ON
if [[ "${IPV6_ON,,}" == "y" || "${IPV6_ON,,}" == "yes" ]]; then
  read -r -p "IPv6-CIDR für das VPN (z. B. fd00::/64): " INIT_IPV6_CIDR
  DISABLE_IPV6_VAL="false"
else
  INIT_IPV4_CIDR="${INIT_IPV4_CIDR}"
  INIT_IPV6_CIDR=""
  DISABLE_IPV6_VAL="true"
fi

echo
say "Zusammenfassung:"
echo "  Endpoint       : ${WG_HOST}:${WG_PORT} (UDP)"
echo "  Web-UI         : Port ${WEB_PORT} (INSECURE=${INSECURE_VAL})"
echo "  DNS            : ${DNS_SERVERS}"
echo "  Admin-Login    : ${INIT_USER} / (*** verborgen ***)"
if [[ -n "${INIT_IPV4_CIDR}" ]]; then echo "  VPN IPv4 CIDR  : ${INIT_IPV4_CIDR}"; fi
if [[ -n "${INIT_IPV6_CIDR}" ]]; then echo "  VPN IPv6 CIDR  : ${INIT_IPV6_CIDR}"; else echo "  IPv6           : deaktiviert (Container)"; fi
read -r -p "Passt das? [Y/n]: " okgo
[[ -z "${okgo}" || "${okgo,,}" == "y" || "${okgo,,}" == "yes" ]] || { err "Abgebrochen."; exit 1; }

########################
# Docker installieren
########################
say "Docker installieren (Engine + Compose Plugin) …"
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg lsb-release
  curl -fsSL https://get.docker.com | sh
fi

# Compose Plugin sicherstellen
apt-get update -y || true
apt-get install -y docker-compose-plugin || true
systemctl enable --now docker

# Compose Befehl ermitteln (Plugin bevorzugt)
if docker compose version >/dev/null 2>&1; then
  DCMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DCMD="docker-compose"
else
  err "Weder 'docker compose' noch 'docker-compose' verfügbar."
  exit 1
fi
ok "Docker ist bereit. Nutze: '$DCMD'"

########################
# Ordner & Compose schreiben
########################
say "Ordner anlegen …"
mkdir -p "${APP_DIR}/data"
ok "Ordner: ${APP_DIR}"

say "docker-compose.yml schreiben …"
{
  cat <<EOF
services:
  wg-easy:
    image: ${IMG}
    container_name: wg-easy
    environment:
      - INIT_ENABLED=true                  # Unattended Setup (nur beim 1. Start)
      - INIT_USERNAME=${INIT_USER}
      - INIT_PASSWORD=${INIT_PASS}
      - INIT_HOST=${WG_HOST}
      - INIT_PORT=${WG_PORT}
      - INIT_DNS=${DNS_SERVERS}
      - INSECURE=${INSECURE_VAL}
EOF

  # Grupperegel: nur setzen, wenn BEIDE angegeben wurden
  if [[ -n "${INIT_IPV4_CIDR}" && -n "${INIT_IPV6_CIDR}" ]]; then
    echo "      - INIT_IPV4_CIDR=${INIT_IPV4_CIDR}"
    echo "      - INIT_IPV6_CIDR=${INIT_IPV6_CIDR}"
  fi

  # IPv6 komplett im Container deaktivieren (optional)
  if [[ "${DISABLE_IPV6_VAL}" == "true" ]]; then
    echo "      - DISABLE_IPV6=true"
  fi

  cat <<EOF
    volumes:
      - ./data:/etc/wireguard
    ports:
      - "${WG_PORT}:${WG_PORT}/udp"    # WireGuard
      - "${WEB_PORT}:51821/tcp"       # Web-UI (im LAN nutzen; öffentlich nur via Reverse Proxy + TLS)
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.disable_ipv6=1
    restart: unless-stopped
EOF
} > "${APP_DIR}/docker-compose.yml"

########################
# Start
########################
say "Container starten …"
cd "${APP_DIR}"
$DCMD up -d
ok "wg-easy läuft."

########################
# Hinweise / Nächste Schritte
########################
echo
say "Fertig! Nächste Schritte:"
echo "  1) Web-UI im Browser öffnen:  http://<Server-IP>:${WEB_PORT}"
echo "  2) Mit Benutzer '${INIT_USER}' einloggen."
echo "  3) Clients anlegen (QR/Config direkt im UI)."

echo
say "Wichtig:"
echo "  - Wenn eine externe Firewall/OPNsense davor sitzt: UDP ${WG_PORT} auf diesen Host weiterleiten."
echo "  - Web-UI übers Internet nur hinter einem Reverse Proxy mit TLS (z. B. Caddy/Traefik) veröffentlichen."

echo
ok "Nützliche Befehle:"
echo "  $DCMD -f ${APP_DIR}/docker-compose.yml logs -f"
echo "  $DCMD -f ${APP_DIR}/docker-compose.yml pull && $DCMD -f ${APP_DIR}/docker-compose.yml up -d"

exit 0
