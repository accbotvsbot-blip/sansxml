cat > /root/install.sh << 'INSTALLEREOF'
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; NC='\033[0m'

spin(){
    local pid=$1 msg="$2"
    local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 $pid 2>/dev/null; do
        for x in "${f[@]}"; do
            printf "\r  ${CYAN}${x}${NC}  ${WHITE}%s${NC}   " "$msg"
            sleep 0.08
            kill -0 $pid 2>/dev/null || break
        done
    done
    printf "\r  ${GREEN}✓${NC}  ${WHITE}%s${NC}        \n" "$msg"
}

clear
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${CYAN}   SC AUTO INSTALL VPN SSH${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "  ${YELLOW}▸ Cleanup service lama${NC}"
( for s in ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot xray; do
    systemctl stop "$s" 2>/dev/null
    systemctl disable "$s" 2>/dev/null
    rm -f "/etc/systemd/system/${s}.service"
  done
  systemctl daemon-reload; systemctl reset-failed 2>/dev/null ) &
spin $! "Stop service lama"

( fuser -k 80/tcp 8080/tcp 443/tcp 8443/tcp 2>/dev/null
  pkill -f ws-ssh.py 2>/dev/null; pkill -f badvpn-udpgw 2>/dev/null; pkill -f vpnbot 2>/dev/null
  sleep 2 ) &
spin $! "Kill port VPN"

( rm -f /usr/local/bin/ws-ssh.py /etc/stunnel/stunnel.conf /etc/stunnel/stunnel.pem
  rm -f /usr/bin/badvpn-udpgw
  rm -f /etc/profile.d/sansxml-menu.sh
  rm -f /root/bot.py /root/vpnbot.log /root/vpnbot_*.json
  rm -f /root/.ssh/id_bot /root/.ssh/id_bot.pub
  rm -f /etc/issue /etc/issue.net /etc/motd
  rm -f /etc/ssh/sshd_config.d/99-vpnbot.conf
  rm -f /etc/sansxml-* /root/.bash_profile
  rm -rf /tmp/badvpn ) &
spin $! "Hapus file lama"

echo -e "  ${GREEN}✓${NC}  ${WHITE}User lama DIBIARKAN${NC}"

echo ""
echo -e "  ${YELLOW}▸ Install dependencies${NC}"
( apt-get update -y >/dev/null 2>&1 ) & spin $! "Update repository"
( apt-get install -y python3 python3-pip python3-venv sshpass curl wget unzip \
    stunnel4 net-tools cron ufw iptables openssl \
    cmake build-essential git pkg-config bc jq >/dev/null 2>&1 ) & spin $! "Install packages"
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

( ufw --force disable >/dev/null 2>&1
  ufw --force reset >/dev/null 2>&1
  ufw default allow incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  for p in 22 80 443 8080 8443; do ufw allow $p/tcp >/dev/null 2>&1; done
  ufw allow 7300/udp >/dev/null 2>&1
  ufw allow 1:65535/udp >/dev/null 2>&1
  ufw --force enable >/dev/null 2>&1 ) & spin $! "Configure firewall"

( systemctl daemon-reload
  systemctl enable ws-ssh ws-ssh-alt stunnel4 >/dev/null 2>&1
  systemctl restart ws-ssh ws-ssh-alt stunnel4
  [ -f /usr/bin/badvpn-udpgw ] && systemctl enable udpgw >/dev/null 2>&1 && systemctl restart udpgw
  sleep 3 ) & spin $! "Start VPN services"

echo ""
echo -e "  ${YELLOW}▸ Konfigurasi${NC}"
echo ""
read -p "$(echo -e ${GREEN}'  Bot Token Telegram : '${NC})" BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    echo -e "  ${RED}❌ Token tidak boleh kosong${NC}"
    exit 1
fi

DOMAIN="sgivip.naaofficial.web.id"
ADMIN_ID="6144358600"

echo "$BOT_TOKEN" > /etc/sansxml-bottoken
echo "$DOMAIN" > /etc/sansxml-domain
echo "$ADMIN_ID" > /etc/sansxml-adminid

cat > /root/vpnbot_config.json << CFGEOF
{
  "bot_token": "${BOT_TOKEN}",
  "domain": "${DOMAIN}",
  "owner_ids": [${ADMIN_ID}],
  "servers": {
    "sg_1ip": {
      "name": "🇸🇬 PRIME SG-01",
      "city": "Singapore",
      "isp": "DigitalOcean LLC",
      "ssh_ovpn": "DIGITALOCEAN • PRIME SG-01",
      "domain": "${DOMAIN}",
      "price_day": 117,
      "price_month": 3500,
      "ip_limit": 1,
      "slot_max": 50
    },
    "sg_2ip": {
      "name": "🇸🇬 PRIME SG-02",
      "city": "Singapore",
      "isp": "DigitalOcean LLC",
      "ssh_ovpn": "DIGITALOCEAN • PRIME SG-02",
      "domain": "${DOMAIN}",
      "price_day": 167,
      "price_month": 5010,
      "ip_limit": 2,
      "slot_max": 50
    }
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

echo ""
echo -e "  ${YELLOW}▸ Install Bot Telegram${NC}"

cat > /root/bot.py << 'BOTPYEOF'
#!/usr/bin/env python3
import re, io, json, os, logging, subprocess, asyncio, base64, random, string
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
HARI_MIN, HARI_MAX = 1, 30
TRIAL_DURATION_MIN = 30
TRIAL_PER_DAY = 2
MIN_USERNAME = 5
MIN_PASSWORD = 5
MIN_TOPUP = 2000

def get_price(hari, server_key=None):
    if server_key and server_key in SERVERS:
        srv = SERVERS[server_key]
    else:
        srv = list(SERVERS.values())[0] if SERVERS else {"price_day": 117}
    price_day = int(srv.get("price_day", 117))
    return price_day * int(hari)

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
    today = datetime.now().strftime("%Y-%m-%d"); month = datetime.now().strftime("%Y-%m")
    return {"hari":sum(t["jumlah"] for t in d if t["waktu"].startswith(today) and t["tipe"]=="buat_akun"),
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
        exp = datetime.strptime(a["exp"],"%Y-%m-%d").date()
        sisa = (exp - datetime.now().date()).days
        if sisa <= 0: return 0
        th = int(a.get("days",30))
        if th <= 0: return 0
        sk = a.get("server_key","")
        srv = SERVERS.get(sk, {})
        price_day = int(srv.get("price_day", 0))
        if price_day <= 0:
            hg = int(a.get("harga",0))
            if hg <= 0: return 0
            price_day = hg // th
        if sisa >= th: return price_day * th
        return max(0, price_day * sisa)
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

def ssh_create(username, password, days):
    exp = (datetime.now()+timedelta(days=days)).strftime("%Y-%m-%d")
    pw_b64 = base64.b64encode(password.encode()).decode()
    cmd = (f"userdel -r {username} 2>/dev/null; "
           f"useradd -m -s /bin/bash {username} 2>&1 ; "
           f"chage -E '{exp}' {username} 2>&1 ; "
           f"chage -M 99999 {username} 2>&1 ; chage -I -1 {username} 2>&1 ; "
           f"PW=$(echo '{pw_b64}' | base64 -d) ; "
           f"printf '%s:%s\\n' '{username}' \"$PW\" | chpasswd 2>&1 ; "
           f"passwd -u {username} 2>&1 ; usermod -U {username} 2>&1 ; echo DONE:$?")
    code, out, err = ssh_run(cmd)
    ok = "DONE:0" in out
    return {"ok":True,"username":username,"password":password,"exp":exp,"manual":not ok}
def ssh_extend(username, new_exp):
    cmd = f"chage -E '{new_exp}' {username} 2>&1 ; echo DONE:$?"
    code, out, err = ssh_run(cmd)
    return "DONE:0" in out
def ssh_delete(username):
    ssh_run(f"pkill -9 -u {username} 2>/dev/null; userdel -r {username} 2>&1; echo OK", timeout=20)
    return True, "OK"
def ssh_test():
    code, out, err = ssh_run("echo PING_OK", timeout=15)
    if "PING_OK" not in out: return False, f"SSH gagal: {err or out}"
    return True, "SSH OK"

def gen_pass(n=8): return ''.join(random.choices(string.ascii_lowercase+string.digits, k=n))
def valid_username(s): return bool(re.match(r'^[a-zA-Z0-9_]{5,20}$', s or ""))
def valid_password(s):
    if not s or len(s)<5 or len(s)>32: return False
    return all(c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*_.-" for c in s)

def get_vps_detail():
    try:
        ip = subprocess.run("curl -s -m 3 ifconfig.me", shell=True, capture_output=True, text=True).stdout.strip() or "-"
        cpu = subprocess.run("nproc", shell=True, capture_output=True, text=True).stdout.strip()
        os_name = subprocess.run("grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2", shell=True, capture_output=True, text=True).stdout.strip()
        kernel = subprocess.run("uname -r", shell=True, capture_output=True, text=True).stdout.strip()
        uptime = subprocess.run("uptime -p", shell=True, capture_output=True, text=True).stdout.strip().replace("up ","")
        ram = subprocess.run("free -m | awk '/Mem:/ {print $3\"/\"$2\" MB\"}'", shell=True, capture_output=True, text=True).stdout.strip()
        disk = subprocess.run("df -h / | awk 'NR==2 {print $5}'", shell=True, capture_output=True, text=True).stdout.strip()
        hostname = subprocess.run("hostname", shell=True, capture_output=True, text=True).stdout.strip()
        return {"ip":ip,"cpu":cpu,"os":os_name,"kernel":kernel,"uptime":uptime,"ram":ram,"disk":disk,"hostname":hostname}
    except: return {"ip":"-","cpu":"-","os":"-","kernel":"-","uptime":"-","ram":"-","disk":"-","hostname":"-"}

def dashboard_text(user, uid):
    uname = f"@{user.username}" if user.username else "-"
    role = "Owner" if is_owner(uid) else "Member"
    st = get_stats(uid)
    total_users = len(load_json(USERS_FILE, {}))
    lines = []
    lines.append("<blockquote>")
    lines.append("💻 <b>SANSXML VPN STORE</b>")
    lines.append("───────────────────────")
    lines.append("👤 <b>Profil</b>")
    lines.append(f"├ User Telegram  : {uname}")
    lines.append(f"├ Chat ID        : <code>{uid}</code>")
    lines.append(f"├ Keanggotaan    : {role}")
    lines.append(f"├ Total Pengguna : <b>{total_users}</b>")
    lines.append(f"╰ 💰 Saldo VPN  : <b>{rupiah(get_bal(uid))}</b>")
    lines.append("")
    lines.append("🌍 <b>Info Global</b>")
    lines.append(f"├ Minggu Ini     : <b>{st['minggu']} Akun</b>")
    lines.append(f"├ Bulan Ini      : <b>{st['bulan']} Akun</b>")
    lines.append(f"╰ Keseluruhan    : <b>{st['total']} Akun</b>")
    lines.append("")
    lines.append("🌐 <b>Informasi</b>")
    lines.append(f"├ Server Tersedia : <b>{len(SERVERS)} Server</b>")
    lines.append(f"╰ Kuota Trial     : <b>{trial_left(uid)}x Hari</b>")
    lines.append("")
    lines.append("───────────────────────")
    lines.append("</blockquote>")
    return "\n".join(lines)

def pilih_layanan_text():
    lines = []
    lines.append("<blockquote>")
    lines.append("💻 <b>PILIH LAYANAN VPN</b>")
    lines.append("───────────────────────")
    lines.append("Silakan pilih protokol yang ingin dibuat:")
    lines.append("───────────────────────")
    lines.append("</blockquote>")
    return "\n".join(lines)

def ssh_server_text():
    lines = []
    lines.append("<blockquote>")
    lines.append("<b>💻 SSH OVPN</b>")
    lines.append("─────────────────────────")
    lines.append("")
    for key, srv in SERVERS.items():
        used, mx = get_slot_info(key)
        sisa = max(0, mx - used)
        cek = "✅" if sisa > 0 else "❌"
        lines.append(f"◆ {srv['name']}")
        lines.append(f"├ Harga Harian   : <b>{rupiah(srv['price_day'])}</b>")
        lines.append(f"├ Harga Bulanan  : <b>{rupiah(srv['price_month'])}</b>")
        lines.append("├ Kuota          : Unlimited")
        lines.append(f"├ Limit IP       : {srv['ip_limit']} IP")
        lines.append(f"╰ Slot Tersedia  : <b>{used}/{mx} {cek}</b>")
        lines.append("")
        lines.append("")
    lines.append("─────────────────────────")
    lines.append("</blockquote>")
    return "\n".join(lines)

def kb_pilih_layanan():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ SSH OVPN", callback_data="pilih|ssh")],
        [InlineKeyboardButton("➕ VMESS", callback_data="pilih|vmess"),
         InlineKeyboardButton("➕ VLESS", callback_data="pilih|vless")],
        [InlineKeyboardButton("➕ TROJAN", callback_data="pilih|trojan")],
        [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]])

def kb_ssh_server():
    rows = []
    keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            srv = SERVERS[k]
            label = f"{srv['name']}"
            row.append(InlineKeyboardButton(label, callback_data=f"buat|{k}"))
        rows.append(row)
    rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="pilih_layanan")])
    return InlineKeyboardMarkup(rows)

def kb_ssh_server_extend():
    rows = []
    keys = list(SERVERS.keys())
    for i in range(0, len(keys), 2):
        row = []
        for j in range(i, min(i+2, len(keys))):
            k = keys[j]
            srv = SERVERS[k]
            label = f"{srv['name']}"
            row.append(InlineKeyboardButton(label, callback_data=f"extend|{k}"))
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
    if is_owner(uid): rows.append([InlineKeyboardButton("⚙️ Admin Panel", callback_data="admin|menu")])
    return InlineKeyboardMarkup(rows)

def saldo_text(uid, nominal=""):
    lines = []
    lines.append("<blockquote>")
    lines.append("💰 <b>Silakan masukkan jumlah nominal topup saldo yang Anda inginkan:</b>")
    lines.append("")
    lines.append(f"Jumlah saat ini: <b>{rupiah(get_bal(uid))}</b>")
    lines.append("")
    lines.append(f"Nominal input: <b>{rupiah(nominal) if nominal else 'Rp 0'}</b>")
    lines.append("")
    lines.append(f"<i>Minimal topup {rupiah(MIN_TOPUP)}</i>")
    lines.append("</blockquote>")
    return "\n".join(lines)

def kb_saldo():
    rows = [
        [InlineKeyboardButton("1", callback_data="saldo_num|1"),
         InlineKeyboardButton("2", callback_data="saldo_num|2"),
         InlineKeyboardButton("3", callback_data="saldo_num|3")],
        [InlineKeyboardButton("4", callback_data="saldo_num|4"),
         InlineKeyboardButton("5", callback_data="saldo_num|5"),
         InlineKeyboardButton("6", callback_data="saldo_num|6")],
        [InlineKeyboardButton("7", callback_data="saldo_num|7"),
         InlineKeyboardButton("8", callback_data="saldo_num|8"),
         InlineKeyboardButton("9", callback_data="saldo_num|9")],
        [InlineKeyboardButton("⬅️ Hapus", callback_data="saldo_hapus"),
         InlineKeyboardButton("0", callback_data="saldo_num|0"),
         InlineKeyboardButton("✅ Konfirmasi", callback_data="saldo_konfirmasi")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]
    ]
    return InlineKeyboardMarkup(rows)

def kb_admin():
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📊 Statistik", callback_data="admin|stats"),
         InlineKeyboardButton("💰 Income", callback_data="admin|income")],
        [InlineKeyboardButton("🖥️ Detail VPS", callback_data="admin|vps"),
         InlineKeyboardButton("🔑 List Akun", callback_data="admin|list|0")],
        [InlineKeyboardButton("📢 Broadcast", callback_data="admin|bc"),
         InlineKeyboardButton("🩺 Test SSH", callback_data="admin|testssh")],
        [InlineKeyboardButton("💾 Backup Token", callback_data="admin|backup"),
         InlineKeyboardButton("🧹 Cleanup", callback_data="admin|cleanup")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]])

def kb_acc_detail(un):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🗑️ Hapus", callback_data=f"del_acc|{un}")],
        [InlineKeyboardButton("🔙 Kembali", callback_data="my_accs")]])

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

    # PAYLOAD (WS & TLS berbeda)
    payload_ws = "GET /cdn-cgi/trace HTTP/1.1[crlf]Host: Bug_Kalian[crlf][crlf]GET-RAY / HTTP/1.1[crlf]Host: [host][crlf]Connection: Upgrade[crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf][crlf]"
    payload_tls = "GET / HTTP/1.1[crlf]Host: [host][crlf]User-Agent: [ua][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"

    lines = []
    lines.append("◤ <b>SSH OVPN ACCOUNT</b> ◢")
    lines.append(f"     ❖ <b>{head}</b> ❖")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append("<code>")
    lines.append(f"City       : {srv.get('city','Singapore')}")
    lines.append(f"ISP        : {srv.get('isp','DigitalOcean LLC')}")
    lines.append(f"SSH OVPN   : {ssh_ovpn_val}")
    lines.append(f"Username   : {u}")
    lines.append(f"Password   : {p}")
    lines.append(f"Quota      : Unlimited")
    lines.append(f"Limit IP   : {ip} IP")
    lines.append("</code>")
    lines.append("")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append("<code>")
    lines.append(f"Host     : {SSH_HOST}")
    lines.append("OpenSSH  : 443, 80, 22")
    lines.append("Dropbear : 443, 109")
    lines.append("SSH WS   : 80, 8080, 8081-9999")
    lines.append("SSH SSL  : 443")
    lines.append("SSH UDP  : 1-65535")
    lines.append("OVPN     : 443, 1194, 2200")
    lines.append("BadVPN   : 7100, 7300")
    lines.append("</code>")
    lines.append("")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append("<code>")
    lines.append(f"SSL      : {SSH_HOST}:443@{u}:{p}")
    lines.append(f"WS       : {SSH_HOST}:80@{u}:{p}")
    lines.append(f"UDP      : {SSH_HOST}:1-65535@{u}:{p}")
    lines.append("</code>")
    lines.append("")
    lines.append("<blockquote>")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append("<b>PAYLOAD WS</b>")
    lines.append(payload_ws)
    lines.append("")
    lines.append("<b>PAYLOAD TLS</b>")
    lines.append(payload_tls)
    lines.append("")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append(f"Durasi   : {dl}")
    lines.append(f"Dibuat   : {created_fmt}")
    lines.append(f"Berakhir : {exp_fmt}")
    lines.append("")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("<b>      ◤ SANSXML VPN STORE ◢</b>")
    lines.append("<i>❖ Terima kasih telah menggunakan layanan kami ❖</i>")
    lines.append("</blockquote>")
    return "\n".join(lines)

async def do_create_account(chat, uid, user, username, password, hari, is_trial=False, server_key="sg_1ip"):
    srv = SERVERS.get(server_key, {})
    ip_limit = int(srv.get("ip_limit", 2))
    price = 0 if is_trial else get_price(hari, server_key)
    if not is_trial and get_bal(uid) < price:
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]
        ])
        await chat.send_message(
            f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
            f"Silakan topup saldo melalui menu\n"
            f"Tombol <b>💰 TOPUP SALDO</b>.",
            reply_markup=kb, parse_mode="HTML")
        return
    server_num = (list(SERVERS.keys()).index(server_key) + 1) if server_key in SERVERS else 1
    if is_trial:
        load_txt = f"⚙️ Membuat <b>TRIAL AKUN</b> untuk server <b>{server_num}</b>..."
    else:
        load_txt = f"⚙️ Membuat <b>PREMIUM AKUN</b> untuk server <b>{server_num}</b>..."
    msg = await chat.send_message(load_txt, parse_mode="HTML")
    r = await asyncio.to_thread(ssh_create, username, password, hari)
    if not is_trial:
        ok, nb = reduce_bal(uid, price)
        if not ok:
            await msg.edit_text("❌ Saldo berubah. Silakan coba lagi.", parse_mode="HTML"); return
    save_acc(username, {
        "user_id":uid,"username":username,"password":password,
        "exp":r["exp"],"days":hari,"limit_ip":ip_limit,"harga":price,
        "created_at":datetime.now().isoformat(),"first_name":user.first_name or "",
        "username_tg":user.username or "","manual":r.get("manual",False),
        "free_owner":is_owner(uid),"is_trial":is_trial,"server_key":server_key,
        "server": srv.get("name","SG NEWMEDIA")
    })
    if not is_trial:
        add_trx(uid, user.first_name or "User", user.username or "", "buat_akun", price, f"{hari}h {srv.get('name','')}")
    dl_txt = f"{TRIAL_DURATION_MIN} Minute" if is_trial else f"{hari} Hari"
    await msg.edit_text(
        acc_caption(username, password, r["exp"], dl_txt, ip_limit,
                    r.get("manual",False), is_trial, server_key),
        parse_mode="HTML")

async def do_extend_account(chat, uid, user, username, hari, server_key):
    srv = SERVERS.get(server_key, {})
    price = get_price(hari, server_key)
    if get_bal(uid) < price:
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
            [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]
        ])
        await chat.send_message(
            f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
            f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
            f"💵 Harga Perpanjang : <b>{rupiah(price)}</b>\n"
            f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
            f"Silakan topup saldo melalui menu\n"
            f"Tombol <b>💰 TOPUP SALDO</b>.",
            reply_markup=kb, parse_mode="HTML")
        return
    msg = await chat.send_message(f"⚙️ Memperpanjang akun <b>{username}</b> selama <b>{hari} hari</b>...", parse_mode="HTML")
    a = get_acc(username)
    try:
        old_exp = datetime.strptime(a["exp"], "%Y-%m-%d").date()
    except: old_exp = datetime.now().date()
    today = datetime.now().date()
    base = old_exp if old_exp > today else today
    new_exp = base + timedelta(days=hari)
    new_exp_str = new_exp.strftime("%Y-%m-%d")
    ok = await asyncio.to_thread(ssh_extend, username, new_exp_str)
    if not ok:
        await msg.edit_text("❌ Gagal perpanjang akun di sistem.", parse_mode="HTML"); return
    a["exp"] = new_exp_str
    a["days"] = int(a.get("days", 0)) + hari
    a["harga"] = int(a.get("harga", 0)) + price
    save_acc(username, a)
    ok2, _ = reduce_bal(uid, price)
    if not ok2:
        await msg.edit_text("❌ Gagal potong saldo.", parse_mode="HTML"); return
    add_trx(uid, user.first_name or "User", user.username or "", "perpanjang", price, f"{hari}h {username}")
    dl_txt = f"{a.get('days',30)} Hari"
    await msg.edit_text(
        acc_caption(username, a["password"], new_exp_str, dl_txt, a.get("limit_ip",1),
                    a.get("manual",False), a.get("is_trial",False), server_key),
        parse_mode="HTML")

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

async def auto_cleanup_task():
    await asyncio.sleep(60)
    while True:
        try:
            today = datetime.now().date(); dele = 0
            for un, a in list(load_json(ACCOUNTS_FILE, {}).items()):
                if a.get("is_trial", False): continue
                if a.get("free_owner", False): continue
                try:
                    ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
                    if (today - ed).days >= 1:
                        await asyncio.to_thread(ssh_delete, un)
                        delete_acc_json(un); dele += 1
                except: pass
            if dele > 0: logger.info(f"[AUTO-CLEANUP] {dele} expired")
        except Exception as e: logger.error(f"cleanup: {e}")
        await asyncio.sleep(3600)

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

    # TOPUP
    if d == "isi_saldo":
        c.user_data["saldo_input"] = ""
        try: await q.edit_message_text(saldo_text(uid), reply_markup=kb_saldo(), parse_mode="HTML")
        except: pass
        return
    if d.startswith("saldo_num|"):
        cur = c.user_data.get("saldo_input", "")
        add = d.split("|",1)[1]
        if len(cur) >= 9:
            await q.answer("Maks 9 digit", show_alert=True); return
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
        if not cur or int(cur) <= 0:
            await q.answer("Nominal belum diisi!", show_alert=True); return
        nominal = int(cur)
        if nominal < MIN_TOPUP:
            await q.answer(f"❌ Minimal topup {rupiah(MIN_TOPUP)}", show_alert=True); return
        saldo_baru = add_bal(uid, nominal)
        add_trx(uid, u.effective_user.first_name or "", u.effective_user.username or "", "isi_saldo", nominal, "topup")
        c.user_data["saldo_input"] = ""
        try:
            await q.edit_message_text(
                f"✅ <b>Topup Saldo Berhasil</b>\n\n"
                f"<blockquote>"
                f"💰 Nominal: <b>{rupiah(nominal)}</b>\n"
                f"💼 Saldo Sekarang: <b>{rupiah(saldo_baru)}</b>"
                f"</blockquote>\n\n"
                f"<i>❖ Saldo dapat digunakan untuk membuat akun VPN ❖</i>",
                reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]]),
                parse_mode="HTML")
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
        p = d.split("|")[1]
        mode = c.user_data.get("mode", "buat")
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
            await chat.send_message(
                f"<blockquote>❌ <b>Slot Penuh</b>\n\n"
                f"Server <b>{SERVERS[server_key]['name']}</b>\n"
                f"Slot tersedia: <b>{used}/{mx}</b>\n\n"
                f"Silakan pilih server lain.</blockquote>",
                parse_mode="HTML"); return
        mode = c.user_data.get("mode", "buat")
        if mode == "trial":
            if trial_left(uid) <= 0:
                await chat.send_message(
                    "🚫 <b>Batas trial hari ini telah tercapai.</b>\n"
                    "Silakan coba lagi besok.",
                    parse_mode="HTML"); return
            use_trial(uid)
            uniq = ''.join(random.choices(string.ascii_lowercase + string.digits, k=4))
            username = f"trial-{uniq}"
            password = f"trial{uniq}"
            c.user_data.clear()
            await do_create_account(chat, uid, u.effective_user, username, password, 1, is_trial=True, server_key=server_key)
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
                ed = datetime.strptime(a["exp"],"%Y-%m-%d").date()
                if (ed - datetime.now().date()).days < 0: continue
            except: pass
            accs.append(a)
        hdr = []
        hdr.append("<blockquote>")
        hdr.append("💻 <b>AKUN SAYA</b>")
        hdr.append("───────────────────────")
        hdr.append("")
        hdr.append(f"📭 Total Akun : <b>{len(accs)}</b>")
        hdr.append("")
        if not accs:
            hdr.append("Belum ada akun premium.")
            hdr.append("Silakan buat akun terlebih dahulu.")
            hdr.append("")
        hdr.append("───────────────────────")
        hdr.append("</blockquote>")
        if not accs:
            rows = [
                [InlineKeyboardButton("➕ BUAT AKUN", callback_data="buat_akun")],
                [InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")]
            ]
        else:
            rows = [[InlineKeyboardButton(f"👤 {a['username']}", callback_data=f"acc_detail|{a['username']}")] for a in accs[:20]]
            rows.append([InlineKeyboardButton("🔙 KEMBALI", callback_data="menu|main")])
        try:
            await q.edit_message_text("\n".join(hdr), reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return

    if d.startswith("acc_detail|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        dl_txt = f"{TRIAL_DURATION_MIN} Minute" if a.get("is_trial") else f"{a.get('days',30)} Hari"
        ref = hitung_refund(a) if not a.get("free_owner") else 0
        cap = acc_caption(un, a['password'], a['exp'], dl_txt, a.get('limit_ip',IP_LIMIT), a.get('manual',False), a.get('is_trial',False), a.get('server_key','sg_1ip'))
        try:
            ed = datetime.strptime(a["exp"], "%Y-%m-%d").date(); sh = max(0,(ed-datetime.now().date()).days); th = int(a.get("days",30))
        except: sh = 0; th = 30
        if ref > 0: cap += f"\n\n💰 <b>Refund: {rupiah(ref)}</b>\n<i>({sh}/{th} hari)</i>"
        else: cap += f"\n\n💰 <i>Refund: Rp 0</i>"
        try: await q.edit_message_text(cap, reply_markup=kb_acc_detail(un), parse_mode="HTML")
        except: pass
        return
    if d.startswith("del_acc|"):
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a or a.get("user_id") != uid: await q.answer("No", show_alert=True); return
        ref = hitung_refund(a) if not a.get("free_owner") else 0
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

    # ADMIN
    if d == "admin|menu":
        if not is_owner(uid): return
        try: await q.edit_message_text(f"⚙️ <b>ADMIN PANEL</b>\n\n👥 User: <b>{len(load_json(USERS_FILE,{}))}</b>\n🔑 Akun: <b>{count_accounts()}</b>\n💰 Saldo: <b>{rupiah(sum(load_json(BAL_FILE,{}).values()))}</b>", reply_markup=kb_admin(), parse_mode="HTML")
        except: pass
        return
    if d == "admin|stats":
        if not is_owner(uid): return
        st = get_stats()
        try: await q.edit_message_text(f"📊 <b>STATISTIK</b>\n\nHari: <b>{st['hari']}</b>\nMinggu: <b>{st['minggu']}</b>\nBulan: <b>{st['bulan']}</b>\nTotal: <b>{st['total']}</b>", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|income":
        if not is_owner(uid): return
        inc = get_income()
        try: await q.edit_message_text(f"💰 <b>PENGHASILAN</b>\n\nHari: <b>{rupiah(inc['hari'])}</b>\nBulan: <b>{rupiah(inc['bulan'])}</b>\nTotal: <b>{rupiah(inc['total'])}</b>", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|vps":
        if not is_owner(uid): return
        v = await asyncio.to_thread(get_vps_detail)
        try: await q.edit_message_text(
            f"🖥️ <b>DETAIL VPS</b>\n\n<blockquote>"
            f"├ Hostname : <code>{v['hostname']}</code>\n"
            f"├ IP       : <code>{v['ip']}</code>\n"
            f"├ OS       : <b>{v['os']}</b>\n"
            f"├ Kernel   : <code>{v['kernel']}</code>\n"
            f"├ CPU      : <b>{v['cpu']} vCPU</b>\n"
            f"├ RAM      : <b>{v['ram']}</b>\n"
            f"├ Disk     : <b>{v['disk']}</b>\n"
            f"╰ Uptime   : <b>{v['uptime']}</b></blockquote>",
            reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|testssh":
        if not is_owner(uid): return
        try: await q.edit_message_text("🩺 Tes...")
        except: pass
        ok, msg = await asyncio.to_thread(ssh_test)
        try: await q.edit_message_text(msg, reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d == "admin|backup":
        if not is_owner(uid): return
        try:
            import io as _io
            cfg = load_config()
            data = json.dumps(cfg, indent=2, ensure_ascii=False)
            bio = _io.BytesIO(data.encode())
            bio.name = "sansxml_config_backup.json"
            await chat.send_document(document=bio, caption="💾 <b>Backup Config Bot</b>\n\nSimpan file ini di tempat aman.", parse_mode="HTML")
        except Exception as e:
            try: await chat.send_message(f"❌ Gagal: {e}", parse_mode="HTML")
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
                    await asyncio.to_thread(ssh_delete, un); delete_acc_json(un); dele += 1
            except: pass
        try: await q.edit_message_text(f"🧹 Dihapus: <b>{dele}</b>", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")]]), parse_mode="HTML")
        except: pass
        return
    if d.startswith("admin|list|"):
        if not is_owner(uid): return
        page = int(d.split("|")[2])
        accs = list(load_json(ACCOUNTS_FILE,{}).items())
        accs.sort(key=lambda x: x[1].get("created_at",""), reverse=True)
        PER = 10; total = len(accs); tp = max(1,(total+PER-1)//PER); page = max(0,min(page,tp-1))
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
        rows.append([InlineKeyboardButton("🔙 Kembali", callback_data="admin|menu")])
        try: await q.edit_message_text(f"🔑 <b>DAFTAR AKUN</b> ({total})", reply_markup=InlineKeyboardMarkup(rows), parse_mode="HTML")
        except: pass
        return
    if d.startswith("adm_acc|"):
        if not is_owner(uid): return
        un = d.split("|",1)[1]; a = get_acc(un)
        if not a: await q.answer("No", show_alert=True); return
        try: await q.edit_message_text(f"🔑 <b>AKUN</b>\n\n<code>{un}</code>\n🔒 <code>{a['password']}</code>\n📅 Exp: {a['exp']}", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🗑️ Hapus", callback_data=f"adm_del|{un}")],[InlineKeyboardButton("🔙 Kembali", callback_data="admin|list|0")]]), parse_mode="HTML")
        except: pass
        return
    if d.startswith("adm_del|"):
        if not is_owner(uid): return
        un = d.split("|",1)[1]
        await asyncio.to_thread(ssh_delete, un); delete_acc_json(un)
        try: await q.edit_message_text(f"🗑️ <code>{un}</code> dihapus", reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("🔙 Kembali", callback_data="admin|list|0")]]), parse_mode="HTML")
        except: pass
        return

async def msg(u, c):
    uid = u.effective_user.id
    track_user(u.effective_user)
    t = (u.message.text or "").strip()

    step = c.user_data.get("buat_step")
    if step:
        data = c.user_data.get("buat_data",{})
        if step == "username":
            if not valid_username(t):
                await u.message.reply_text("❌ Username minimal 5 huruf\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            if is_username_taken(t):
                await u.message.reply_text(f"❌ {t} sudah ada.\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            data["username"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return
        if step == "password":
            if not valid_password(t):
                await u.message.reply_text("❌ Password minimal 5 huruf\n\n🔑 Masukkan password akun :", parse_mode="HTML"); return
            data["password"] = t; c.user_data["buat_data"] = data; c.user_data["buat_step"] = "durasi"
            await u.message.reply_text("📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
        if step == "durasi":
            try: hari = int(re.sub(r'[^0-9]','',t))
            except: await u.message.reply_text("❌ Masa aktif tidak valid contoh ketik : 3\n\n📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text("❌ Masa aktif tidak valid contoh ketik : 3\n\n📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            un = data.get("username"); pw = data.get("password")
            server_key = data.get("server_key", "sg_1ip")
            price = get_price(hari, server_key)
            c.user_data["buat_step"] = None; c.user_data["buat_data"] = {}
            if get_bal(uid) < price:
                kb = InlineKeyboardMarkup([
                    [InlineKeyboardButton("💰 TOPUP SALDO", callback_data="isi_saldo")],
                    [InlineKeyboardButton("🔙 Kembali", callback_data="menu|main")]
                ])
                await u.message.reply_text(
                    f"<blockquote>❌ <b>Saldo Tidak Cukup</b>\n\n"
                    f"💰 Saldo Anda : <b>{rupiah(get_bal(uid))}</b>\n"
                    f"💵 Harga Akun : <b>{rupiah(price)}</b>\n"
                    f"📉 Kurang     : <b>{rupiah(price - get_bal(uid))}</b></blockquote>\n\n"
                    f"Silakan topup saldo melalui menu\n"
                    f"Tombol <b>💰 TOPUP SALDO</b>.",
                    reply_markup=kb, parse_mode="HTML"); return
            await do_create_account(u.effective_chat, uid, u.effective_user, un, pw, hari, server_key=server_key)
            return

    estep = c.user_data.get("extend_step")
    if estep:
        data = c.user_data.get("extend_data", {})
        server_key = data.get("server_key", "sg_1ip")

        if estep == "username":
            if not is_username_taken(t):
                await u.message.reply_text("❌ Akun tidak ditemukan.\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            a = get_acc(t)
            if not a or a.get("user_id") != uid:
                await u.message.reply_text("❌ Akun tidak ditemukan atau bukan milik Anda.\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            if a.get("is_trial"):
                await u.message.reply_text("❌ Akun trial tidak bisa diperpanjang.\n\n👤 Masukkan username akun :", parse_mode="HTML"); return
            data["username"] = t
            c.user_data["extend_data"] = data
            c.user_data["extend_step"] = "password"
            await u.message.reply_text("🔑 Masukkan password akun :", parse_mode="HTML"); return

        if estep == "password":
            a = get_acc(data.get("username"))
            if not a or a.get("password") != t:
                await u.message.reply_text("❌ Password salah.\n\n🔑 Masukkan password akun :", parse_mode="HTML"); return
            c.user_data["extend_step"] = "durasi"
            try:
                ed = datetime.strptime(a["exp"], "%Y-%m-%d").date()
                sh = max(0, (ed - datetime.now().date()).days)
                sisa_txt = f"\n<i>Sisa masa aktif: {sh} hari</i>"
            except: sisa_txt = ""
            await u.message.reply_text(
                f"📆 <b>Masukkan masa aktif tambahan 1-30 (hari) :</b>{sisa_txt}",
                parse_mode="HTML"); return

        if estep == "durasi":
            try: hari = int(re.sub(r'[^0-9]','',t))
            except: await u.message.reply_text("❌ Masa aktif tidak valid contoh ketik : 3\n\n📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            if not (HARI_MIN <= hari <= HARI_MAX):
                await u.message.reply_text("❌ Masa aktif tidak valid contoh ketik : 3\n\n📆 Masukkan masa aktif 1-30 (hari) :", parse_mode="HTML"); return
            un = data.get("username")
            c.user_data["extend_step"] = None; c.user_data["extend_data"] = {}
            await do_extend_account(u.effective_chat, uid, u.effective_user, un, hari, server_key)
            return

async def handle_photo(u, c):
    await u.message.reply_text("Gunakan /start", reply_markup=ReplyKeyboardRemove())

async def post_init(app):
    try:
        await app.bot.set_my_commands([BotCommand("start", "⌂ Menu")])
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
echo ""
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}   ✓✓✓ INSTALASI SELESAI ✓✓✓${NC}"
echo -e "  ${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
for s in ssh ws-ssh ws-ssh-alt stunnel4 udpgw vpnbot; do
    ST=$(systemctl is-active "$s" 2>/dev/null || echo "n/a")
    printf "  %-14s : " "$s"
    [ "$ST" = "active" ] && echo -e "${GREEN}$ST${NC}" || echo -e "${RED}$ST${NC}"
done
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