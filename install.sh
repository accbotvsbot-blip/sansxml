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


cat >> /root/install.sh << 'PART2EOF'

echo -e "${CYAN}Install Menu VPS...${NC}"
cat > /usr/local/bin/vps-menu << 'MENUEOF'
#!/bin/bash
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'
DOMAIN=$(cat /etc/sansxml-domain 2>/dev/null || echo "unknown")
BOT_TOKEN=$(cat /etc/sansxml-bottoken 2>/dev/null || echo "not-set")
ADMIN_ID=$(cat /etc/sansxml-adminid 2>/dev/null || echo "not-set")
cek(){ systemctl is-active --quiet "$1" 2>/dev/null && echo -e "${GREEN}●${NC}" || echo -e "${RED}○${NC}"; }
show(){
    clear
    UP=$(uptime -p 2>/dev/null | sed 's/up //')
    IP=$(curl -s -m 3 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    OS=$(lsb_release -d 2>/dev/null | cut -f2 || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    K=$(uname -r); CPU=$(nproc)
    RT=$(free -m | awk '/Mem:/ {print $2}')
    RU=$(free -m | awk '/Mem:/ {print $3}')
    RP=$(( RU * 100 / RT ))
    DP=$(df -h / | awk 'NR==2 {print $5}')
    AK=$(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd | wc -l)
    TS="${BOT_TOKEN:0:20}..."
    echo ""
    echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}   SC AUTO INSTALLER VPS SSH${NC}"
    echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${WHITE}Domain${NC} : ${GREEN}$DOMAIN${NC}"
    echo -e "  ${WHITE}Admin ${NC} : ${GREEN}$ADMIN_ID${NC}"
    echo -e "  ${WHITE}Token ${NC} : ${CYAN}$TS${NC}"
    echo -e "  ${WHITE}OS    ${NC} : ${CYAN}$OS${NC}"
    echo -e "  ${WHITE}CPU   ${NC} : ${CYAN}${CPU} vCPU${NC}  ${WHITE}RAM${NC}: ${CYAN}${RU}/${RT} MB${NC} (${YELLOW}${RP}%${NC})"
    echo -e "  ${WHITE}Disk  ${NC} : ${CYAN}${DP}${NC}  ${WHITE}Uptime${NC}: ${CYAN}$UP${NC}"
    echo -e "  ${WHITE}IP    ${NC} : ${CYAN}$IP${NC}   ${WHITE}Akun${NC}: ${YELLOW}$AK${NC}"
    echo -e "  ${MAGENTA}─────────────────────────────────────────${NC}"
    echo -e "  ${WHITE}Services${NC}: $(cek ssh)SSH  $(cek ws-ssh)WS  $(cek stunnel4)SSL  $(cek udpgw)UDP  $(cek vpnbot)BOT"
    echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${GREEN}[01]${NC} Status Service    ${GREEN}[06]${NC} Hapus Semua"
    echo -e "   ${GREEN}[02]${NC} Test Koneksi      ${GREEN}[07]${NC} Cleanup Expired"
    echo -e "   ${GREEN}[03]${NC} Buat Akun SSH     ${GREEN}[08]${NC} Restart Bot"
    echo -e "   ${GREEN}[04]${NC} Hapus 1 Akun      ${GREEN}[09]${NC} Restart Semua"
    echo -e "   ${GREEN}[05]${NC} List Akun         ${GREEN}[10]${NC} Log Bot"
    echo -e "   ${GREEN}[11]${NC} Ubah Domain       ${GREEN}[12]${NC} Ubah Token"
    echo -e "   ${GREEN}[13]${NC} Ubah Admin ID     ${GREEN}[14]${NC} Clean SC"
    echo -e "   ${RED}[00]${NC} Exit"
    echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}
pause(){ echo ""; read -p "$(echo -e ${YELLOW}'  Enter...'${NC})"; }
while true; do
    show
    read -p "$(echo -e ${GREEN}'  Pilih [0-14]: '${NC})" P
    case $P in
        1) clear; for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot; do printf "  %-14s: %s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done; pause ;;
        2) clear; for p in 22 80 443 8080 8443; do printf "  Port %-6s: " $p; ss -tlnp | grep -q ":$p " && echo -e "${GREEN}OK${NC}" || echo -e "${RED}GAGAL${NC}"; done; pause ;;
        3) clear; read -p "  Username: " U; read -p "  Password: " PW; read -p "  Hari: " H
           [ -z "$U" ] || [ -z "$PW" ] || [ -z "$H" ] && { pause; continue; }
           EXP=$(date -d "+${H} days" +%Y-%m-%d)
           userdel -r "$U" 2>/dev/null; useradd -e "$EXP" -m -s /bin/bash "$U"
           echo "$U:$PW" | chpasswd; passwd -u "$U" 2>/dev/null
           echo -e "  ${GREEN}✅ Akun: $U / $PW / $EXP${NC}"; pause ;;
        4) clear; awk -F: '$3>=1000 && $3<65000 {print "  "$1}' /etc/passwd
           read -p "  Username: " U; [ -z "$U" ] && { pause; continue; }
           pkill -9 -u "$U" 2>/dev/null; userdel -r "$U" 2>/dev/null
           echo -e "  ${GREEN}✅ $U dihapus${NC}"; pause ;;
        5) clear; printf "  %-20s %-15s\n" "USERNAME" "EXPIRED"; echo "  ─────────────────────"
           for u in $(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd); do
               E=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
               printf "  %-20s %-15s\n" "$u" "$E"; done; pause ;;
        6) clear; read -p "  YAKIN? (yes/no): " C; [ "$C" != "yes" ] && { pause; continue; }
           for u in $(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd); do pkill -9 -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null; done
           echo -e "  ${GREEN}✅ Semua dihapus${NC}"; pause ;;
        7) clear; T=$(date +%s); C=0
           for u in $(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd); do
               E=$(chage -l "$u" 2>/dev/null | grep "Account expires" | cut -d: -f2 | xargs)
               [ "$E" = "never" ] && continue; ET=$(date -d "$E" +%s 2>/dev/null)
               [ -n "$ET" ] && [ "$ET" -lt "$T" ] && { pkill -9 -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null; C=$((C+1)); }
           done
           echo -e "  ${GREEN}✅ $C akun expired dihapus${NC}"; pause ;;
        8) systemctl restart vpnbot 2>/dev/null; echo -e "  ${GREEN}✅ Bot restart${NC}"; pause ;;
        9) systemctl restart ssh ws-ssh ws-ssh-alt stunnel4 2>/dev/null
           [ -f /usr/bin/badvpn-udpgw ] && systemctl restart udpgw
           systemctl restart vpnbot 2>/dev/null
           echo -e "  ${GREEN}✅ Semua restart${NC}"; pause ;;
        10) clear; tail -f /root/vpnbot.log ;;
        11) clear; read -p "  Domain baru: " NEW; [ -z "$NEW" ] && { pause; continue; }
            echo "$NEW" > /etc/sansxml-domain
            [ -f /root/vpnbot_config.json ] && python3 -c "import json;f='/root/vpnbot_config.json';c=json.load(open(f));c['domain']='$NEW';json.dump(c,open(f,'w'),indent=2)"
            systemctl restart vpnbot 2>/dev/null
            echo -e "  ${GREEN}✅ Domain: $NEW${NC}"; pause ;;
        12) clear; read -p "  Token baru: " NEW; [ -z "$NEW" ] && { pause; continue; }
            echo "$NEW" > /etc/sansxml-bottoken
            [ -f /root/vpnbot_config.json ] && python3 -c "import json;f='/root/vpnbot_config.json';c=json.load(open(f));c['bot_token']='$NEW';json.dump(c,open(f,'w'),indent=2)"
            systemctl restart vpnbot 2>/dev/null
            echo -e "  ${GREEN}✅ Token diubah${NC}"; pause ;;
        13) clear; read -p "  Admin ID baru (pisah koma): " NEW; [ -z "$NEW" ] && { pause; continue; }
            echo "$NEW" > /etc/sansxml-adminid
            [ -f /root/vpnbot_config.json ] && python3 -c "import json;f='/root/vpnbot_config.json';c=json.load(open(f));ids=[int(x.strip()) for x in '$NEW'.split(',') if x.strip().isdigit()];c['owner_ids']=ids;json.dump(c,open(f,'w'),indent=2)"
            systemctl restart vpnbot 2>/dev/null
            echo -e "  ${GREEN}✅ Admin diubah${NC}"; pause ;;
        14) clear; read -p "  YAKIN Clean SC? (yes/no): " C; [ "$C" != "yes" ] && { pause; continue; }
            for u in $(awk -F: '$3>=1000 && $3<65000 {print $1}' /etc/passwd); do pkill -9 -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null; done
            rm -f /root/vpnbot_*.json /root/vpnbot.log
            apt-get clean >/dev/null 2>&1
            rm -rf /tmp/* /var/tmp/* 2>/dev/null
            echo -e "  ${GREEN}✅ VPS dibersihkan${NC}"; pause ;;
        0) clear; exit 0 ;;
    esac
done
MENUEOF
chmod +x /usr/local/bin/vps-menu

cat > /etc/profile.d/sansxml-menu.sh << 'PROFEOF'
if [ -n "$SSH_CONNECTION" ] && [ "$USER" != "root" ]; then
    /usr/local/bin/vps-menu
fi
PROFEOF
chmod +x /etc/profile.d/sansxml-menu.sh
grep -q "vps-menu" /root/.bashrc 2>/dev/null || echo '[ -n "$SSH_CONNECTION" ] && /usr/local/bin/vps-menu' >> /root/.bashrc

clear
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         ✓ INSTALASI DASAR SELESAI${NC}"
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════════${NC}"
echo ""
read -p "$(echo -e ${YELLOW}'Domain (contoh: sgivip.naaofficial.web.id) : '${NC})" DOMAIN
read -p "$(echo -e ${YELLOW}'Bot Token Telegram                         : '${NC})" BOT_TOKEN
read -p "$(echo -e ${YELLOW}'Admin Telegram ID (contoh: 6144358600)     : '${NC})" ADMIN_ID

echo "$DOMAIN" > /etc/sansxml-domain
echo "$BOT_TOKEN" > /etc/sansxml-bottoken
echo "$ADMIN_ID" > /etc/sansxml-adminid

WA_LINK="wa.me/6289527419748"
TG_LINK="t.me/unokwn"

rm -f /etc/issue /etc/issue.net /etc/motd
rm -rf /etc/motd.d/* 2>/dev/null
chmod -x /etc/update-motd.d/* 2>/dev/null
rm -f /etc/update-motd.d/* 2>/dev/null

cat > /etc/issue.net << BANNER_EOF
<br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卐&nbsp;</b></font><font color="#ffff00"><b>SANSXML&nbsp;VPN&nbsp;STORE</b></font><font color="#ffffff"><b>&nbsp;卐&nbsp;---</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;──&nbsp;PREMIUM&nbsp;VPN&nbsp;SERVER&nbsp;──</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卍&nbsp;TERM&nbsp;OF&nbsp;SERVICE&nbsp;卐&nbsp;---</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;MULTI&nbsp;LOGIN&nbsp;!!</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;HACKING&nbsp;AND&nbsp;CARDING</b></font><br><font color="#ffff00"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;👉&nbsp;MULTI&nbsp;LOGIN&nbsp;BANNED&nbsp;👈</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ORDER&nbsp;CONFIG&nbsp;PREMIUM:&nbsp;</b></font><font color="#00ff44"><b>${WA_LINK}</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BOT&nbsp;ORDER&nbsp;VPN:&nbsp;</b></font><font color="#00ff44"><b>${TG_LINK}</b></font><br><br>
BANNER_EOF
cp /etc/issue.net /etc/motd

sed -i '/^[[:space:]]*ListenAddress/d' /etc/ssh/sshd_config
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-vpnbot.conf << 'SSHEOF'
Port 22
ListenAddress 0.0.0.0
ListenAddress ::
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
Banner /etc/issue.net
PrintMotd yes
SSHEOF
systemctl restart ssh 2>/dev/null || systemctl restart sshd

cat > /root/vpnbot_config.json << CFGEOF
{
  "bot_token": "${BOT_TOKEN}",
  "domain": "${DOMAIN}",
  "owner_ids": [${ADMIN_ID}],
  "harga_30_hari": 5000,
  "ip_limit": 2,
  "block_hours": 5
}
CFGEOF

echo ""
echo -e "${CYAN}Menulis bot.py inline...${NC}"

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

CONFIG_FILE = "/root/vpnbot_config.json"
def load_config():
    d = {"bot_token":"", "domain":"", "owner_ids":[], "harga_30_hari":5000, "ip_limit":2, "block_hours":5}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f: c = json.load(f)
            for k,v in d.items(): c.setdefault(k,v)
            return c
        except: pass
    return d
def save_config(c):
    with open(CONFIG_FILE,"w") as f: json.dump(c,f,indent=2)
CONFIG = load_config()
BOT_TOKEN = CONFIG["bot_token"]
ADMIN_IDS = CONFIG["owner_ids"]
SSH_HOST = CONFIG["domain"]
HARGA_30_HARI = CONFIG["harga_30_hari"]
IP_LIMIT = CONFIG["ip_limit"]
SSH_KEY_PATH = "/root/.ssh/id_bot"
HARI_MIN, HARI_MAX = 1, 30
TRIAL_DURATION_MIN = 30
TRIAL_PER_DAY = 2

def hitung_harga(h): return int(round(h * HARGA_30_HARI / 30))
USERS_FILE="/root/vpnbot_users.json"; BAL_FILE="/root/vpnbot_balance.json"
ACCOUNTS_FILE="/root/vpnbot_accounts.json"; TRIAL_FILE="/root/vpnbot_trial.json"
TRX_FILE="/root/vpnbot_trx.json"

logging.basicConfig(format="%(asctime)s - %(levelname)s - %(message)s", level=logging.INFO,
    handlers=[logging.StreamHandler(), logging.FileHandler("/root/vpnbot.log", encoding="utf-8")])
logger = logging.getLogger(__name__)

def is_owner(uid): return uid in ADMIN_IDS
def rupiah(n): return f"Rp {int(n):,}".replace(",", ".")
def load_json(p, d):
    if not os.path.exists(p): return d
    try:
        with open(p) as f: return json.load(f)
    except: return d
def save_json(p, d):
    with open(p,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False)
def track_user(u):
    d = load_json(USERS_FILE,{})
    d[str(u.id)] = {"first_name": u.first_name or "", "username": u.username or "", "last_seen": datetime.now().isoformat()}
    save_json(USERS_FILE,d)
def get_bal(uid): return load_json(BAL_FILE,{}).get(str(uid),0)
def add_bal(uid, amt):
    d = load_json(BAL_FILE,{}); d[str(uid)] = d.get(str(uid),0)+int(amt); save_json(BAL_FILE,d); return d[str(uid)]
def reduce_bal(uid, amt):
    d = load_json(BAL_FILE,{}); cur = d.get(str(uid),0)
    if cur < amt: return False, cur
    d[str(uid)] = cur - amt; save_json(BAL_FILE,d); return True, d[str(uid)]
def add_trx(uid, name, uname, tipe, jumlah, ket=""):
    d = load_json(TRX_FILE,[])
    d.append({"user_id":uid,"name":name,"username":uname,"tipe":tipe,"jumlah":int(jumlah),"ket":ket,"waktu":datetime.now().isoformat()})
    save_json(TRX_FILE,d)
def get_stats(uid=None):
    d = load_json(TRX_FILE,[])
    if uid: d = [t for t in d if t["user_id"]==uid]
    today = datetime.now().strftime("%Y-%m-%d")
    week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d")
    month = datetime.now().strftime("%Y-%m")
    return {"hari":sum(1 for t in d if t["waktu"].startswith(today) and t["tipe"]=="buat_akun"),
            "minggu":sum(1 for t in d if t["waktu"][:10]>=week and t["tipe"]=="buat_akun"),
            "bulan":sum(1 for t in d if t["waktu"].startswith(month) and t["tipe"]=="buat_akun"),
            "total":sum(1 for t in d if t["tipe"]=="buat_akun")}
def get_acc(u): return load_json(ACCOUNTS_FILE,{}).get(u)
def get_user_accs(uid): return [a for a in load_json(ACCOUNTS_FILE,{}).values() if a.get("user_id")==uid]
def save_acc(u, d):
    dd = load_json(ACCOUNTS_FILE,{}); dd[u]=d; save_json(ACCOUNTS_FILE,dd)
def is_username_taken(u): return u.lower() in [k.lower() for k in load_json(ACCOUNTS_FILE,{}).keys()]
def count_accounts(): return len(load_json(ACCOUNTS_FILE,{}))
def delete_acc_json(un):
    dd = load_json(ACCOUNTS_FILE,{})
    if un in dd:
        data = dd.pop(un); save_json(ACCOUNTS_FILE,dd); return data
    return None
def trial_left(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: return TRIAL_PER_DAY
    return max(0, TRIAL_PER_DAY - u.get("used",0))
def use_trial(uid):
    d = load_json(TRIAL_FILE,{}); today = datetime.now().strftime("%Y-%m-%d")
    u = d.get(str(uid),{})
    if u.get("date") != today: u = {"date":today,"used":0}
    u["used"] = u.get("used",0)+1
    d[str(uid)] = u; save_json(TRIAL_FILE,d)
def hitung_refund(a):
    try:
        exp = datetime.strptime(a["exp"],"%Y-%m-%d").date()
        sisa = (exp - datetime.now().date()).days
        if sisa <= 0: return 0
        th = int(a.get("days",30)); hg = int(a.get("harga",0))
        if th <= 0 or hg <= 0: return 0
        if sisa >= th: return hg
        return max(0, int(round(hg * sisa / th)))
    except: return 0

def ssh_run(cmd, timeout=30):
    full = ["ssh","-i",SSH_KEY_PATH,
            "-o","StrictHostKeyChecking=no","-o","UserKnownHostsFile=/dev/null",
            "-o","ConnectTimeout=10","-o","PubkeyAuthentication=yes",
            "-o","PasswordAuthentication=no","-o","LogLevel=ERROR",
            "-p","22","root@127.0.0.1",cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired: return -1,"","Timeout"
    except Exception as e: return -2,"",str(e)

def ssh_create(username, password, days):
    exp = (datetime.now()+timedelta(days=days)).strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(password.encode()).decode()
    cmd = (f"userdel -r {username} 2>/dev/null; "
           f"useradd -e {exp} -m -s /bin/bash {username} 2>&1 ; "
           f"PW=\$(echo '{pw_b64}' | base64 -d) ; "
           f"echo \"{username}:\$PW\" | chpasswd 2>&1 ; "
           f"passwd -u {username} 2>&1 ; usermod -U {username} 2>&1 ; "
           f"echo DONE:\$?")
    code, out, err = ssh_run(cmd)
    ok = "DONE:0" in out
    return {"ok":True,"username":username,"password":password,"exp":exp,"manual":not ok}
def ssh_delete(username):
    ssh_run(f"pkill -9 -u {username} 2>/dev/null; userdel -r {username} 2>&1; userdel {username} 2>&1; echo OK", timeout=20)
    return True, "OK"
def ssh_test():
    code, out, err = ssh_run("echo PING_OK", timeout=15)
    if "PING_OK" not in out: return False, f"SSH gagal: {err or out}"
    return True, "SSH OK"

def gen_pass(n=8): return ''.join(random.choices(string.ascii_lowercase+string.digits, k=n))
def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{3,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<4 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def dashboard_text(user, uid):
    uname = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid)
    return (f"╭──────〔 <b>SANSXML VPN STORE</b> 〕──────╮\n"
        f"<blockquote>"
        f"👤 <b>Profil</b>\n"
        f"├ User Telegram  : {uname}\n"
        f"├ Chat ID        : <code>{uid}</code>\n"
        f"├ Keanggotaan    : {role}\n"
        f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>\n"
        f"\n"
        f"🌍 <b>Info Global</b>\n"
        f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>\n"
        f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>\n"
        f"╰ Keseluruhan    : <b>{st['total']} Akun</b>\n"
        f"\n"
        f"🌐 <b>Informasi</b>\n"
        f"├ Server 1       : <b>SG NEWMEDIA</b>\n"
        f"├ Server 2       : <b>SG LEASWEB</b>\n"
        f"╰ Kuota Trial    : <b>{trial_left(uid)}x Hari</b>\n"
        f"</blockquote>\n"
        f"╰──────────────────────────╯")

def server_list_text():
    return ("╭──────────〔 <b>SERVER VPN</b> 〕──────────╮\n"
        "<blockquote>◆ 🇸🇬 <b>SG 1 • NEWMEDIA</b>\n"
        "├ Harga Harian   : <b>Rp 167</b>\n"
        "├ Harga Bulanan  : <b>Rp 5.010</b>\n"
        "├ Kuota          : Unlimited\n"
        "├ Limit IP       : 2 IP\n"
        "╰ Slot Tersedia  : <b>0/100 ✅</b></blockquote>\n"
        "<blockquote>◆ 🇸🇬 <b>SG 2 • LEASEWEB</b>\n"
        "├ Harga Harian   : <b>Rp 167</b>\n"
        "├ Harga Bulanan  : <b>Rp 5.010</b>\n"
        "├ Kuota          : Unlimited\n"
        "├ Limit IP       : 2 IP\n"
        "╰ Slot Tersedia  : <b>0/100 ✅</b></blockquote>\n"
        "╰────────────────────────────────────╯")

def kb_server_list():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🇸🇬 SG NEWMEDIA", callback_data="buat|newmedia"),
         InlineKeyboardButton("🇸🇬 SG LEASWEB", callback_data="buat|leaseweb")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def kb_dashboard(uid):
    rows = [
        [InlineKeyboardButton("➕ BUAT AKUN", callback_data="server|list"),
         InlineKeyboardButton("⌛ TRIAL AKUN", callback_data="trial")],
        [InlineKeyboardButton("👤 AKUN SAYA", callback_data="my_accs"),
         InlineKeyboardButton("♻️ REFRESH", callback_data="menu|main")]]
    if is_owner(uid):
        rows.append([InlineKeyboardButton("⚙️ Admin Panel", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def kb_admin():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📊 Statistik", callback_data="admin|stats"),
         InlineKeyboardButton("🔑 List Akun", callback_data="admin|list|0")],
        [InlineKeyboardButton("🩺 Test SSH", callback_data="admin|testssh"),
         InlineKeyboardButton("🧹 Cleanup", callback_data="admin|cleanup")],
        [InlineKeyboardButton("🔙 Menu", callback_data="menu|main")]])

def kb_acc_detail(un):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🗑️ Hapus", callback_data=f"del_acc|{un}")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="my_accs")]])

def kb_confirm_delete(un):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Ya", callback_data=f"del_acc_do|{un}"),
         InlineKeyboardButton("❌ Batal", callback_data=f"acc_detail|{un}")]])

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server="SG NEWMEDIA"):
    if manual: head = "MANUAL"
    elif is_trial: head = "TRIAL"
    else: head = "PREMIUM"
    BULAN_ID = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        exp_d = datetime.strptime(exp,"%Y-%m-%d")
        exp_fmt = f"{exp_d.day} {BULAN_ID[exp_d.month-1]}, {exp_d.year}"
        now = datetime.now()
        try: days_int = int(dl.split()[0])
        except: days_int = 30
        created = now - timedelta(days=days_int)
        created_fmt = f"{created.day} {BULAN_ID[created.month-1]}, {created.year}"
    except:
        exp_fmt = exp; created_fmt = "-"
    server_name = server.replace("🇸🇬 ","").strip()
    return (f"◤ <b>SSH OVPN ACCOUNT</b> ◢\n"
        f"     ❖ <b>{head}</b> ❖\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<code>"
        f"Server   : {server_name}\n"
        f"Username : {u}\n"
        f"Password : {p}\n"
        f"Quota    : Unlimited\n"
        f"</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<code>"
        f"Host     : {SSH_HOST}\n"
        f"OpenSSH  : 443, 80, 22\n"
        f"Dropbear : 443, 109\n"
        f"SSH WS   : 80, 8080, 8081-9999\n"
        f"SSH SSL  : 443\n"
        f"SSH UDP  : 1-65535\n"
        f"OVPN     : 443, 1194, 2200\n"
        f"BadVPN   : 7100, 7300\n"
        f"</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<code>"
        f"SSL      : {SSH_HOST}:443@{u}:{p}\n"
        f"WS       : {SSH_HOST}:80@{u}:{p}\n"
        f"UDP      : {SSH_HOST}:1-65535@{u}:{p}\n"
        f"</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<code>"
        f"Durasi   : {dl}\n"
        f"Dibuat   : {created_fmt}\n"
        f"Berakhir : {exp_fmt}\n"
        f"</code>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━\n"
        f"<i>❖ Terima kasih telah menggunakan layanan kami ❖</i>")

async def do_create_account(chat, uid, user, username, password, hari, is_trial=False, server="SG NEWMEDIA"):
    owner = is_owner(uid)
    price = 0 if (owner or is_trial) else hitung_harga(hari)
    if not owner and not is_trial and get_bal(uid) < price:
        await chat.send_message(f"❌ Saldo kurang: {rupiah(get_bal(uid))} < {rupiah(price)}", parse_mode="HTML"); return
    msg = await chat.send_message("⏳ Membuat akun...", parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create, username, password, hari)
    if not owner and not is_trial:
        ok, nb = reduce_bal(uid, price)
        if not ok: await msg.edit_text("❌ Saldo berubah."); return
    save_acc(username, {"user_id":uid,"username":username,"password":password,
        "exp":r["exp"],"days":hari,"limit_ip":IP_LIMIT,"harga":price,
        "created_at":datetime.now().isoformat(),"first_name":user.first_name or "",
        "username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":owner,"is_trial":is_trial,"server":server})
    if not is_trial:
        add_trx(uid, user.first_name or "User", user.username or "", "buat_akun", price, f"{hari}h {server}")
    dl_txt = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    await msg.edit_text(acc_caption(username, password, r["exp"], dl_txt, IP_LIMIT, r.get("manual",False), is_trial, server), parse_mode="HTML")
    for aid in ADMIN_IDS:
        try:
            await chat.bot.send_message(chat_id=aid,
                text=f"💰 <b>AKUN DIBUAT</b>\n\n👤 {user.first_name}\n📦 {server} • SSH {hari}h\n🔑 <code>{username}</code>\n🔒 <code>{password}</code>",
                parse_mode="HTML")
        except: pass

async def do_create_trial(chat, uid, user, server="SG NEWMEDIA"):
    if trial_left(uid) <= 0:
        await chat.send_message("❌ Trial habis. Coba besok!", parse_mode="HTML"); return
    use_trial(uid)
    await do_create_account(chat, uid, user, "trial-"+gen_pass(8), gen_pass(8), 1, is_trial=True, server=server)

async def _do_delete_account(uid, uname, user, chat):
    a = get_acc(uname)
    if not a or a.get("user_id") != uid: return
    refund = hitung_refund(a) if not a.get("free_owner") else 0
    try: await asyncio.to_thread(ssh_delete, uname)
    except: pass
    delete_acc_json(uname)
    if refund > 0:
        try:
            add_bal(uid, refund)
            add_trx(uid, user.first_name or "", user.username or "", "refund", refund, f"hapus {uname}")
        except: pass

async def start(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user); c.user_data.clear()
    await u.message.reply_text(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")

async def cb(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    q = u.callback_query; await q.answer()
    d = q.data; chat = u.effective_chat
    if d == "noop": return
    if d == "server|list":
        try: await q.edit_message_text(server_list_text(), reply_markup=kb_server_list(), parse_mode="HTML")
        except: pass
        return
    if d == "menu|main":
        c.user_data.clear()
        try: await q.edit_message_text(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")
        except: pass
        return
    if d == "trial":
        await do_create_trial(chat, uid, u.effective_user); return
    if d.startswith("buat|"):
        server_code = d.split("|")[1]
        server_label = {"newmedia":"🇸🇬 SG NEWMEDIA","leaseweb":"🇸🇬 SG LEASWEB"}.get(server_code,"🇸🇬 SG NEWMEDIA")
        c.user_data["buat_step"] = "username"
        c.user_data["buat_data"] = {"server":server_label}
        await chat.send_message("👤 <b>Masukkan username akun :</b>", parse_mode="HTML")
        return
    if d == "my_accs":
        accs = []
        for a in get_user_accs(uid):
            if a.get("is_trial",False): continue
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                if (ed - datetime.now().date()).days < 0: continue
            except: pass
            accs.append(a)
        if not accs:
            try: await q.edit_message_text("❌ Belum ada akun.", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("➕ Buat", callback_data="server|list")],[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]]), parse_mode="HTML")
            except: pass
            return
        accs.sort(key=lambda x: x.get("created_at",""), reverse=True)
        rows = []
        for a in accs[:20]:
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                exp_fmt = ed.strftime("%d/%m")
            except: exp_fmt = "?"
            server_tag = a.get("server","SG").replace("🇸🇬 ","").replace("SG ","")
            rows.append([InlineKeyboardButton(f"🖥 {a['username']} | {server_tag} | ⌛ {exp_fmt}", callback_data=f"acc_detail|{a['username']}")])
        rows.append([InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")])
        try: await q.edit_message_text(f"🌟 <b>AKUN SAYA</b> ({len(accs)}):", reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return
    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]
        a = get_acc(un)
        if not a or a.get("user_id") != uid:
            await q.answer("Tidak ada", show_alert=True); return
        dl_txt = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
        try: await q.edit_message_text(acc_caption(un, a['password'], a['exp'], dl_txt, a.get('limit_ip',IP_LIMIT), a.get('manual',False), a.get('is_trial',False), a.get('server','SG NEWMEDIA')), reply_markup=kb_acc_detail(un), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc|"):
        un = d.split("|",1)[1]
        a = get_acc(un)
        if not a or a.get("user_id") != uid:
            await q.answer("Tidak ada", show_alert=True); return
        ref = hitung_refund(a) if not a.get("free_owner") else 0
        try: await q.edit_message_text(f"⚠️ Hapus <code>{un}</code>?\n💰 Refund: <b>{rupiah(ref)}</b>", reply_markup=kb_confirm_delete(un), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc_do|"):
        un = d.split("|",1)[1]
        a = get_acc(un)
        if not a or a.get("user_id") != uid:
            await q.answer("Tidak ada", show_alert=True); return
        ref = hitung_refund(a) if not a.get("free_owner") else 0
        await _do_delete_account(uid, un, u.effective_user, chat)
        try: await q.delete_message()
        except: pass
        if ref > 0:
            try: await chat.send_message(f"✅ Hapus. Refund: <b>{rupiah(ref)}</b>", parse_mode="HTML")
            except: pass
        return
    if d == "admin|menu":
        if not is_owner(uid): return
        try: await q.edit_message_text(f"⚙️ <b>ADMIN PANEL</b>\n\n👥 User: <b>{len(load_json(USERS_FILE,{}))}</b>\n🔑 Akun: <b>{count_accounts()}</b>\n💰 Saldo: <b>{rupiah(sum(load_json(BAL_FILE,{}).values()))}</b>", reply_markup=kb_admin(), parse_mode="HTML")
        except: pass
        return
    if d == "admin|testssh":
        if not is_owner(uid): return
        try: await q.edit_message_text("🩺 Tes...", parse_mode="HTML")
        except: pass
        ok, msg = await asyncio.to_thread(ssh_test)
        try: await q.edit_message_text(msg, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|stats":
        if not is_owner(uid): return
        st = get_stats()
        try: await q.edit_message_text(f"📊 <b>STATISTIK</b>\n\nHari: <b>{st['hari']}</b>\nMinggu: <b>{st['minggu']}</b>\nBulan: <b>{st['bulan']}</b>\nTotal: <b>{st['total']}</b>", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|cleanup":
        if not is_owner(uid): return
        try: await q.edit_message_text("🧹 Cleaning...")
        except: pass
        today = datetime.now().date(); dele = 0
        for un, a in list(load_json(ACCOUNTS_FILE,{}).items()):
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                if (today - ed).days >= 1:
                    await asyncio.to_thread(ssh_delete, un)
                    delete_acc_json(un); dele += 1
            except: pass
        try: await q.edit_message_text(f"🧹 Dihapus: <b>{dele}</b>", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|list|"):
        if not is_owner(uid): return
        page = int(d.split("|")[2])
        accs = list(load_json(ACCOUNTS_FILE,{}).items())
        accs.sort(key=lambda x: x[1].get("created_at",""), reverse=True)
        PER = 10; total = len(accs)
        tp = max(1,(total+PER-1)//PER); page = max(0,min(page,tp-1))
        start = page*PER; today = datetime.now().date(); rows = []
        for un, a in accs[start:start+PER]:
            try:
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                st = "❌" if (ed-today).days < 0 else f"✅{(ed-today).days}h"
            except: st = "❔"
            rows.append([InlineKeyboardButton(f"{un} | {st}", callback_data=f"adm_acc|{un}")])
        nav = []
        if page > 0: nav.append(InlineKeyboardButton("◀️", callback_data=f"admin|list|{page-1}"))
        nav.append(InlineKeyboardButton(f"{page+1}/{tp}", callback_data="noop"))
        if page < tp-1: nav.append(InlineKeyboardButton("▶️", callback_data=f"admin|list|{page+1}"))
        if nav: rows.append(nav)
        rows.append([InlineKeyboardButton("🔙", callback_data="admin|menu")])
        try: await q.edit_message_text(f"🔑 <b>DAFTAR AKUN</b> ({total})", reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return
    if d.startswith("adm_acc|"):
        if not is_owner(uid): return
        un = d.split("|",1)[1]
        a = get_acc(un)
        if not a:
            await q.answer("Tidak ada", show_alert=True); return
        try: await q.edit_message_text(f"🔑 <b>AKUN</b>\n\n<code>{un}</code>\n🔒 <code>{a['password']}</code>\n📅 Exp: {a['exp']}", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🗑️ Hapus", callback_data=f"adm_del|{un}")],[InlineKeyboardButton("🔙", callback_data="admin|list|0")]]), parse_mode="HTML")
        except: pass
        return
    if d.startswith("adm_del|"):
        if not is_owner(uid): return
        un = d.split("|",1)[1]
        await asyncio.to_thread(ssh_delete, un)
        delete_acc_json(un)
        try: await q.edit_message_text(f"🗑️ <code>{un}</code> dihapus", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙", callback_data="admin|list|0")]]), parse_mode="HTML")
        except: pass
        return

async def handle_photo(u, c):
    await u.message.reply_text("Gunakan /start", reply_markup=ReplyKeyboardRemove())

async def msg(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    t = (u.message.text or "").strip()
    step = c.user_data.get("buat_step")
    if step:
        data = c.user_data.get("buat_data",{})
        if step == "username":
            if not valid_username(t):
                await u.message.reply_text("❌ Username invalid (3-20)\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            if is_username_taken(t):
                await u.message.reply_text(f"❌ {t} sudah ada.\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            data["username"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if step == "password":
            if not valid_password(t):
                await u.message.reply_text("❌ Password min 4\n\n🔑 Masukkan password akun :", parse_mode="HTML"); return
            data["password"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
        if step == "durasi":
            try: hari = int(re.sub(r'[^0-9]','',t))
            except:
                await u.message.reply_text("❌ Angka 1-30", parse_mode="HTML"); return
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text(f"❌ {HARI_MIN}-{HARI_MAX}", parse_mode="HTML"); return
            un = data.get("username"); pw = data.get("password"); server = data.get("server","SG NEWMEDIA")
            owner = is_owner(uid); price = 0 if owner else hitung_harga(hari)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if not owner and get_bal(uid) < price:
                await u.message.reply_text(f"❌ Saldo kurang {rupiah(price)}", parse_mode="HTML"); return
            await do_create_account(u.effective_chat, uid, u.effective_user, un, pw, hari, server=server)
            return

async def post_init(app):
    try: await app.bot.set_my_commands([BotCommand("start","Start")])
    except: pass
    ok, msg = await asyncio.to_thread(ssh_test)
    logger.info(f"[STARTUP] {msg}")

def main():
    app = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CallbackQueryHandler(cb))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, msg))
    app.run_polling(allowed_updates=Update.ALL_TYPES)

if __name__ == "__main__":
    main()
BOTPYEOF

chmod +x /root/bot.py
python3 -m py_compile /root/bot.py && echo -e "${GREEN}  ✓ Bot OK${NC}" || echo -e "${RED}  ❌ Bot error${NC}"

cat > /etc/systemd/system/vpnbot.service << 'SVCEOF'
[Unit]
Description=SANSXML VPN Bot
After=network.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/bot.py
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable vpnbot >/dev/null 2>&1
systemctl restart vpnbot
sleep 4

clear
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                  ✓✓✓ INSTALASI SELESAI ✓✓✓${NC}"
echo -e "${MAGENTA}══════════════════════════════════════════════════════════════════${NC}"
echo ""
for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot; do
    ST=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    printf "  %-14s : " "$s"
    [ "$ST" = "active" ] && echo -e "${GREEN}$ST${NC}" || echo -e "${RED}$ST${NC}"
done
echo ""
echo -e "${CYAN}Domain${NC}  : ${GREEN}$DOMAIN${NC}"
echo -e "${CYAN}Menu${NC}    : ${GREEN}vps-menu${NC}"
echo -e "${CYAN}Bot log${NC} : ${GREEN}tail -f /root/vpnbot.log${NC}"
echo ""
read -p "$(echo -e ${YELLOW}'Buka menu? (y/n): '${NC})" OPEN
[ "$OPEN" = "y" ] || [ "$OPEN" = "Y" ] && /usr/local/bin/vps-menu
PART2EOF

echo "✅ Part 2 tersimpan — installer lengkap!"
echo ""
echo "Cek file: wc -l /root/install.sh"
echo "Jalankan: bash /root/install.sh"
