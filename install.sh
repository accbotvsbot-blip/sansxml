cat > /root/install.sh << 'INSTALLEREOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

spin(){ local pid=$1 msg="$2"; local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 $pid 2>/dev/null; do for x in "${f[@]}"; do printf "\r  ${CYAN}${x}${NC}  ${WHITE}%s${NC}   " "$msg"; sleep 0.08; kill -0 $pid 2>/dev/null || break; done; done
    printf "\r  ${GREEN}✓${NC}  ${WHITE}%s${NC}        \n" "$msg"; }

clear
echo ""; echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${CYAN}   SC AUTO INSTALL VPN SSH${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo ""

echo -e "  ${YELLOW}▸ Cleanup service lama${NC}"
( for s in ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot xray; do systemctl stop "$s" 2>/dev/null; systemctl disable "$s" 2>/dev/null; rm -f "/etc/systemd/system/${s}.service"; done
  systemctl daemon-reload; systemctl reset-failed 2>/dev/null ) & spin $! "Stop service lama"

( fuser -k 80/tcp 8080/tcp 443/tcp 8443/tcp 2>/dev/null
  pkill -f ws-ssh.py 2>/dev/null; pkill -f badvpn-udpgw 2>/dev/null; pkill -f vpnbot 2>/dev/null; sleep 2 ) & spin $! "Kill port VPN"

( rm -f /usr/local/bin/ws-ssh.py /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem /usr/bin/badvpn-udpgw
  rm -f /etc/profile.d/sansxml-menu.sh /root/bot.py /root/vpnbot.log
  rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub /etc/issue /etc/issue.net /etc/motd
  rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf /etc/sansxml-* /root/.bash_profile
  rm -rf /tmp/badvpn ) & spin $! "Hapus file lama"

echo -e "  ${GREEN}✓${NC}  ${WHITE}Data user & riwayat DIBIARKAN${NC}"; echo ""
echo -e "  ${YELLOW}▸ Install dependencies${NC}"
( apt-get update -y >/dev/null 2>&1 ) & spin $! "Update repository"
( apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip stunnel4 net-tools cron ufw iptables openssl cmake build-essential git pkg-config bc jq who procps dnsutils >/dev/null 2>&1 ) & spin $! "Install packages"
( pip3 install --break-system-packages --upgrade pip >/dev/null 2>&1
  pip3 install --break-system-packages --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 \
    || pip3 install --upgrade "python-telegram-bot>=20" requests qrcode pillow >/dev/null 2>&1 ) & spin $! "Install Telegram API"
( mkdir -p /root/.ssh; chmod 700 /root/.ssh
  ssh-keygen -t ed25519 -f /root/.ssh/id_bot -N "" -q
  cat /root/.ssh/id_bot.pub >> /root/.ssh/authorized_keys
  sort -u /root/.ssh/authorized_keys -o /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys ) & spin $! "Generate SSH key"
echo ""
echo -e "  ${YELLOW}▸ Install VPN services${NC}"

( cat > /usr/local/bin/ws-ssh.py << 'PYEOF'
#!/usr/bin/env python3
import socket, threading, sys, hashlib, base64
LP = int(sys.argv[1]) if len(sys.argv) > 1 else 80
def fwd(src, dst):
    try:
        while True:
            d = src.recv(65536)
            if not d: break
            dst.sendall(d)
    except: pass
    finally:
        try: dst.shutdown(socket.SHUT_WR)
        except: pass
def handle(c, a):
    try:
        c.settimeout(3)
        first = b""
        try: first = c.recv(4096)
        except: pass
        if first and first.startswith((b"GET ",b"POST ",b"CONNECT ",b"HEAD ")):
            h = first
            try:
                while b"\r\n\r\n" not in h and len(h) < 65536:
                    x = c.recv(4096)
                    if not x: break
                    h += x
            except: pass
            k = None
            for l in h.split(b"\r\n"):
                if l.lower().startswith(b"sec-websocket-key:"):
                    k = l.split(b":",1)[1].strip(); break
            acc = base64.b64encode(hashlib.sha1(k + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest()) if k else b"s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
            c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + acc + b"\r\n\r\n")
        s = socket.create_connection(("127.0.0.1", 22), timeout=10)
        s.settimeout(None); c.settimeout(None)
        if first and not first.startswith((b"GET ",b"POST ",b"CONNECT ",b"HEAD ")):
            s.sendall(first)
        t1 = threading.Thread(target=fwd, args=(c, s), daemon=True)
        t2 = threading.Thread(target=fwd, args=(s, c), daemon=True)
        t1.start(); t2.start(); t1.join(); t2.join()
    except: pass
    finally:
        try: c.close()
        except: pass
def main():
    sv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sv.bind(("0.0.0.0", LP)); sv.listen(500)
    print(f"WS-SSH :{LP}", flush=True)
    while True:
        try:
            c, a = sv.accept()
            threading.Thread(target=handle, args=(c, a), daemon=True).start()
        except: pass
if __name__ == "__main__": main()
PYEOF
  chmod +x /usr/local/bin/ws-ssh.py
  cat > /etc/systemd/system/ws-ssh.service << 'EOF'
[Unit]
Description=WS-SSH 80
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh.py 80
Restart=always
RestartSec=3
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
EOF
  cat > /etc/systemd/system/ws-ssh-alt.service << 'EOF'
[Unit]
Description=WS-SSH 8080
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh.py 8080
Restart=always
RestartSec=3
LimitNOFILE=100000
[Install]
WantedBy=multi-user.target
EOF
) & spin $! "Install WS-SSH"

( mkdir -p /etc/stunnel
  openssl req -new -x509 -days 3650 -nodes -out /etc/stunnel/stunnel.pem -keyout /etc/stunnel/stunnel.pem -subj "/CN=sansxml.local" 2>/dev/null
  cat > /etc/stunnel/stunnel.conf << 'EOF'
pid = /var/run/stunnel4.pid
debug = 4
output = /var/log/stunnel4.log
[ssl-443]
accept = 443
connect = 127.0.0.1:80
cert = /etc/stunnel/stunnel.pem
[ssl-8443]
accept = 8443
connect = 127.0.0.1:80
cert = /etc/stunnel/stunnel.pem
EOF
  sed -i 's/^ENABLED=.*/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4 ) & spin $! "Install stunnel SSL"

( rm -rf /tmp/badvpn
  git clone --depth=1 https://github.com/ambrop72/badvpn.git /tmp/badvpn 2>/dev/null
  if [ -d /tmp/badvpn ]; then
    mkdir -p /tmp/badvpn/build && cd /tmp/badvpn/build
    cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1
    [ -f udpgw/badvpn-udpgw ] && cp udpgw/badvpn-udpgw /usr/bin/
    cd /root && rm -rf /tmp/badvpn
  fi
  [ -f /usr/bin/badvpn-udpgw ] && cat > /etc/systemd/system/udpgw.service << 'EOF'
[Unit]
Description=UDPGW
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 0.0.0.0:7300 --max-clients 500
Restart=always
[Install]
WantedBy=multi-user.target
EOF
) & spin $! "Compile BadVPN UDPGW"

( ufw --force disable >/dev/null 2>&1; ufw --force reset >/dev/null 2>&1
  ufw default allow incoming >/dev/null 2>&1; ufw default allow outgoing >/dev/null 2>&1
  for p in 22 80 443 8080 8443; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 7300/udp >/dev/null 2>&1; ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 3 ) & spin $! "Start VPN services"

echo ""; echo -e "  ${YELLOW}▸ Konfigurasi Bot${NC}"; echo ""
read -p "$(echo -e ${GREEN}'  Bot Token Telegram : '${NC})" BOT_TOKEN
if [ -z "$BOT_TOKEN" ]; then echo -e "  ${RED}❌ Token tidak boleh kosong${NC}"; exit 1; fi

DOMAIN="sgivip.naaofficial.web.id"
ADMIN_ID="6144358600"
echo "$BOT_TOKEN" > /etc/sansxml-bottoken
echo "$DOMAIN" > /etc/sansxml-domain
echo "$ADMIN_ID" > /etc/sansxml-adminid

echo ""
echo -e "  ${YELLOW}▸ Konfigurasi Auto Backup GitHub (Opsional)${NC}"
echo -e "  ${WHITE}Kosongkan untuk skip setup backup${NC}"
echo ""
read -p "  GitHub Username        : " GH_USER
read -p "  GitHub Repo (private)  : " GH_REPO
read -s -p "  GitHub Token (ghp_xxx) : " GH_TOKEN
echo ""
read -p "  Email GitHub           : " GH_EMAIL

BACKUP_ENABLED=0
if [ -n "$GH_USER" ] && [ -n "$GH_REPO" ] && [ -n "$GH_TOKEN" ]; then
    BACKUP_ENABLED=1
    mkdir -p /root/vpnbot_backup
    cd /root/vpnbot_backup
    if [ ! -d ".git" ]; then
        git init -q
        git config user.email "$GH_EMAIL"
        git config user.name "$GH_USER"
        git branch -M main 2>/dev/null
        git remote add origin "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" 2>/dev/null || \
        git remote set-url origin "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git"
    fi
    echo -e "  ${CYAN}▸ Cek backup di GitHub...${NC}"
    if git pull origin main -q 2>/dev/null || git pull origin master -q 2>/dev/null; then
        echo -e "  ${GREEN}✓ Backup ditemukan! Restore data...${NC}"
        for f in vpnbot_users.json vpnbot_balance.json vpnbot_accounts.json vpnbot_trial.json vpnbot_trx.json vpnbot_blocked.json; do
            if [ -f "/root/vpnbot_backup/$f" ]; then
                cp "/root/vpnbot_backup/$f" "/root/$f"
                echo -e "    ${GREEN}✓${NC} $f"
            fi
        done
    else
        echo -e "  ${YELLOW}! Backup kosong / repo baru, mulai fresh${NC}"
    fi
    cd /root
    cat > /etc/sansxml-backup.conf << BEOF
GH_USER="${GH_USER}"
GH_REPO="${GH_REPO}"
GH_TOKEN="${GH_TOKEN}"
GH_EMAIL="${GH_EMAIL}"
BEOF
    chmod 600 /etc/sansxml-backup.conf
    cat > /root/vpnbot_backup.sh << 'BEOF'
#!/bin/bash
source /etc/sansxml-backup.conf 2>/dev/null
cd /root/vpnbot_backup || exit 1
for f in vpnbot_users.json vpnbot_balance.json vpnbot_accounts.json vpnbot_trial.json vpnbot_trx.json vpnbot_blocked.json vpnbot_config.json; do
    [ -f "/root/$f" ] && cp "/root/$f" "./$f"
done
git add -A
if ! git diff --cached --quiet; then
    git -c user.email="$GH_EMAIL" -c user.name="$GH_USER" commit -m "Auto backup: $(date '+%Y-%m-%d %H:%M:%S')" -q
    git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:main -q 2>/dev/null || \
    git push "https://${GH_USER}:${GH_TOKEN}@github.com/${GH_USER}/${GH_REPO}.git" HEAD:master -q 2>/dev/null
fi
BEOF
    chmod +x /root/vpnbot_backup.sh
    ( crontab -l 2>/dev/null | grep -v vpnbot_backup.sh; echo "*/5 * * * * /root/vpnbot_backup.sh >/dev/null 2>&1" ) | crontab -
    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
    /root/vpnbot_backup.sh >/dev/null 2>&1
    echo -e "  ${GREEN}✓ Auto backup aktif (setiap 5 menit)${NC}"
else
    echo -e "  ${YELLOW}! Backup di-skip${NC}"
fi

cat > /root/vpnbot_config.json << CFGEOF
{
  "bot_token": "${BOT_TOKEN}",
  "domain": "${DOMAIN}",
  "owner_ids": [${ADMIN_ID}],
  "servers": {
    "sg_1ip": {"name": "🇸🇬 PRIME SG-01", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-01", "domain": "${DOMAIN}", "price_day": 117, "price_month": 3510, "ip_limit": 1, "slot_max": 50},
    "sg_2ip": {"name": "🇸🇬 PRIME SG-02", "city": "Singapore", "isp": "DigitalOcean LLC", "ssh_ovpn": "DIGITALOCEAN • PRIME SG-02", "domain": "${DOMAIN}", "price_day": 167, "price_month": 5010, "ip_limit": 2, "slot_max": 50}
  },
  "ip_limit": 2,
  "block_hours": 5
}
CFGEOF

rm -f /etc/issue /etc/issue.net /etc/motd
rm -rf /etc/motd.d/* 2>/dev/null
chmod -x /etc/update-motd.d/* 2>/dev/null
rm -f /etc/update-motd.d/* 2>/dev/null

cat > /etc/issue.net << 'BEOF'
<br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卐&nbsp;</b></font><font color="#ffff00"><b>SANSXML&nbsp;VPN&nbsp;STORE</b></font><font color="#ffffff"><b>&nbsp;卐&nbsp;---</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;──&nbsp;PREMIUM&nbsp;VPN&nbsp;SERVER&nbsp;──</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;---&nbsp;卍&nbsp;TERM&nbsp;OF&nbsp;SERVICE&nbsp;卐&nbsp;---</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;MULTI&nbsp;LOGIN&nbsp;!!</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;NO&nbsp;HACKING&nbsp;AND&nbsp;CARDING</b></font><br><font color="#ffff00"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;👉&nbsp;MULTI&nbsp;LOGIN&nbsp;BANNED&nbsp;👈</b></font><br><font color="#ff00aa"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;▬▬▬▬▬▬ஜ۩۞۩ஜ▬▬▬▬▬▬</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ORDER&nbsp;CONFIG&nbsp;PREMIUM:&nbsp;</b></font><font color="#00ff44"><b>wa.me/6289527419748</b></font><br><font color="#ffffff"><b>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;BOT&nbsp;ORDER&nbsp;VPN:&nbsp;</b></font><font color="#00ff44"><b>t.me/unokwn</b></font><br><br>
BEOF
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

echo ""; echo -e "  ${YELLOW}▸ Install Bot Telegram${NC}"

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string, socket
from datetime import datetime, timedelta
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, BotCommand, ReplyKeyboardRemove
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, MessageHandler, filters

CONFIG_FILE = "/root/vpnbot_config.json"
def load_config():
    d = {"bot_token":"", "domain":"", "owner_ids":[6144358600], "servers":{}, "ip_limit":2, "block_hours":5}
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE) as f: c = json.load(f)
            for k,v in d.items(): c.setdefault(k,v)
            return c
        except: pass
    return d
def save_config(c):
    with open(CONFIG_FILE,"w") as f: json.dump(c,f,indent=2,ensure_ascii=False)

CONFIG = load_config()
BOT_TOKEN = CONFIG["bot_token"]
ADMIN_IDS = [6144358600]
SSH_HOST = CONFIG["domain"]
SERVERS = CONFIG.get("servers", {})
IP_LIMIT = CONFIG["ip_limit"]
SSH_KEY_PATH = "/root/.ssh/id_bot"
HARI_MIN, HARI_MAX = 1, 365
TRIAL_DURATION_MIN = 30
TRIAL_PER_DAY = 2
MIN_TOPUP = 1000
BLOCK_FILE = "/root/vpnbot_blocked.json"
BLOCK_HOURS = 2

def get_price(hari, server_key=None):
    if server_key and server_key in SERVERS: srv = SERVERS[server_key]
    else: srv = list(SERVERS.values())[0] if SERVERS else {"price_day": 117}
    return int(srv.get("price_day", 117)) * int(hari)

def get_server_slot_number(server_key):
    keys = list(SERVERS.keys())
    if server_key in keys: return keys.index(server_key) + 1
    return 1

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
def get_income():
    d = load_json(TRX_FILE,[])
    today = datetime.now().strftime("%Y-%m-%d")
    week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d")
    month = datetime.now().strftime("%Y-%m")
    return {"hari":sum(t["jumlah"] for t in d if t["waktu"].startswith(today) and t["tipe"]=="buat_akun"),
            "minggu":sum(t["jumlah"] for t in d if t["waktu"][:10]>=week and t["tipe"]=="buat_akun"),
            "bulan":sum(t["jumlah"] for t in d if t["waktu"].startswith(month) and t["tipe"]=="buat_akun"),
            "total":sum(t["jumlah"] for t in d if t["tipe"]=="buat_akun")}
def get_acc(u): return load_json(ACCOUNTS_FILE,{}).get(u)
def get_user_accs(uid): return [a for a in load_json(ACCOUNTS_FILE,{}).values() if a.get("user_id")==uid]
def save_acc(u, d):
    dd = load_json(ACCOUNTS_FILE,{}); dd[u]=d; save_json(ACCOUNTS_FILE,dd)
def is_username_taken(u): return u.lower() in [k.lower() for k in load_json(ACCOUNTS_FILE,{}).keys()]
def count_accounts(): return len(load_json(ACCOUNTS_FILE,{}))
def count_slots(server_key):
    accs = load_json(ACCOUNTS_FILE, {})
    today = datetime.now().date()
    count = 0
    for a in accs.values():
        if a.get("server_key") != server_key: continue
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
            if (ed - today).days >= 0: count += 1
        except: pass
    return count
def get_slot_info(server_key):
    srv = SERVERS.get(server_key, {})
    mx = int(srv.get("slot_max", 50))
    used = count_slots(server_key)
    return used, mx
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
        if a.get("is_trial"): return 0
        hg = int(a.get("harga", 0)); th = int(a.get("days", 30))
        if hg <= 0 or th <= 0: return 0
        exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
        sisa = (exp - datetime.now().date()).days
        if sisa <= 0: return 0
        refund = int(round((hg/th) * sisa))
        return max(0, min(refund, hg))
    except: return 0

def ssh_run(cmd, timeout=30):
    full = ["ssh","-i",SSH_KEY_PATH,"-o","StrictHostKeyChecking=no","-o","UserKnownHostsFile=/dev/null",
            "-o","ConnectTimeout=10","-o","PubkeyAuthentication=yes","-o","PasswordAuthentication=no",
            "-o","LogLevel=ERROR","-p","22","root@127.0.0.1",cmd]
    try:
        r = subprocess.run(full, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired: return -1,"","Timeout"
    except Exception as e: return -2,"",str(e)

def ssh_create(username, password, days, is_trial=False):
    now = datetime.now()
    if is_trial:
        exp_date = now.date()
        exp_ts = (now + timedelta(minutes=TRIAL_DURATION_MIN)).strftime("%Y-%m-%d %H:%M:%S")
    else:
        exp_date = (now + timedelta(days=days)).date()
        exp_ts = exp_date.strftime("%Y-%m-%d") + " 23:59:59"
    exp = exp_date.strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(password.encode()).decode()
    cmd = (f"userdel -r {username} 2>/dev/null; "
           f"useradd -m -s /bin/bash {username} 2>&1 ; "
           f"chage -E '{exp}' {username} 2>&1 ; "
           f"chage -M 99999 {username} 2>&1 ; chage -I -1 {username} 2>&1 ; "
           f"PW=$(echo '{pw_b64}' | base64 -d) ; "
           f"printf '%s:%s\\n' '{username}' \"$PW\" | chpasswd 2>&1 ; "
           f"passwd -u {username} 2>&1 ; usermod -U {username} 2>&1 ; echo DONE:$?")
    code, out, err = ssh_run(cmd)
    return {"ok":True,"username":username,"password":password,"exp":exp,"exp_ts":exp_ts,"manual":("DONE:0" not in out)}
def ssh_extend(username, new_exp):
    code, out, err = ssh_run(f"chage -E '{new_exp}' {username} 2>&1 ; echo DONE:$?")
    return "DONE:0" in out
def ssh_delete(username):
    ssh_run(f"pkill -9 -u {username} 2>/dev/null; userdel -r {username} 2>&1; echo OK", timeout=20)
    return True, "OK"
def ssh_test():
    code, out, err = ssh_run("echo PING_OK", timeout=15)
    return ("PING_OK" in out, "SSH OK" if "PING_OK" in out else f"SSH gagal: {err or out}")

def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_vps_public_ip():
    try:
        r = subprocess.run("curl -s -m 5 ifconfig.me", shell=True, capture_output=True, text=True, timeout=8)
        ip = r.stdout.strip()
        if ip and ip.count(".") == 3: return ip
    except: pass
    try:
        r = subprocess.run("curl -s -m 5 icanhazip.com", shell=True, capture_output=True, text=True, timeout=8)
        ip = r.stdout.strip()
        if ip and ip.count(".") == 3: return ip
    except: pass
    return None

def is_valid_domain(val):
    val = val.strip()
    if len(val) < 3 or len(val) > 253:
        return False, "Panjang minimal 3 karakter, maksimal 253", None
    try:
        parts = val.split(".")
        if len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts):
            return True, "IP Address", None
    except: pass
    if not re.match(r'^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$', val.split('.')[0]):
        return False, "Format domain tidak valid", None
    parts = val.split(".")
    if len(parts) < 2:
        return False, "Domain harus punya titik", None
    for p in parts:
        if len(p) < 1 or len(p) > 63:
            return False, "Setiap bagian domain maksimal 63 karakter", None
        if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$', p):
            return False, "Format domain tidak valid", None
    if not re.match(r'^[a-zA-Z]{2,}$', parts[-1]):
        return False, "TLD tidak valid", None
    try:
        domain_ip = socket.gethostbyname(val)
    except socket.gaierror:
        return False, "Domain tidak ditemukan di DNS", None
    except Exception as e:
        return False, f"Gagal resolve: {e}", None
    vps_ip = get_vps_public_ip()
    if vps_ip and domain_ip == vps_ip:
        return True, f"Domain → {domain_ip} ✅ (IP VPS ini)", domain_ip
    elif vps_ip:
        return True, f"Domain → {domain_ip} ⚠️ (beda dari IP VPS: {vps_ip})", domain_ip
    else:
        return True, f"Domain → {domain_ip}", domain_ip

def count_ssh_sessions(username):
    try:
        r = subprocess.run(f"ps -u {username} -o pid= 2>/dev/null | wc -l", shell=True, capture_output=True, text=True, timeout=5)
        return int(r.stdout.strip() or 0)
    except: return 0
def get_active_ips(username):
    try:
        r = subprocess.run("who", shell=True, capture_output=True, text=True, timeout=5)
        ips = set()
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[0] == username:
                ip_part = parts[-1].strip("()")
                if ip_part and ip_part != ":0": ips.add(ip_part)
        return list(ips)
    except: return []
def check_limit(username, limit_ip):
    sessions = count_ssh_sessions(username)
    ips = get_active_ips(username)
    over = (sessions > limit_ip) or (len(ips) > limit_ip)
    return over, sessions, ips
def block_user(username, hours=2):
    try:
        subprocess.run(f"passwd -l {username}", shell=True, timeout=10)
        subprocess.run(f"pkill -9 -u {username}", shell=True, timeout=10)
        d = load_json(BLOCK_FILE, {})
        d[username] = {"blocked_at": datetime.now().isoformat(),
                       "unblock_at": (datetime.now() + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")}
        save_json(BLOCK_FILE, d); return True
    except: return False
def unblock_user(username):
    try:
        subprocess.run(f"passwd -u {username}", shell=True, timeout=10)
        d = load_json(BLOCK_FILE, {})
        if username in d: d.pop(username); save_json(BLOCK_FILE, d)
        return True
    except: return False
def get_block_info(username):
    return load_json(BLOCK_FILE, {}).get(username)

def count_users_by_period():
    d = load_json(USERS_FILE, {})
    today = datetime.now().strftime("%Y-%m-%d")
    week = (datetime.now()-timedelta(days=7)).strftime("%Y-%m-%d")
    month = datetime.now().strftime("%Y-%m")
    hari = sum(1 for u in d.values() if (u.get("last_seen","")[:10] == today))
    minggu = sum(1 for u in d.values() if (u.get("last_seen","")[:10] >= week))
    bulan = sum(1 for u in d.values() if (u.get("last_seen","")[:7] == month))
    return {"hari": hari, "minggu": minggu, "bulan": bulan, "total": len(d)}

def get_server_status():
    result = []
    today = datetime.now().date()
    accs = load_json(ACCOUNTS_FILE, {})
    for key, srv in SERVERS.items():
        used = 0
        for a in accs.values():
            if a.get("server_key") != key: continue
            try:
                ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
                if (ed - today).days >= 0: used += 1
            except: pass
        mx = int(srv.get("slot_max", 50))
        stat = "🟢 Online" if max(0, mx - used) > 0 else "🔴 Full"
        result.append({"name": srv.get("name","-"), "used": used, "max": mx, "status": stat})
    return result

def save_servers():
    cfg = load_config(); cfg["servers"] = SERVERS; save_config(cfg)

def server_list_text():
    lines = ["<blockquote>", "💻 <b>KELOLA SERVER</b>", "───────────────────────", ""]
    for key, srv in SERVERS.items():
        lines.append(f"<b>{srv.get('name','-')}</b>")
        lines.append(f"├ Harga Harian  : <b>{rupiah(srv.get('price_day',0))}</b>")
        lines.append(f"├ Harga Bulanan : <b>{rupiah(srv.get('price_month',0))}</b>")
        lines.append(f"├ Limit IP      : <b>{srv.get('ip_limit',1)} IP</b>")
        lines.append(f"╰ Slot Server  : <b>{srv.get('slot_max',50)}</b>")
        lines.append("")
    lines.append("───────────────────────"); lines.append("</blockquote>")
    return "\n".join(lines)

def kb_server_list():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k].get('name','-'), callback_data=f"srv_edit|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def kb_srv_field(key):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("Nama Server", callback_data=f"srv_set|{key}|name"),
         InlineKeyboardButton("Harga Bulanan", callback_data=f"srv_set|{key}|price_month")],
        [InlineKeyboardButton("Limit IP", callback_data=f"srv_set|{key}|ip_limit"),
         InlineKeyboardButton("Slot Server", callback_data=f"srv_set|{key}|slot_max")],
        [InlineKeyboardButton("Domain Server", callback_data=f"srv_set|{key}|domain")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="admin|srv")]])

def get_user_topup_stats(uid_key):
    d = load_json(TRX_FILE, [])
    today = datetime.now().strftime("%Y-%m-%d")
    week = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    month = datetime.now().strftime("%Y-%m")
    tops = [t for t in d if str(t.get("user_id")) == str(uid_key) and t.get("tipe") == "isi_saldo"]
    return {"hari": sum(t["jumlah"] for t in tops if t["waktu"].startswith(today)),
            "minggu": sum(t["jumlah"] for t in tops if t["waktu"][:10] >= week),
            "bulan": sum(t["jumlah"] for t in tops if t["waktu"].startswith(month)),
            "total": sum(t["jumlah"] for t in tops)}

def count_active_accounts(uid_key):
    d = load_json(ACCOUNTS_FILE, {})
    today = datetime.now().date()
    cnt = 0
    for a in d.values():
        if str(a.get("user_id")) != str(uid_key): continue
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
            if (ed - today).days >= 0: cnt += 1
        except: pass
    return cnt

def user_detail_text(uid_key):
    users = load_json(USERS_FILE, {})
    u = users.get(str(uid_key), {})
    name = u.get("first_name") or "-"
    uname = u.get("username") or "-"
    ls = (u.get("last_seen") or "-")[:10]
    saldo = get_bal(uid_key)
    akun_aktif = count_active_accounts(uid_key)
    top = get_user_topup_stats(uid_key)
    uname_line = f"@{uname}" if uname != "-" else "-"
    lines = ["<blockquote>"]
    lines.append(f"👤 <b>{name}</b>")
    lines.append(f"├ Username    : {uname_line}")
    lines.append(f"├ Chat ID     : <code>{uid_key}</code>")
    lines.append(f"├ Bergabung   : {ls}")
    lines.append(f"├ Total Saldo : <b>{rupiah(saldo)}</b>")
    lines.append(f"╰ Total Akun Aktif : <b>{akun_aktif}</b>")
    lines.append("")
    lines.append("💰 <b>Riwayat Topup</b>")
    lines.append(f"├ Hari Ini    : {rupiah(top['hari'])}")
    lines.append(f"├ Minggu Ini  : {rupiah(top['minggu'])}")
    lines.append(f"├ Bulan Ini   : {rupiah(top['bulan'])}")
    lines.append(f"╰ Total       : {rupiah(top['total'])}")
    lines.append("</blockquote>")
    return "\n".join(lines)

def list_users_paged(page=0, per=10):
    users = load_json(USERS_FILE, {})
    keys = [k for k in users.keys() if int(k) not in ADMIN_IDS]
    keys.sort(key=lambda k: users[k].get("last_seen",""), reverse=True)
    total = len(keys)
    tp = max(1, (total + per - 1) // per)
    page = max(0, min(page, tp - 1))
    start = page * per
    chunk = keys[start:start+per]
    lines = ["<blockquote>", "👤 <b>DAFTAR PENGGUNA</b>", "──────────────────────",
             f"👥 Total User : <b>{total}</b>", ""]
    for i, k in enumerate(chunk, start=start+1):
        u = users[k]
        lines.append(f"{i}. 👤 {u.get('first_name') or '-'}")
    lines += ["", "──────────────────────", f"Halaman {page+1}/{tp}", "──────────────────────", "</blockquote>"]
    return "\n".join(lines), chunk, page, tp, total

def kb_user_list(chunk, page, tp):
    rows = []
    users = load_json(USERS_FILE, {})
    for k in chunk:
        n = users.get(k, {}).get("first_name") or "-"
        rows.append([InlineKeyboardButton(f"👤 {n}", callback_data=f"admin|user|{k}|{page}")])
    nav = []
    if page > 0: nav.append(InlineKeyboardButton("◀ Prev", callback_data=f"admin|users|{page-1}"))
    nav.append(InlineKeyboardButton(f"{page+1}/{tp}", callback_data="noop"))
    if page < tp - 1: nav.append(InlineKeyboardButton("Next ▶", callback_data=f"admin|users|{page+1}"))
    if nav: rows.append(nav)
    rows.append([InlineKeyboardButton("🔄 Refresh", callback_data=f"admin|users|{page}"),
                 InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def kb_user_detail(uid_key, page):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔄 Refresh", callback_data=f"admin|user|{uid_key}|{page}")],
        [InlineKeyboardButton("🔙 Kembali", callback_data=f"admin|users|{page}")]])

def kb_admin():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("💻 Kelola VPN", callback_data="admin|srv"),
         InlineKeyboardButton("👤 Daftar Pengguna", callback_data="admin|users|0")],
        [InlineKeyboardButton("📢 Broadcast", callback_data="admin|bc")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def kb_acc_detail(un):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🗑️ Hapus", callback_data=f"del_acc|{un}")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="my_accs")]])

def dashboard_text(user, uid):
    uname = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid)
    total_users = len(load_json(USERS_FILE, {}))
    lines = ["<blockquote>", "💻 <b>SANSXML VPN STORE</b>", "───────────────────────", "👤 <b>Profil</b>"]
    lines.append(f"├ User Telegram  : {uname}")
    lines.append(f"├ Chat ID        : <code>{uid}</code>")
    lines.append(f"├ Keanggotaan    : {role}")
    lines.append(f"├ Total Pengguna : <b>{total_users}</b>")
    lines.append(f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>")
    lines += ["", "🌍 <b>Info Global</b>"]
    lines.append(f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>")
    lines.append(f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>")
    lines.append(f"╰ Keseluruhan    : <b>{st['total']} Akun</b>")
    lines += ["", "🌐 <b>Informasi</b>"]
    lines.append(f"├ Server Tersedia : <b>{len(SERVERS)} Server</b>")
    lines.append(f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>")
    lines += ["", "───────────────────────", "</blockquote>"]
    return "\n".join(lines)

def pilih_layanan_text():
    return ("<blockquote>\n💻 <b>PILIH LAYANAN VPN</b>\n───────────────────────\n"
            "Silakan pilih protokol yang ingin dibuat:\n───────────────────────\n</blockquote>")

def ssh_server_text():
    lines = ["<blockquote>", "<b>💻 SSH OVPN</b>", "─────────────────────────", ""]
    for key, srv in SERVERS.items():
        used, mx = get_slot_info(key)
        cek = "✅" if max(0, mx-used) > 0 else "❌"
        lines.append(f"◆ {srv['name']}")
        lines.append(f"├ Harga Harian   : <b>{rupiah(srv['price_day'])}</b>")
        lines.append(f"├ Harga Bulanan  : <b>{rupiah(srv['price_month'])}</b>")
        lines.append("├ Kuota          : Unlimited")
        lines.append(f"├ Limit IP       : {srv['ip_limit']} IP")
        lines.append(f"╰ Slot Tersedia  : <b>{used}/{mx} {cek}</b>")
        lines.append(""); lines.append("")
    lines += ["─────────────────────────", "</blockquote>"]
    return "\n".join(lines)

def kb_pilih_layanan():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ SSH OVPN", callback_data="pilih|ssh")],
        [InlineKeyboardButton("➕ VMESS", callback_data="pilih|vmess"),
         InlineKeyboardButton("➕ VLESS", callback_data="pilih|vless")],
        [InlineKeyboardButton("➕ TROJAN", callback_data="pilih|trojan")],
        [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]])

def kb_ssh_server():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k]['name'], callback_data=f"buat|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="pilih_layanan")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_extend():
    rows = []; keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            row.append(InlineKeyboardButton(SERVERS[k]['name'], callback_data=f"extend|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")])
    return InlineKeyboardMarkup(rows)

def kb_coming_soon(p): return InlineKeyboardMarkup([[InlineKeyboardButton("🔙 KEMBALI", callback_data="pilih_layanan")]])

def kb_dashboard(uid):
    rows = [
        [InlineKeyboardButton("➕ BUAT AKUN", callback_data="buat_akun"),
         InlineKeyboardButton("⌛ TRIAL AKUN", callback_data="trial_akun")],
        [InlineKeyboardButton("🔄 PERPANJANG AKUN", callback_data="perpanjang_akun")],
        [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo"),
         InlineKeyboardButton("👤 AKUN SAYA", callback_data="my_accs")],
        [InlineKeyboardButton("♻️ REFRESH", callback_data="refresh")]]
    if is_owner(uid): rows.append([InlineKeyboardButton("💻 PENGATURAN", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def saldo_text(uid, nominal=""):
    return ("<blockquote>\n💰 <b>Silakan masukkan jumlah nominal topup saldo yang Anda inginkan:</b>\n\n"
            f"Jumlah saat ini: <b>{rupiah(get_bal(uid))}</b>\n\n"
            f"Nominal input: <b>{rupiah(nominal) if nominal else 'Rp 0'}</b>\n\n"
            f"<i>Minimal topup {rupiah(MIN_TOPUP)}</i>\n</blockquote>")

def kb_saldo():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("1", callback_data="saldo_num|1"), InlineKeyboardButton("2", callback_data="saldo_num|2"), InlineKeyboardButton("3", callback_data="saldo_num|3")],
        [InlineKeyboardButton("4", callback_data="saldo_num|4"), InlineKeyboardButton("5", callback_data="saldo_num|5"), InlineKeyboardButton("6", callback_data="saldo_num|6")],
        [InlineKeyboardButton("7", callback_data="saldo_num|7"), InlineKeyboardButton("8", callback_data="saldo_num|8"), InlineKeyboardButton("9", callback_data="saldo_num|9")],
        [InlineKeyboardButton("⬅️ Hapus", callback_data="saldo_hapus"), InlineKeyboardButton("0", callback_data="saldo_num|0"), InlineKeyboardButton("✅ Konfirmasi", callback_data="saldo_konfirmasi")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def acc_caption(u, p, exp, dl, ip, manual=False, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {})
    head = "TRIAL" if is_trial else ("MANUAL" if manual else "PREMIUM")
    BULAN_ID = ["Jan","Feb","Mar","Apr","Mei","Jun","Jul","Agu","Sep","Okt","Nov","Des"]
    try:
        exp_d = datetime.strptime(exp,"%Y-%m-%d")
        exp_fmt = f"{exp_d.day} {BULAN_ID[exp_d.month-1]}, {exp_d.year}"
        now = datetime.now()
        try: days_int = int(dl.split()[0])
        except: days_int = 30
        created = now - timedelta(days=days_int)
        created_fmt = f"{created.day} {BULAN_ID[created.month-1]}, {created.year}"
    except: exp_fmt = exp; created_fmt = "-"
    ssh_ovpn_val = srv.get("ssh_ovpn") or srv.get("name","SG NEWMEDIA").replace("🇸🇬 ","").strip()
    srv_host = srv.get("domain") or SSH_HOST
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: [host][crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
    lines = ["<blockquote>"]
    lines += ["◤ <b>SSH OVPN ACCOUNT</b> ◢", f"     ❖ <b>{head}</b> ❖", "━━━━━━━━━━━━━━━━━━━━━━━", "", ""]
    lines += [f"City       : {srv.get('city','Singapore')}",
              f"ISP        : {srv.get('isp','DigitalOcean LLC')}",
              f"SSH OVPN   : {ssh_ovpn_val}",
              f"Username   : {u}",
              f"Password   : {p}",
              "Quota      : Unlimited",
              f"Limit IP   : {ip} IP", "", ""]
    lines += ["━━━━━━━━━━━━━━━━━━━━━━━", "", ""]
    lines += [f"Host     : {srv_host}", "OpenSSH  : 443, 80, 22", "Dropbear : 443, 109",
              "SSH WS   : 80, 8080, 8081-9999", "SSH SSL  : 443", "SSH UDP  : 1-65535",
              "OVPN     : 443, 1194, 2200", "BadVPN   : 7100, 7300", "━━━━━━━━━━━━━━━━━━━━━━━"]
    lines += [f"SSL : {srv_host}:443@{u}:{p}", "", f"WS  : {srv_host}:80@{u}:{p}", "", f"UDP : {srv_host}:1-65535@{u}:{p}",
              "━━━━━━━━━━━━━━━━━━━━━━━", "", "PAYLOAD WS", payload_ws, "", "PAYLOAD TLS", payload_tls,
              "━━━━━━━━━━━━━━━━━━━━━━━", "", f"Durasi   : {dl}", f"Dibuat   : {created_fmt}", f"Berakhir : {exp_fmt}", "",
              "━━━━━━━━━━━━━━━━━━━━━━━", "<b>      ◤ SANSXML VPN STORE ◢</b>",
              "<i>❖ Terima kasih telah menggunakan layanan kami ❖</i>", "</blockquote>"]
    return "\n".join(lines)

async def do_create_account(chat, uid, user, username, password, hari, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {})
    ip_limit = int(srv.get("ip_limit", 2))
    price = 0 if is_trial else get_price(hari, server_key)
    if not is_trial and get_bal(uid) < price:
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
        await chat.send_message(
            f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
            f"Silakan topup saldo melalui menu\nTombol <b>💰 TOPUP SALDO</b>.",
            reply_markup=kb, parse_mode="HTML")
        return
    server_num = get_server_slot_number(server_key)
    load_txt = f"⚙️ Membuat <b>{'TRIAL' if is_trial else 'PREMIUM'} AKUN</b> untuk server <b>{server_num}</b>..."
    msg = await chat.send_message(load_txt, parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create, username, password, hari, is_trial)
    if not is_trial:
        ok, nb = reduce_bal(uid, price)
        if not ok:
            await msg.edit_text("❌ Saldo berubah.", parse_mode="HTML"); return
    save_acc(username, {
        "user_id":uid,"username":username,"password":password,
        "exp":r["exp"],"exp_ts":r.get("exp_ts",""),"days":hari,"limit_ip":ip_limit,"harga":price,
        "created_at":datetime.now().isoformat(),"first_name":user.first_name or "",
        "username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":server_key,
        "server": srv.get("name","SG NEWMEDIA")})
    if not is_trial:
        add_trx(uid, user.first_name or "User", user.username or "", "buat_akun", price, f"{hari}h {srv.get('name','')}")
    dl_txt = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    exp_show = r.get("exp_ts","")[:10] if is_trial else r["exp"]
    await msg.edit_text(acc_caption(username, password, exp_show, dl_txt, ip_limit, r.get("manual",False), is_trial, server_key), parse_mode="HTML")

async def do_extend_account(chat, uid, user, username, hari, server_key):
    price = get_price(hari, server_key)
    if get_bal(uid) < price:
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
        await chat.send_message(
            f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Perpanjang : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
            f"Silakan topup saldo melalui menu\nTombol <b>💰 TOPUP SALDO</b>.",
            reply_markup=kb, parse_mode="HTML")
        return
    msg = await chat.send_message(f"⚙️ Memperpanjang akun <b>{username}</b> selama <b>{hari} hari</b>...", parse_mode="HTML")
    a = get_acc(username)
    try: old_exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
    except: old_exp = datetime.now().date()
    base = old_exp if old_exp > datetime.now().date() else datetime.now().date()
    new_exp = base + timedelta(days=hari)
    new_exp_str = new_exp.strftime("%Y-%m-%d")
    ok = await asyncio.to_thread(ssh_extend, username, new_exp_str)
    if not ok:
        await msg.edit_text("❌ Gagal perpanjang.", parse_mode="HTML"); return
    a["exp"] = new_exp_str; a["exp_ts"] = new_exp_str + " 23:59:59"
    a["days"] = int(a.get("days", 0)) + hari
    a["harga"] = int(a.get("harga", 0)) + price
    save_acc(username, a)
    ok2, _ = reduce_bal(uid, price)
    if not ok2:
        await msg.edit_text("❌ Gagal potong saldo.", parse_mode="HTML"); return
    add_trx(uid, user.first_name or "User", user.username or "", "perpanjang", price, f"{hari}h {username}")
    await msg.edit_text(acc_caption(username, a["password"], new_exp_str, f"{a.get('days',30)} Hari",
        a.get("limit_ip",1), a.get("manual",False), a.get("is_trial",False), server_key), parse_mode="HTML")

async def _do_delete_account(uid, uname, user, chat):
    a = get_acc(uname)
    if not a or a.get("user_id") != uid: return
    refund = 0 if (a.get("is_trial") or int(a.get("harga",0)) <= 0) else hitung_refund(a)
    try: await asyncio.to_thread(ssh_delete, uname)
    except: pass
    delete_acc_json(uname)
    if refund > 0:
        try:
            add_bal(uid, refund)
            add_trx(uid, user.first_name or "", user.username or "", "refund", refund, f"hapus {uname}")
        except: pass

async def auto_cleanup_task():
    await asyncio.sleep(30)
    while True:
        try:
            now = datetime.now(); today = now.date(); dele = 0
            for un, a in list(load_json(ACCOUNTS_FILE, {}).items()):
                expired = False
                ets = a.get("exp_ts", "")
                if ets:
                    try:
                        if now >= datetime.strptime(ets, "%Y-%m-%d %H:%M:%S"): expired = True
                    except: pass
                else:
                    try:
                        if (today - datetime.strptime(a["exp"], "%Y-%m-%d").date()).days >= 1: expired = True
                    except: pass
                if expired:
                    await asyncio.to_thread(ssh_delete, un); delete_acc_json(un); dele += 1
            if dele > 0: logger.info(f"[AUTO-CLEANUP] {dele} expired")
            accs = load_json(ACCOUNTS_FILE, {}); blk = load_json(BLOCK_FILE, {})
            for un, a in accs.items():
                if a.get("is_trial"): continue
                if un in blk: continue
                limit_ip = int(a.get("limit_ip", 1))
                over, sessions, ips = await asyncio.to_thread(check_limit, un, limit_ip)
                if over:
                    if await asyncio.to_thread(block_user, un, BLOCK_HOURS):
                        logger.info(f"[BLOCK] {un} - sessions={sessions} ips={len(ips)} > limit={limit_ip}")
            blk = load_json(BLOCK_FILE, {}); changed = False
            for un, info in list(blk.items()):
                try:
                    if now >= datetime.strptime(info["unblock_at"], "%Y-%m-%d %H:%M:%S"):
                        await asyncio.to_thread(unblock_user, un); changed = True
                except: pass
            if changed: logger.info("[UNBLOCK] akun terblokir dibuka otomatis")
        except Exception as e: logger.error(f"cleanup: {e}")
        await asyncio.sleep(60)

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

    if d == "refresh":
        try: await q.message.delete()
        except: pass
        try: await chat.send_message(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")
        except: pass
        return

    if d == "isi_saldo":
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(saldo_text(uid), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("saldo_num|"):
        cur = c.user_data.get("saldo_input", "")
        add = d.split("|",1)[1]
        if len(cur) >= 9: await q.answer("Maks 9 digit", show_alert=True); return
        cur = (cur + add).lstrip("0") or ""
        c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid, cur), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d == "saldo_hapus":
        cur = c.user_data.get("saldo_input", "")
        cur = cur[:-1] if cur else ""
        c.user_data["saldo_input"] = cur
        try: await q.edit_message_text(saldo_text(uid, cur), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d == "saldo_konfirmasi":
        cur = c.user_data.get("saldo_input", "")
        if not cur or int(cur) <= 0: await q.answer("Nominal belum diisi!", show_alert=True); return
        nominal = int(cur)
        if nominal < MIN_TOPUP: await q.answer(f"❌ Minimal topup {rupiah(MIN_TOPUP)}", show_alert=True); return
        saldo_baru = add_bal(uid, nominal)
        add_trx(uid, u.effective_user.first_name or "", u.effective_user.username or "", "isi_saldo", nominal, "topup")
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(
            f"✅ <b>Topup Saldo Berhasil</b>\n\n<blockquote>💰 Nominal: <b>{rupiah(nominal)}</b>\n💼 Saldo Sekarang: <b>{rupiah(saldo_baru)}</b></blockquote>\n\n"
            f"<i>❖ Saldo dapat digunakan untuk membuat akun VPN ❖</i>",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]]), parse_mode="HTML")
        except: pass
        return

    if d == "buat_akun":
        c.user_data.clear(); c.user_data["mode"] = "buat"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "trial_akun":
        c.user_data.clear(); c.user_data["mode"] = "trial"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "perpanjang_akun":
        c.user_data.clear(); c.user_data["mode"] = "perpanjang"
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d == "pilih_layanan":
        c.user_data["mode"] = c.user_data.get("mode", "buat")
        try: await q.edit_message_text(pilih_layanan_text(), reply_markup=kb_pilih_layanan(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("pilih|"):
        p = d.split("|")[1]; mode = c.user_data.get("mode", "buat")
        if p == "ssh":
            if mode == "perpanjang":
                try: await q.edit_message_text(ssh_server_text(), reply_markup=kb_ssh_server_extend(), parse_mode="HTML")
                except: pass
            else:
                try: await q.edit_message_text(ssh_server_text(), reply_markup=kb_ssh_server(), parse_mode="HTML")
                except: pass
        else:
            try: await q.edit_message_text(f"⚠️ <b>{p.upper()} BELUM TERSEDIA</b>\n\nSegera hadir. Sementara gunakan <b>SSH OVPN</b>.", reply_markup=kb_coming_soon(p), parse_mode="HTML")
            except: pass
        return
    if d == "menu|main":
        c.user_data.clear()
        try: await q.edit_message_text(dashboard_text(u.effective_user, uid), reply_markup=kb_dashboard(uid), parse_mode="HTML")
        except: pass
        return

    if d.startswith("extend|"):
        server_key = d.split("|")[1]
        if server_key not in SERVERS:
            await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
        try: await q.message.delete()
        except: pass
        c.user_data["extend_step"] = "username"
        c.user_data["extend_data"] = {"server_key": server_key}
        await chat.send_message("👤 <b>Masukkan username akun yang ingin diperpanjang :</b>", parse_mode="HTML")
        return

    if d.startswith("buat|"):
        server_key = d.split("|")[1]
        if server_key not in SERVERS:
            await chat.send_message("❌ Server tidak valid.", parse_mode="HTML"); return
        used, mx = get_slot_info(server_key)
        if used >= mx:
            await chat.send_message(f"<blockquote>❌ <b>Slot Penuh</b>\n\nServer <b>{SERVERS[server_key]['name']}</b>\nSlot tersedia: <b>{used}/{mx}</b></blockquote>", parse_mode="HTML"); return
        mode = c.user_data.get("mode", "buat")
        try: await q.message.delete()
        except: pass
        if mode == "trial":
            if trial_left(uid) <= 0:
                await chat.send_message("🚫 <b>Batas trial hari ini telah tercapai.</b>\nSilakan coba lagi besok.", parse_mode="HTML"); return
            use_trial(uid)
            uniq = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
            c.user_data.clear()
            await do_create_account(chat, uid, u.effective_user, f"trial-{uniq}", f"trial{uniq}", 1, is_trial=True, server_key=server_key)
            return
        else:
            c.user_data["buat_step"] = "username"
            c.user_data["buat_data"] = {"server_key": server_key}
            await chat.send_message("👤 <b>Masukkan username akun :</b>", parse_mode="HTML")
            return

    if d == "my_accs":
        accs = []
        for a in get_user_accs(uid):
            if a.get("is_trial",False): continue
            try:
                if (datetime.strptime(a["exp"],"%Y-%m-%d").date() - datetime.now().date()).days < 0: continue
            except: pass
            accs.append(a)
        hdr = ["<blockquote>", "💻 <b>AKUN SAYA</b>", "───────────────────────", "", f"📭 Total Akun : <b>{len(accs)}</b>", ""]
        if not accs: hdr += ["Belum ada akun premium.", "Silakan buat akun terlebih dahulu.", ""]
        hdr += ["───────────────────────", "</blockquote>"]
        if not accs:
            rows = [[InlineKeyboardButton("➕ BUAT AKUN", callback_data="buat_akun")],
                    [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]]
        else:
            rows = []
            for a in accs[:20]:
                un = a.get("username","")
                b = get_block_info(un)
                rows.append([InlineKeyboardButton(f"{'🚫' if b else '👤'} {un}{' (DIBLOKIR)' if b else ''}", callback_data=f"acc_detail|{un}")])
            rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")])
        try: await q.edit_message_text("\n".join(hdr), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        dl_txt = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
        ref = 0 if (a.get("is_trial") or int(a.get("harga",0)) <= 0) else hitung_refund(a)
        cap = acc_caption(un, a['password'], a['exp'], dl_txt, a.get('limit_ip',IP_LIMIT), a.get('manual',False), a.get('is_trial',False), a.get('server_key','sg_1ip'))
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date(); sh = max(0,(ed-datetime.now().date()).days); th = int(a.get("days",30))
        except: sh = 0; th = 30
        b = get_block_info(un)
        if b:
            try:
                ua = datetime.strptime(b["unblock_at"], "%Y-%m-%d %H:%M:%S")
                total_min = max(0, int((ua - datetime.now()).total_seconds() // 60))
                cap += f"\n\n🚫 <b>AKUN SEDANG DIBLOKIR</b>\n├ Alasan: Melebihi limit IP\n╰ Terbuka otomatis dalam: <b>{total_min//60}j {total_min%60}m</b>"
            except: pass
        else:
            if ref > 0: cap += f"\n\n💰 <b>Refund: {rupiah(ref)}</b>\n<i>({sh}/{th} hari)</i>"
            else: cap += f"\n\n💰 <i>Refund: Rp 0</i>"
        try: await q.edit_message_text(cap, reply_markup=kb_acc_detail(un), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        ref = 0 if (a.get("is_trial") or int(a.get("harga", 0)) <= 0) else hitung_refund(a)
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date(); sh = max(0,(ed-datetime.now().date()).days); th = int(a.get("days",30))
        except: sh = 0; th = 30
        ha = int(a.get("harga",0))
        await _do_delete_account(uid, un, u.effective_user, chat)
        try: await q.delete_message()
        except: pass
        sb = get_bal(uid)
        if ref > 0:
            try: await chat.send_message(
                f"✅ <b>Akun Dihapus</b>\n\n<blockquote>👤 <b>Akun</b>\n├ User: <code>{un}</code>\n├ Server: <b>{a.get('server','SG').replace('🇸🇬 ','').strip()}</b>\n├ Durasi: <b>{th} Hari</b>\n╰ Harga: <b>{rupiah(ha)}</b></blockquote>\n"
                f"<blockquote>💰 <b>Refund</b>\n├ Sisa: <b>{sh}/{th} hari</b>\n├ Persen: <b>{int(round(sh/th*100)) if th>0 else 0}%</b>\n╰ Refund: <b>{rupiah(ref)}</b></blockquote>\n"
                f"<blockquote>💼 Saldo: <b>{rupiah(sb)}</b></blockquote>\n\n<i>❖ Refund masuk ke saldo ❖</i>", parse_mode="HTML")
            except: pass
        else:
            try: await chat.send_message(f"✅ <b>Akun Dihapus</b>\n\n👤 <code>{un}</code>\n💰 Refund: <b>Rp 0</b>", parse_mode="HTML")
            except: pass
        return

    if d == "admin|menu":
        if not is_owner(uid): return
        inc = get_income(); us = count_users_by_period()
        svr_stat = get_server_status()
        svr_txt = "\n".join([f"├ {s['name']}\n│ ├ Slot   : <b>{s['used']}/{s['max']}</b>\n│ ╰ Status : <b>{s['status']}</b>" for s in svr_stat])
        txt = (
            "<blockquote>"
            "<b>PENGATURAN VPS BOT VPN</b>\n"
            "───────────────────────\n"
            f"👥 Total User : <b>{us['total']}</b>\n"
            f"   Total Akun : <b>{count_accounts()}</b>\n\n"
            "📈 <b>PENGHASILAN</b>\n"
            f"├ Hari Ini   : <b>{rupiah(inc['hari'])}</b>\n"
            f"├ Minggu Ini : <b>{rupiah(inc['minggu'])}</b>\n"
            f"├ Bulan Ini  : <b>{rupiah(inc['bulan'])}</b>\n"
            f"└ Total      : <b>{rupiah(inc['total'])}</b>\n\n"
            "👤 <b>JUMLAH USER</b>\n"
            f"├ Hari Ini   : <b>{us['hari']}</b>\n"
            f"├ Minggu Ini : <b>{us['minggu']}</b>\n"
            f"├ Bulan Ini  : <b>{us['bulan']}</b>\n"
            f"└ Total      : <b>{us['total']}</b>\n\n"
            "📡 <b>STATUS VPS SG</b>\n"
            f"{svr_txt}\n"
            "───────────────────────\n"
            "</blockquote>")
        try: await q.edit_message_text(txt, reply_markup=kb_admin(), parse_mode="HTML")
        except: pass
        return

    if d.startswith("admin|users|"):
        if not is_owner(uid): return
        try: page = int(d.split("|")[2])
        except: page = 0
        try:
            txt, chunk, page, tp, total = list_users_paged(page)
            await q.edit_message_text(txt, reply_markup=kb_user_list(chunk, page, tp), parse_mode="HTML")
        except Exception as e: logger.error(f"users list: {e}")
        return
    if d.startswith("admin|user|"):
        if not is_owner(uid): return
        parts = d.split("|")
        if len(parts) < 4: return
        target_uid = parts[2]
        try: page = int(parts[3])
        except: page = 0
        try:
            txt = user_detail_text(target_uid)
            await q.edit_message_text(txt, reply_markup=kb_user_detail(target_uid, page), parse_mode="HTML")
        except Exception as e: logger.error(f"user detail: {e}")
        return

    if d == "admin|srv":
        if not is_owner(uid): return
        try: await q.edit_message_text(server_list_text(), reply_markup=kb_server_list(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_edit|"):
        if not is_owner(uid): return
        key = d.split("|")[1]
        if key not in SERVERS:
            await q.answer("Server tidak ditemukan", show_alert=True); return
        srv = SERVERS[key]
        txt = (
            f"<blockquote><b>{srv.get('name','-')}</b>\n───────────────────────\n"
            f"├ Harga Harian  : <b>{rupiah(srv.get('price_day',0))}</b>\n"
            f"├ Harga Bulanan : <b>{rupiah(srv.get('price_month',0))}</b>\n"
            f"├ Limit IP      : <b>{srv.get('ip_limit',1)} IP</b>\n"
            f"├ Slot Server  : <b>{srv.get('slot_max',50)}</b>\n"
            f"╰ Domain       : <b>{srv.get('domain','-')}</b>\n\n"
            f"Pilih yang ingin diubah:\n───────────────────────\n</blockquote>")
        try: await q.edit_message_text(txt, reply_markup=kb_srv_field(key), parse_mode="HTML")
        except: pass
        return
    if d.startswith("srv_set|"):
        if not is_owner(uid): return
        parts = d.split("|")
        if len(parts) < 3: return
        key = parts[1]; field = parts[2]
        if key not in SERVERS:
            await q.answer("Server tidak ditemukan", show_alert=True); return
        c.user_data["srv_edit"] = {"key": key, "field": field}
        if field == "name":
            prompt = f"Kirim nama baru untuk server <b>{SERVERS[key].get('name','-')}</b>\nContoh: <code>🇸🇬 PRIME SG-01</code>"
        elif field == "price_month":
            prompt = f"Kirim harga BULANAN (30 hari) baru untuk <b>{SERVERS[key].get('name','-')}</b>\nContoh: <code>3510</code>\n<i>Harga harian otomatis = harga bulanan ÷ 30</i>"
        elif field == "ip_limit":
            prompt = f"Kirim limit IP baru untuk <b>{SERVERS[key].get('name','-')}</b>\nContoh: <code>2</code>"
        elif field == "slot_max":
            prompt = f"Kirim jumlah slot server baru untuk <b>{SERVERS[key].get('name','-')}</b>\nContoh: <code>50</code>"
        elif field == "domain":
            prompt = f"Kirim DOMAIN baru untuk <b>{SERVERS[key].get('name','-')}</b>\nContoh: <code>sgivip.naaofficial.web.id</code>\nAtau IP VPS: <code>103.150.100.50</code>\n\n<i>Bot akan cek domain ke DNS & cocokkan dengan IP VPS.</i>"
        try: await q.edit_message_text(prompt, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data=f"srv_edit|{key}")]]), parse_mode="HTML")
        except: pass
        return

    if d == "admin|bc":
        if not is_owner(uid): return
        c.user_data["bc_wait"] = True
        try: await q.edit_message_text(
            "📢 <b>BROADCAST PENGUMUMAN</b>\n\n"
            "Silakan ketik pesan pengumuman yang ingin dikirim ke semua user.\n\n"
            "<i>Pesan akan dikirim ke seluruh user bot (kecuali yang memblokir bot).</i>",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("❌ Batal", callback_data="admin|menu")]]),
            parse_mode="HTML")
        except: pass
        return
    if d == "bc_send":
        if not is_owner(uid): return
        msg_text = c.user_data.get("bc_text", "")
        if not msg_text:
            await q.answer("Pesan kosong!", show_alert=True); return
        try: await q.edit_message_text("📤 <b>Mengirim broadcast...</b>", parse_mode="HTML")
        except: pass
        users = load_json(USERS_FILE, {})
        ok_count = 0; fail_count = 0
        for tuid in users.keys():
            try:
                await c.bot.send_message(chat_id=int(tuid), text=msg_text, parse_mode="HTML")
                ok_count += 1
            except Exception: fail_count += 1
            await asyncio.sleep(0.05)
        c.user_data["bc_text"] = ""
        c.user_data["bc_wait"] = False
        try: await q.edit_message_text(
            f"✅ <b>Broadcast Selesai</b>\n\n<blockquote>"
            f"├ Sukses : <b>{ok_count}</b>\n"
            f"╰ Gagal  : <b>{fail_count}</b>\n"
            f"</blockquote>\n\n"
            f"<i>❖ Pesan berhasil dikirim ke user yang tidak memblokir bot ❖</i>",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]),
            parse_mode="HTML")
        except: pass
        return

async def msg(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    t = (u.message.text or "").strip()

    srv_edit = c.user_data.get("srv_edit")
    if srv_edit and is_owner(uid):
        key = srv_edit.get("key"); field = srv_edit.get("field")
        val = t.strip()
        if key not in SERVERS:
            c.user_data["srv_edit"] = None
            await u.message.reply_text("❌ Server tidak ditemukan.", parse_mode="HTML"); return
        srv = SERVERS[key]
        try:
            if field == "name":
                if len(val) < 3:
                    await u.message.reply_text("❌ Nama minimal 3 karakter. Coba lagi:", parse_mode="HTML"); return
                srv["name"] = val
                msg_out = f"Nama server diubah → <b>{val}</b>"
            elif field == "price_month":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0:
                    await u.message.reply_text("❌ Angka tidak valid. Coba lagi:", parse_mode="HTML"); return
                srv["price_month"] = angka
                srv["price_day"] = max(1, int(round(angka / 30)))
                msg_out = (f"Harga bulanan → <b>{rupiah(angka)}</b>\n"
                           f"Harga harian otomatis → <b>{rupiah(srv['price_day'])}</b>")
            elif field == "ip_limit":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0:
                    await u.message.reply_text("❌ Angka tidak valid. Coba lagi:", parse_mode="HTML"); return
                srv["ip_limit"] = angka
                msg_out = f"Limit IP → <b>{angka} IP</b>"
            elif field == "slot_max":
                angka = int(re.sub(r'[^0-9]','',val))
                if angka <= 0:
                    await u.message.reply_text("❌ Angka tidak valid. Coba lagi:", parse_mode="HTML"); return
                srv["slot_max"] = angka
                msg_out = f"Slot Server → <b>{angka}</b>"
            elif field == "domain":
                cek_msg = await u.message.reply_text("⏳ Mengecek domain...")
                ok_dom, tipe_dom, resolved_ip = is_valid_domain(val)
                try: await cek_msg.delete()
                except: pass
                if not ok_dom:
                    await u.message.reply_text(
                        f"❌ <b>Domain Tidak Valid</b>\n\n"
                        f"Alasan: {tipe_dom}\n\n"
                        f"Contoh yang valid:\n"
                        f"├ <code>sgivip.naaofficial.web.id</code>\n"
                        f"├ <code>sg1.premium.com</code>\n"
                        f"╰ <code>103.150.100.50</code>\n\n"
                        f"Coba kirim ulang:",
                        parse_mode="HTML")
                    return
                srv["domain"] = val
                msg_out = f"Domain ({tipe_dom}) → <b>{val}</b>"
            else:
                c.user_data["srv_edit"] = None
                await u.message.reply_text("❌ Field tidak valid.", parse_mode="HTML"); return
            save_servers()
            c.user_data["srv_edit"] = None
            await u.message.reply_text(
                f"<blockquote>{msg_out}\n\n"
                f"<b>Data Server Sekarang:</b>\n"
                f"├ Nama : <b>{srv.get('name','-')}</b>\n"
                f"├ Harga Harian : <b>{rupiah(srv.get('price_day',0))}</b>\n"
                f"├ Harga Bulanan : <b>{rupiah(srv.get('price_month',0))}</b>\n"
                f"├ Limit IP : <b>{srv.get('ip_limit',1)} IP</b>\n"
                f"├ Slot Server : <b>{srv.get('slot_max',50)}</b>\n"
                f"╰ Domain : <b>{srv.get('domain','-')}</b></blockquote>",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali ke Kelola", callback_data="admin|srv")]]),
                parse_mode="HTML")
            return
        except Exception as e:
            await u.message.reply_text(f"❌ Error: {e}\nCoba lagi:", parse_mode="HTML"); return

    if c.user_data.get("bc_wait") and is_owner(uid):
        c.user_data["bc_wait"] = False
        c.user_data["bc_text"] = t
        preview = ("📢 <b>PREVIEW BROADCAST</b>\n\n<blockquote>" + t + "</blockquote>\n\nKirim pesan ini ke semua user?")
        await u.message.reply_text(preview,
            reply_markup=InlineKeyboardMarkup([
                [InlineKeyboardButton("✅ Kirim", callback_data="bc_send")],
                [InlineKeyboardButton("❌ Batal", callback_data="admin|menu")]]),
            parse_mode="HTML")
        return

    step = c.user_data.get("buat_step")
    if step:
        data = c.user_data.get("buat_data",{})
        if step == "username":
            if not valid_username(t):
                await u.message.reply_text("🚫 <b>Username minimal 5 angka !!</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML")
                return
            if is_username_taken(t):
                await u.message.reply_text(f"🚫 <b>Username {t} sudah ada !!</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML")
                return
            data["username"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if step == "password":
            if not valid_password(t):
                await u.message.reply_text("🚫 <b>Password minimal 5 angka !!</b>", parse_mode="HTML")
                await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML")
                return
            data["password"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
        if step == "durasi":
            try: hari = int(re.sub(r'[^0-9]','',t))
            except:
                await u.message.reply_text("🚫 <b>Masa aktif tidak valid.</b>\n📅 <b>Masukkan 1–30 hari Contoh : 3</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML")
                return
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text("🚫 <b>Masa aktif tidak valid.</b>\n📅 <b>Masukkan 1–30 hari Contoh : 3</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML")
                return
            un = data.get("username"); pw = data.get("password")
            server_key = data.get("server_key", "sg_1ip")
            price = get_price(hari, server_key)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if get_bal(uid) < price:
                kb = InlineKeyboardMarkup([
                    [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
                    [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])
                await u.message.reply_text(
                    f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
                    f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
                    f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
                    f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
                    f"Silakan topup saldo melalui menu\nTombol <b>💰 TOPUP SALDO</b>.",
                    reply_markup=kb, parse_mode="HTML"); return
            await do_create_account(u.effective_chat, uid, u.effective_user, un, pw, hari, server_key=server_key)
            return

    estep = c.user_data.get("extend_step")
    if estep:
        data = c.user_data.get("extend_data", {})
        server_key = data.get("server_key", "sg_1ip")
        if estep == "username":
            if not is_username_taken(t):
                await u.message.reply_text("🚫 <b>Akun tidak ditemukan.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML")
                return
            a = get_acc(t)
            if not a or a.get("user_id") != uid:
                await u.message.reply_text("🚫 <b>Bukan akun Anda.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML")
                return
            if a.get("is_trial"):
                await u.message.reply_text("🚫 <b>Akun trial tidak bisa diperpanjang.</b>", parse_mode="HTML")
                await u.message.reply_text("👤 Masukkan username akun :", parse_mode="HTML")
                return
            data["username"] = t; c.user_data["extend_data"] = data; c.user_data["extend_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if estep == "password":
            a = get_acc(data.get("username"))
            if not a or a.get("password") != t:
                await u.message.reply_text("🚫 <b>Password salah.</b>", parse_mode="HTML")
                await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML")
                return
            c.user_data["extend_step"] = "durasi"
            try:
                sh = max(0, (datetime.strptime(a["exp"], "%Y-%m-%d").date() - datetime.now().date()).days)
                sisa_txt = f"\n<i>Sisa masa aktif: {sh} hari</i>"
            except: sisa_txt = ""
            await u.message.reply_text(f"📆 <b>Masukkan masa aktif tambahan 1-30 (hari) :</b>{sisa_txt}", parse_mode="HTML"); return
        if estep == "durasi":
            try: hari = int(re.sub(r'[^0-9]','',t))
            except:
                await u.message.reply_text("🚫 <b>Masa aktif tidak valid.</b>\n📅 <b>Masukkan 1–30 hari Contoh : 3</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML")
                return
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text("🚫 <b>Masa aktif tidak valid.</b>\n📅 <b>Masukkan 1–30 hari Contoh : 3</b>", parse_mode="HTML")
                await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML")
                return
            un = data.get("username")
            c.user_data["extend_step"] = None; c.user_data["extend_data"] = {}
            await do_extend_account(u.effective_chat, uid, u.effective_user, un, hari, server_key)
            return

async def handle_photo(u, c):
    await u.message.reply_text("Gunakan /start", reply_markup=ReplyKeyboardRemove())

async def post_init(app):
    try: await app.bot.set_my_commands([BotCommand("start", "⌂ Menu")])
    except: pass
    asyncio.create_task(auto_cleanup_task())
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
python3 -m py_compile /root/bot.py && echo -e "  ${GREEN}✓ Bot OK${NC}" || echo -e "  ${RED}❌ Bot error${NC}"

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
echo ""; echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}   ✓✓✓ INSTALASI SELESAI ✓✓✓${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo ""
for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot; do
    ST=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    printf "  %-14s : " "$s"
    [ "$ST" = "active" ] && echo -e "${GREEN}$ST${NC}" || echo -e "${RED}$ST${NC}"
done
if [ "$BACKUP_ENABLED" = "1" ]; then
    echo ""
    echo -e "  ${GREEN}✓ Auto Backup GitHub AKTIF${NC}"
    echo -e "  ${CYAN}Repo${NC}   : https://github.com/$GH_USER/$GH_REPO"
    echo -e "  ${CYAN}Interval${NC}: Setiap 5 menit"
fi
echo ""
echo -e "  ${CYAN}Domain${NC} : ${GREEN}$DOMAIN${NC}"
echo -e "  ${CYAN}Bot${NC}    : Cek di Telegram (/start)"
echo -e "  ${CYAN}Log${NC}    : tail -f /root/vpnbot.log"
echo ""
INSTALLEREOF

chmod +x /root/install.sh
echo "✅ INSTALLER SIAP: /root/install.sh"
wc -l /root/install.sh
echo ""
echo "Jalankan: bash /root/install.sh"