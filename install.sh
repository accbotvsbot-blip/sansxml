cat > /root/install.sh << 'PART1EOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

clear
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}     SANSXML VPN — FULL INSTALLER + AUTO CLEAN${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e ${GREEN}'Lanjut install? (y/n): '${NC})" OK
[ "$OK" != "y" ] && [ "$OK" != "Y" ] && exit 0
echo ""

echo -e "${CYAN}[CLEAN 1/4]${NC} Stop service VPN lama..."
for svc in ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot xray; do
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/${svc}.service"
done
systemctl daemon-reload
systemctl reset-failed 2>/dev/null
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[CLEAN 2/4]${NC} Kill proses & buka port..."
fuser -k 80/tcp 8080/tcp 443/tcp 8443/tcp 10001/tcp 10002/tcp 10003/tcp 2>/dev/null
pkill -f ws-ssh.py 2>/dev/null
pkill -f badvpn-udpgw 2>/dev/null
pkill -f vpnbot 2>/dev/null
sleep 2
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[CLEAN 3/4]${NC} Hapus file VPN lama..."
rm -f /usr/local/bin/ws-ssh.py
rm -f /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem
rm -f /usr/bin/badvpn-udpgw
rm -f /usr/local/bin/vps-menu
rm -f /etc/profile.d/sansxml-menu.sh
rm -f /root/bot.py /root/vpnbot.log /root/vpnbot_*.json
rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub
rm -f /etc/issue /etc/issue.net /etc/motd
rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf
rm -f /etc/sansxml-*
rm -rf /tmp/badvpn
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[CLEAN 4/4]${NC} Hapus user SSH lama..."
COUNT=0
for u in $(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd); do
    if [ "$u" != "ubuntu" ] && [ "$u" != "admin" ]; then
        pkill -9 -u "$u" 2>/dev/null
        userdel -r "$u" 2>/dev/null
        COUNT=$((COUNT+1))
    fi
done
sed -i '/vps-menu/d' /root/.bashrc 2>/dev/null
echo -e "${GREEN}  ✓ $COUNT user dihapus${NC}"

echo -e "${CYAN}[1/8]${NC} Install packages..."
apt-get update -y >/dev/null 2>&1
apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip \
    stunnel4 net-tools cron ufw iptables openssl \
    cmake build-essential git pkg-config bc jq >/dev/null 2>&1
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[2/8]${NC} Telegram API..."
pip3 install --break-system-packages --upgrade pip >/dev/null 2>&1
pip3 install --break-system-packages --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 \
  || pip3 install --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[3/8]${NC} SSH key..."
mkdir -p /root/.ssh; chmod 700 /root/.ssh
ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[4/8]${NC} WS-SSH..."
cat > /usr/local/bin/ws-ssh.py << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, sys, hashlib, base64, time
LISTEN_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 80
SSH_HOST = "127.0.0.1"; SSH_PORT = 22; BUFFER = 65536
GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
def log(m): print(f"[{time.strftime('%H:%M:%S')}] [{LISTEN_PORT}] {m}", flush=True)
def forward(src, dst, tag):
    try:
        while True:
            data = src.recv(BUFFER)
            if not data: break
            dst.sendall(data)
    except (ConnectionResetError, BrokenPipeError, OSError): pass
    except Exception as e: log(f"fwd [{tag}] {e}")
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except: pass
def handle(client, addr):
    log(f"<- {addr}")
    try:
        client.settimeout(3)
        first = b""
        try: first = client.recv(4096)
        except socket.timeout: pass
        if not first: log(f"<-> {addr} RAW")
        elif first.startswith(b"SSH-") or b"SSH-2.0" in first[:64]: log(f"<-> {addr} SSH raw")
        elif first.startswith((b"GET ", b"POST ", b"CONNECT ", b"HEAD ", b"PUT ", b"OPTIONS ")):
            header = first
            try:
                while b"\r\n\r\n" not in header and len(header) < 65536:
                    c = client.recv(4096)
                    if not c: break
                    header += c
            except socket.timeout: pass
            key = None
            for line in header.split(b"\r\n"):
                if line.lower().startswith(b"sec-websocket-key:"):
                    key = line.split(b":", 1)[1].strip(); break
            accept = (base64.b64encode(hashlib.sha1(key + GUID).digest()) if key else b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
            client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
            log(f"<-> {addr} WS OK")
        try: ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=10)
        except Exception as e: log(f"X sshd: {e}"); client.close(); return
        log(f"OK {addr} -> SSH")
        ssh.settimeout(None); client.settimeout(None)
        if first and not first.startswith((b"GET ", b"POST ", b"CONNECT ", b"HEAD ", b"PUT ", b"OPTIONS ")):
            try: ssh.sendall(first)
            except: pass
        t1 = threading.Thread(target=forward, args=(client, ssh, "C>S"), daemon=True)
        t2 = threading.Thread(target=forward, args=(ssh, client, "S>C"), daemon=True)
        t1.start(); t2.start(); t1.join(); t2.join()
        try: ssh.close()
        except: pass
    except Exception as e: log(f"handler: {e}")
    finally:
        try: client.close()
        except: pass
        log(f"X {addr}")
def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", LISTEN_PORT)); s.listen(500)
    log(f"WS-SSH listen :{LISTEN_PORT}")
    while True:
        try:
            c, a = s.accept()
            threading.Thread(target=handle, args=(c, a), daemon=True).start()
        except Exception as e: log(f"accept: {e}")
if __name__ == "__main__": main()
PYEOF
chmod +x /usr/local/bin/ws-ssh.py

cat > /etc/systemd/system/ws-ssh.service << 'SVCEOF'
[Unit]
Description=WS-SSH port 80
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh.py 80
Restart=always
RestartSec=3
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
SVCEOF

cat > /etc/systemd/system/ws-ssh-alt.service << 'SVCEOF'
[Unit]
Description=WS-SSH port 8080
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh.py 8080
Restart=always
RestartSec=3
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
SVCEOF
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[5/8]${NC} stunnel..."
mkdir -p /etc/stunnel
openssl req -new -x509 -days 3650 -nodes \
    -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem \
    -subj "/C=SG/CN=sansxml.local" 2>/dev/null

cat > /etc/stunnel/stunnel.conf << 'STEOF'
pid = /var/run/stunnel4.pid
debug = 4
output = /var/log/stunnel4.log
socket = l:TCP_NODELAY=1
socket = r:TCP_NODELAY=1

[ssl-ws-443]
accept  = 443
connect = 127.0.0.1:80
cert    = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
client = no

[ssl-ws-8443]
accept  = 8443
connect = 127.0.0.1:80
cert    = /etc/stunnel/stunnel.pem
TIMEOUTclose = 0
client = no
STEOF
sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[6/8]${NC} UDPGW (5-8 menit)..."
rm -rf /tmp/badvpn
git clone --depth=1 https://github.com/ambrop72/badvpn.git /tmp/badvpn 2>/dev/null
if [ -d /tmp/badvpn ]; then
    mkdir -p /tmp/badvpn/build && cd /tmp/badvpn/build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1
    [ -f udpgw/badvpn-udpgw ] && cp udpgw/badvpn-udpgw /usr/bin/
    cd /root && rm -rf /tmp/badvpn
fi
if [ -f /usr/bin/badvpn-udpgw ]; then
cat > /etc/systemd/system/udpgw.service << 'SVCEOF'
[Unit]
Description=BadVPN UDPGW
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 500 --max-connections-for-client 10
Restart=always
[Install]
WantedBy=multi-user.target
SVCEOF
echo -e "${GREEN}  ✓${NC}"
else
echo -e "${YELLOW}  ⚠ Skip${NC}"
fi

echo -e "${CYAN}[7/8]${NC} Firewall..."
ufw --force disable >/dev/null 2>&1
ufw --force reset >/dev/null 2>&1
ufw default allow incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
for pt in 22 80 443 8080 8443; do ufw allow $pt/tcp >/dev/null 2>&1; done
ufw allow 7300/udp >/dev/null 2>&1
ufw allow 1:65535/udp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1
echo -e "${GREEN}  ✓${NC}"

echo -e "${CYAN}[8/8]${NC} Start services..."
systemctl daemon-reload
systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1
systemctl restart ws-ssh ws-ssh-alt stunnel4
[ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
sleep 3
echo -e "${GREEN}  ✓${NC}"

PART1EOF

echo "✅ Part 1 tersimpan"