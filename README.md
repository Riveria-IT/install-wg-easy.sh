# wg-easy Installer (v15) – Docker + Compose

**Repo:** https://github.com/Riveria-IT/install-wg-easy.sh.git

Dieses Skript installiert **wg-easy v15** in Docker (inkl. Compose), richtet die Ordnerstruktur ein und führt dich interaktiv durch alle wichtigen Eingaben (Endpoint **Domain oder IP**, Ports, DNS, Admin-Login, optional IPv4/IPv6-CIDR). Danach startet es `wg-easy` sofort.

> Ideal für **Debian/Ubuntu** – z. B. in einem **Proxmox LXC** (empfohlen: **privilegiert**, alternativ unprivilegiert mit `features: keyctl=1,nesting=1`).  
> Wenn OPNsense/Firewall davor sitzt, denke an die Portweiterleitung **UDP 51820** und (nur im LAN) **TCP 51821**.

---

## 🔧 Was das Skript macht

- Installiert **Docker Engine** und das **Compose-Plugin**
- Legt `/etc/docker/containers/wg-easy` an und schreibt dort eine `docker-compose.yml`
- Fragt interaktiv ab:
  - **Public Host/IP** (Domain *oder* IP) für den WireGuard-Endpoint
  - **WireGuard-Port (UDP)**, **Web-UI-Port (TCP)**
  - **DNS-Server** für Clients
  - **INSECURE** (Web-UI ohne Reverse Proxy – nur im LAN nutzen)
  - **Admin-Benutzername & Passwort** (Unattended-Setup in v15)
  - **Optional**: **IPv4-/IPv6-CIDR** fürs interne VPN-Netz
- Startet den Container und zeigt dir die **Nächsten Schritte** an

---

## ⚡️ Schnellstart (Einzeiler)

> Lädt das Skript aus dem Branch `main` und führt es sofort aus.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Riveria-IT/install-wg-easy.sh/main/install-wg-easy.sh)
```

**Alternative mit `wget`:**
```bash
bash <(wget -qO- https://raw.githubusercontent.com/Riveria-IT/install-wg-easy.sh/main/install-wg-easy.sh)
```

**Erst ansehen, dann ausführen (empfohlen):**
```bash
curl -fsSL https://raw.githubusercontent.com/Riveria-IT/install-wg-easy.sh/main/install-wg-easy.sh | less
# und dann:
bash <(curl -fsSL https://raw.githubusercontent.com/Riveria-IT/install-wg-easy.sh/main/install-wg-easy.sh)
```

> **Hinweis:** Falls dein Default-Branch **nicht** `main` ist, ersetze `main` durch den korrekten Branch-Namen.

---

## 🧭 Alternative Installation (git clone)

```bash
git clone https://github.com/Riveria-IT/install-wg-easy.sh.git
cd install-wg-easy.sh
sudo chmod +x install-wg-easy.sh
sudo ./install-wg-easy.sh
```

---

## ✅ Voraussetzungen

- Root-Rechte (`sudo`)
- Debian/Ubuntu (VM oder Proxmox-LXC)
- Netzwerkzugang ins Internet (für Docker-Install)
- **Proxmox LXC**:
  - empfohlen: **privilegiert**
  - alternativ: unprivilegiert mit `features: keyctl=1,nesting=1`

---

## ❓ Welche Werte muss ich eingeben?

Beim Start fragt dich das Skript u. a.:

- **Public Host/IP**:  
  - **Domain** (z. B. `vpn.deinedomain.ch`) *oder* **öffentliche IP**  
  - Domain ist praktischer bei DynIP/HTTPS; IP reicht bei statischer WAN-IP.
- **WireGuard-Port (UDP)**: Standard **51820**, frei wählbar
- **Web-UI-Port (TCP)**: Standard **51821**, im LAN erreichbar
- **DNS-Server**: z. B. `1.1.1.1,9.9.9.9`
- **INSECURE (true/false)**: Web-UI ohne Reverse Proxy (nur im LAN sinnvoll)
- **Admin-Login**: Benutzername + Passwort für den ersten Login
- **Optional – IPv4-/IPv6-CIDR**: eigenes internes VPN-Netz; wenn gesetzt, **beide** Felder (v15-Regel)

Alles kannst du später im **wg-easy UI** anpassen und neue Client-Configs generieren.

---

## 🔐 Firewall / OPNsense

- **WAN → wg-easy-Host** weiterleiten:
  - **UDP 51820** (oder dein gewählter WG-Port)
- **Web-UI**:
  - **TCP 51821** nur im **LAN** nutzen  
  - Öffentlich **nur hinter Reverse Proxy + TLS** (z. B. Caddy/Traefik/NGINX)

---

## 🌐 Optional: Reverse Proxy (Caddy) – Beispiel

> Nur wenn du die Web-UI übers Internet bereitstellen willst.

**Caddyfile (Ausschnitt):**
```caddyfile
vpn.example.ch {
  encode gzip
  reverse_proxy 127.0.0.1:51821
}
```

**Start (Docker Compose separater Stack):**
```bash
docker run -d --name caddy -p 80:80 -p 443:443 \
  -v $PWD/Caddyfile:/etc/caddy/Caddyfile \
  -v caddy_data:/data -v caddy_config:/config \
  caddy:latest
```

---

## 🔄 Update & Wartung

```bash
# Logs
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml logs -f

# Update ziehen und neu starten
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml pull
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml up -d

# Neustart
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml restart
```

---

## 🗑️ Uninstall

```bash
# Container stoppen/entfernen
docker compose -f /etc/docker/containers/wg-easy/docker-compose.yml down

# (Optional) Daten löschen – ACHTUNG: löscht Keys/Configs!
sudo rm -rf /etc/docker/containers/wg-easy
```

---

## 🧪 Troubleshooting

- **Web-UI nicht erreichbar**
  - Läuft der Container? `docker ps`
  - Logs prüfen (siehe oben)
  - Blockieren Host-Firewall/Hypervisor/OPNsense den Port?
- **VPN verbindet nicht**
  - Stimmt der **Endpoint** (Domain/IP) im Client?
  - Ist **UDP-Port** korrekt **weitergeleitet**?
  - Systemzeit korrekt (NTP) auf beiden Seiten?
- **Langsamkeit**
  - IDS/IPS/Traffic-Shaper deaktivieren (zum Test)
  - Genug vCPU/RAM
  - MTU 1420 im Client testen
- **IPv6**
  - Wenn du IPv6-Endpoints nutzt, IPv6 im Container aktiv lassen oder sauber per Proxy terminieren.

---

## 🤔 FAQ

**Muss ich eine Domain angeben?**  
Nein. Domain **oder** IP – beides geht. Domain ist praktischer (DynDNS/HTTPS).

**Brauche ich einen Passwort-Hash?**  
Nicht bei **wg-easy v15**. Das Skript setzt **INIT_USERNAME / INIT_PASSWORD** fürs erste Setup.

**Kann ich später etwas ändern?**  
Ja. Endpoint, Ports, DNS, Netze etc. im UI oder in der `docker-compose.yml` – dann `up -d`.

---

## 📄 Lizenz / Credits

- Lizenz: siehe Repository (falls noch nicht gesetzt: z. B. MIT)  
- Danke an das **wg-easy**-Projekt (ghcr.io/wg-easy/wg-easy)

---

Viel Erfolg! Wenn du magst, füge ich noch eine kurze **OPNsense-Portforward-Anleitung** oder ein **systemd-Service-Wrapper** hinzu.
