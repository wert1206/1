#!/bin/sh
# 查看 / 修改本机当前运行的所有配置信息
# 用法:
#   sh status.sh        只看
#   sh status.sh edit   看完后进入修改（端口 / 密码 / UUID / ClientKey）

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if ! command -v python3 >/dev/null 2>&1; then
	echo "需要 python3 才能完整显示配置，先用 apt-get install -y python3 装一下。" >&2
	exit 1
fi

PYFILE=$(mktemp /tmp/parso-status.XXXXXX.py) || {
	echo "无法创建临时文件" >&2
	exit 1
}
trap 'rm -f "$PYFILE"' 0 1 2 15

cat >"$PYFILE" <<'PY'
import json, os, re, shutil, subprocess, datetime, socket, time, sys

C0 = "\033[0m"
CY = "\033[36m"
CB = "\033[1m"
CG = "\033[32m"
CR = "\033[31m"
CYEL = "\033[33m"

EDIT = os.environ.get("PARSO_EDIT") == "1"
VERSION = "v12 · 支持 edit（运行状态 / 操作日志 / 备份留 5 份 / 异常退出清理临时文件）"

def run(cmd):
	try:
		p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=20)
		return (p.stdout or "").strip()
	except Exception:
		return ""

def title(t):
	print("\n\033[44;37m %s \033[0m" % t)

def kv(k, v, w=12):
	print("   %s%-*s%s %s" % (CY, w, k, C0, v))

def fail(msg):
	print("   %s%s%s" % (CR, msg, C0))

def ok(msg):
	print("   %s%s%s" % (CG, msg, C0))

def warn(msg):
	print("   %s%s%s" % (CYEL, msg, C0))

def ask(prompt):
	try:
		return input(prompt).strip()
	except (EOFError, KeyboardInterrupt):
		print("")
		return ""

def valid_port(s):
	return s.isdigit() and 1 <= int(s) <= 65535

def port_busy(p):
	return bool(run("ss -lntp 2>/dev/null | grep -E ':%s([^0-9]|$)'" % p))

def backup_file(path):
	b = "%s.bak-%s" % (path, datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
	try:
		shutil.copy2(path, b)
	except Exception:
		return ""
	try:
		d = os.path.dirname(path) or "."
		prefix = os.path.basename(path) + ".bak-"
		olds = sorted(n for n in os.listdir(d) if n.startswith(prefix))
		for n in olds[:-5]:
			os.remove(os.path.join(d, n))
	except Exception:
		pass
	return b

LOG_PATH = os.environ.get("PARSO_LOG") or "/var/log/xray-panel.log"

def log_action(item, detail):
	try:
		user = os.environ.get("SUDO_USER") or os.environ.get("USER") or "root"
		line = "%s [%s] %s: %s\n" % (datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), user, item, detail)
		d = os.path.dirname(LOG_PATH)
		if d and not os.path.isdir(d):
			os.makedirs(d, exist_ok=True)
		if os.path.isfile(LOG_PATH) and os.path.getsize(LOG_PATH) > 1024 * 1024:
			os.replace(LOG_PATH, LOG_PATH + ".1")
		with open(LOG_PATH, "a") as f:
			f.write(line)
	except Exception:
		pass

def snap(kind):
	try:
		if kind == "xray":
			d = json.load(open(xray_json))
			ibs = d.get("inbounds") or []
			ports = ",".join("%s:%s" % (ib.get("protocol", "?"), ib.get("port", "?")) for ib in ibs) or "-"
			uid = "-"
			for ib in ibs:
				cl = ((ib.get("settings") or {}).get("clients") or [])
				if cl and cl[0].get("id"):
					uid = cl[0]["id"][:8]
					break
			return "%s / UUID %s" % (ports, uid)
		if kind == "cns":
			d = json.load(open(cns_json))
			return "%s / TLS %s / 密码%s / key %s" % (
				d.get("Listen_addr"), (d.get("Tls") or {}).get("Listen_addr") or "关",
				"有" if d.get("Encrypt_password") else "空", d.get("Proxy_key") or "-")
		if kind == "amy4":
			d = json.load(open(amy_json))
			a = d["AmyIns"][0]["ANetSettings"]
			return "%s / key %s / IPv6 %s" % (a.get("ListenAddr"), "有" if a.get("ClientKeys") else "空", a.get("IPv6Support"))
		if kind == "tinyproxy":
			pth = tinyproxy_conf_path()
			if pth:
				port, auth = "?", "无"
				for line in open(pth):
					t = line.strip()
					if t.lower().startswith("port "):
						port = t.split()[1]
					if t.lower().startswith("basicauth "):
						auth = "有"
				return ":%s / 认证%s" % (port, auth)
	except Exception:
		pass
	return "-"

def write_json(path, obj):
	tmp = path + ".new"
	with open(tmp, "w") as f:
		json.dump(obj, f, ensure_ascii=False, indent=2)
	os.replace(tmp, path)

def restart_check(name, ports, bak="", path=""):
	run("systemctl restart %s 2>&1" % name)
	time.sleep(2)
	st = run("systemctl is-active %s" % name)
	missing = [p for p in ports if not port_busy(p)]
	if st != "active" or missing:
		fail("重启后状态 %s%s" % (st, ("，端口没在监听: " + ", ".join(":" + p for p in missing)) if missing else ""))
		log = run("journalctl -u %s -n 10 --no-pager 2>/dev/null | tail -10" % name)
		if log:
			print(log)
		if bak and path and os.path.isfile(bak):
			try:
				shutil.copy2(bak, path)
				run("systemctl restart %s 2>/dev/null" % name)
				time.sleep(2)
				warn("已自动回滚到原配置（%s），%s 现在是 %s" % (bak, name, run("systemctl is-active %s" % name)))
			except Exception as e:
				fail("自动回滚失败: %s，请手动 cp %s %s" % (e, bak, path))
		return False
	ok("%s 已重启，%s 正常监听" % (name, ", ".join(":" + p for p in ports)))
	return True

# ---------- 基础信息 ----------
host = socket.gethostname()
def pick_ip():
	env_ip = os.environ.get("PUBLIC_IP", "").strip()
	if re.match(r"^\d+\.\d+\.\d+\.\d+$", env_ip):
		return env_ip, True
	# 服务器常在 NAT 后面（本机只有 172.x），所以先问外网探针要公网 IP
	for url in ("https://ifconfig.me/ip", "https://ipinfo.io/ip", "https://api.ipify.org", "https://4.ipw.cn"):
		out = run("curl -s -m 4 %s" % url)
		m = re.search(r"\d+\.\d+\.\d+\.\d+", out or "")
		if m:
			return m.group(0), True
	cands = []
	o1 = run("ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i==\"src\"){print $(i+1);exit}}'")
	if o1:
		cands.append(o1)
	cands += run("hostname -I 2>/dev/null").split()
	for c in cands:
		if c and not c.startswith(("127.", "169.254.")):
			return c, False
	return (cands[0] if cands else ""), False

ip, ip_public = pick_ip()
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

print("\033[45;37m 当前运行配置 \033[0m")
kv("主机名", host)
kv("公网地址", (ip or "未知") + ("" if ip_public else "（本机地址，未探测到公网 IP）"))
kv("查看时间", now)
kv("脚本版本", VERSION)

# ---------- 端口 / 进程 ----------
ss_out = run("ss -lntp")
pid_ports = {}
name_pids = {}
for line in ss_out.splitlines():
	if not line.startswith("LISTEN"):
		continue
	cols = line.split()
	if len(cols) < 4:
		continue
	addr = cols[3]
	port = addr.rsplit(":", 1)[-1] if ":" in addr else ""
	for m in re.finditer(r'\("([^"]+)",pid=(\d+)', line):
		pname, pid = m.group(1), int(m.group(2))
		name_pids.setdefault(pname, set()).add(pid)
		pid_ports.setdefault(pid, set()).add(port)

# ---------- 服务状态 ----------
SERVICES = [
	("xray", "/usr/local/xray"),
	("cns", "/usr/local/cns"),
	("amy4", "/usr/local/amy4"),
	("tinyproxy", "/usr/local/tinyproxy"),
]

def tinyproxy_conf_path():
	for p in ("/usr/local/tinyproxy/tinyproxy.conf", "/etc/tinyproxy/tinyproxy.conf"):
		if os.path.isfile(p):
			return p
	return ""

def svc_present(name, d):
	if name == "tinyproxy":
		return bool(tinyproxy_conf_path()) or bool(run("command -v tinyproxy"))
	return os.path.isdir(d)

title("服务状态")
print("   %s%-10s %-10s %-10s %-22s %s%s" % (CB, "项目", "状态", "开机自启", "监听端口", "PID", C0))
installed = []
for name, d in SERVICES:
	if not svc_present(name, d):
		print("   %-10s %s未安装%s" % (name, "\033[90m", C0))
		continue
	installed.append(name)
	st = run("systemctl is-active %s" % name) or "unknown"
	en = run("systemctl is-enabled %s 2>/dev/null" % name) or "-"
	main_pid = run("systemctl show -p MainPID --value %s 2>/dev/null" % name)
	pids = set()
	if main_pid and main_pid.isdigit() and int(main_pid) > 0:
		pids.add(int(main_pid))
	# 同名的监听进程（cns 之类会 fork 子进程监听）也算进来
	for p in name_pids.get(name, set()):
		pids.add(p)
	ports = sorted({x for p in pids for x in pid_ports.get(p, set()) if x}, key=lambda x: int(x))
	port_txt = ",".join(":" + p for p in ports) if ports else "-"
	pid_txt = ",".join(str(p) for p in sorted(pids)) if pids else "-"
	color = CG if st == "active" else CR
	print("   %-10s %s%-10s%s %-10s %-22s %s" % (name, color, st, C0, en, port_txt, pid_txt))

# ---------- xray ----------
def b64(s):
	import base64
	return base64.b64encode(s.encode()).decode()

def link_vmess(ip, port, uid, net, path, tls, typ, ps, fp=None):
	obj = '{"add": "%s", "port": %s, "aid": "0", "host": "%s", "id": "%s", "net": "%s", "path": "%s", "ps": "%s", "tls": "%s", "type": "%s", "v": "2"%s}' % (
		ip, port, "obfs.domain" if net in ("ws", "tcp") else "", uid, net, path,
		"%s_%s:%s" % (ps, ip, port), tls, typ, (', "fp": "%s"' % fp if fp else ""))
	return "vmess://" + b64(obj)

def inbound_info(ib, ip):
	proto = ib.get("protocol", "")
	port = str(ib.get("port", ""))
	sett = ib.get("settings", {}) or {}
	stream = ib.get("streamSettings", {}) or {}
	net = stream.get("network", "tcp")
	sec = stream.get("security", "none")
	hdr = ((stream.get("tcpSettings") or {}).get("header") or {}).get("type", "none")
	clients = sett.get("clients") or []
	uid = ""
	flow = ""
	if clients:
		uid = clients[0].get("id") or clients[0].get("password") or ""
		flow = clients[0].get("flow", "") or ""
	ws = stream.get("wsSettings") or {}
	path = ws.get("path") or "/"
	reality = stream.get("realitySettings") or {}
	tls_settings = stream.get("tlsSettings") or {}

	label = proto
	link = ""
	if proto == "vmess":
		if net == "tcp" and sec == "none":
			label = "vmess tcp http"
			link = link_vmess(ip, port, uid, "tcp", "/", "", "http", "vmess_tcp_http")
		elif net == "tcp" and sec == "tls":
			label = "vmess tcp tls"
			link = link_vmess(ip, port, uid, "tcp", "", "tls", "none", "vmess_tcp_tls", "chrome")
		elif net == "ws" and sec == "none":
			label = "vmess ws"
			link = link_vmess(ip, port, uid, "ws", path, "", "none", "vmess_ws")
		elif net == "ws" and sec == "tls":
			label = "vmess ws tls"
			link = link_vmess(ip, port, uid, "ws", path, "tls", "none", "vmess_ws_tls", "chrome")
		elif net == "kcp" and sec == "none":
			label = "vmess mkcp"
			link = link_vmess(ip, port, uid, "kcp", "", "", "utp", "vmess_mkcp")
		elif net == "kcp" and sec == "tls":
			label = "vmess mkcp tls"
			link = link_vmess(ip, port, uid, "kcp", "", "tls", "none", "vmess_mkcp_tls", "chrome")
	else:
		label = "%s %s%s" % (proto, net, " tls" if sec == "tls" else (" reality" if sec == "reality" else ""))
		if proto == "vless" and sec == "reality":
			sni = (reality.get("serverNames") or ["obfs.domain"])[0]
			pbk = reality.get("publicKey", "") or reality.get("settings", {}).get("publicKey", "")
			sid = (reality.get("shortIds") or [""])[0]
			link = "vless://%s@%s:%s?security=reality&sni=%s&encryption=none&headerType=none&type=tcp&fp=chrome&flow=%s&sid=%s&pbk=%s&spx=/iphone-14-pro#vless_tcp_reality%s:%s" % (
				uid, ip, port, sni, flow or "xtls-rprx-vision", sid, pbk, ip, port)
		elif proto == "vless" and net == "ws" and sec == "tls":
			sni = ((tls_settings.get("serverName")) or "obfs.domain")
			link = "vless://%s@%s:%s?security=tls&sni=%s&encryption=none&type=ws&path=%s&host=%s&fp=chrome#vless_ws_tls%s:%s" % (
				uid, ip, port, sni, path, sni, ip, port)
		elif proto == "trojan":
			label = "trojan tls"
			sni = ((tls_settings.get("serverName")) or "obfs.domain")
			link = "trojan://%s@%s:%s?security=tls&sni=%s#trojan_tls_%s:%s" % (uid, ip, port, sni, ip, port)
	return label, port, uid, link

title("xray")
xray_json = "/usr/local/xray/xray.json"
xray_data = {}
if not os.path.isdir("/usr/local/xray"):
	print("   %s未安装%s" % ("\033[90m", C0))
elif not os.path.isfile(xray_json):
	fail("目录存在但没找到 %s" % xray_json)
else:
	try:
		xray_data = json.load(open(xray_json))
	except Exception as e:
		fail("配置解析失败: %s" % e)
		xray_data = {}
	ib_list = xray_data.get("inbounds") or []
	kv("安装目录", "/usr/local/xray")
	kv("配置文件", xray_json)
	kv("入站数量", "%d 个" % len(ib_list))
	if ib_list:
		first_uid = ""
		for ib in ib_list:
			label, port, uid, link = inbound_info(ib, ip)
			if uid and not first_uid:
				first_uid = uid
		kv("UUID", first_uid or "-")
		for i, ib in enumerate(ib_list, 1):
			label, port, uid, link = inbound_info(ib, ip)
			print("\n   %s[%d] %s%s  :%s" % (CY, i, label, C0, port))
			if label.startswith(("vmess", "vless")):
				kv("UUID", uid, 8)
			elif label.startswith("trojan"):
				kv("密码", uid, 8)
			if link:
				kv("链接", link, 8)
		print("")
		outbounds = xray_data.get("outbounds") or []
		if outbounds:
			kv("出站", ",".join(o.get("protocol", "") for o in outbounds))

# ---------- cns ----------
title("cns")
cns_dir = "/usr/local/cns"
cns_json = os.path.join(cns_dir, "cns.json")
cns_data = {}
if not os.path.isdir(cns_dir):
	print("   %s未安装%s" % ("\033[90m", C0))
else:
	kv("安装目录", cns_dir)
	if not os.path.isfile(cns_json):
		fail("目录存在但没找到 %s" % cns_json)
	else:
		try:
			cns_data = json.load(open(cns_json))
		except Exception as e:
			fail("配置解析失败: %s" % e)
			cns_data = {}
		kv("配置文件", cns_json)
		listen = cns_data.get("Listen_addr") or []
		kv("监听端口", ",".join(str(x) for x in listen) or "-")
		tls = cns_data.get("Tls") or {}
		if tls:
			kv("TLS 监听", ",".join(str(x) for x in (tls.get("Listen_addr") or [])) or "-")
		pw = cns_data.get("Encrypt_password") or ""
		kv("加密密码", pw if pw else "（空，不加密）")
		kv("Proxy_key", str(cns_data.get("Proxy_key", "Meng")))
		kv("Udp_flag", str(cns_data.get("Udp_flag", "httpUDP")))
		kv("UDP/TCP 超时", "%s / %s 秒" % (cns_data.get("Udp_timeout", "-"), cns_data.get("Tcp_timeout", "-")))

# ---------- amy4 ----------
title("amy4")
amy_dir = "/usr/local/amy4"
amy_json = os.path.join(amy_dir, "amy4.json")
amy_data = {}
if not os.path.isdir(amy_dir):
	print("   %s未安装%s" % ("\033[90m", C0))
else:
	kv("安装目录", amy_dir)
	if not os.path.isfile(amy_json):
		fail("目录存在但没找到 %s" % amy_json)
	else:
		try:
			amy_data = json.load(open(amy_json))
		except Exception as e:
			fail("配置解析失败: %s" % e)
			amy_data = {}
		kv("配置文件", amy_json)
		for ins in (amy_data.get("AmyIns") or []):
			s = ins.get("ANetSettings") or {}
			kv("服务端口", str(s.get("ListenAddr", "-")))
			keys = s.get("ClientKeys") or []
			key_txt = ", ".join(k for k in keys if k)
			kv("ClientKey", key_txt if key_txt else "（空，不校验）")
			v6 = s.get("IPv6Support", "-")
			kv("IPv6 支持", "true" if v6 is True else ("false" if v6 is False else str(v6)))

# ---------- tinyproxy ----------
title("tinyproxy")
tp_conf = tinyproxy_conf_path()
if not tp_conf:
	print("   %s未安装（本仓库不含该二进制，可用 apt install tinyproxy 装）%s" % ("\033[90m", C0))
else:
	kv("配置文件", tp_conf)
	txt = open(tp_conf, errors="ignore").read()
	port = re.search(r"^\s*Port\s+(\d+)", txt, re.M)
	kv("监听端口", port.group(1) if port else "-")
	auths = [m.group(1).strip() for m in re.finditer(r"^\s*BasicAuth\s+(.+)$", txt, re.M)]
	user = re.search(r"^\s*BasicAuthUser\s+(.+)$", txt, re.M)
	pw = re.search(r"^\s*BasicAuthPassword\s+(.+)$", txt, re.M)
	if auths:
		kv("认证", ", ".join(auths))
	elif user:
		kv("认证", "%s : %s" % (user.group(1).strip(), pw.group(1).strip() if pw else ""))
	else:
		kv("认证", "（无 BasicAuth）")
	for m in re.finditer(r"^\s*Allow\s+(.+)$", txt, re.M):
		kv("Allow", m.group(1).strip())

# ---------- 汇总 ----------
title("汇总")
kv("已安装", ", ".join(installed) if installed else "无")
kv("开机自启", ", ".join(x for x in installed if run("systemctl is-enabled %s 2>/dev/null" % x) == "enabled") or "无")
for name, d in SERVICES:
	if svc_present(name, d):
		sz = run("du -sh %s 2>/dev/null | awk '{print $1}'" % d)
		kv("占用 %s" % name, sz or "-")

if not EDIT:
	print("")
	print("   改端口 / 密码 / UUID / ClientKey：\033[36msh status.sh edit\033[0m")
	print("")
	sys.exit(0)

# ================= 修改配置 =================
XRAY_OPTS = [
	(1, "tcp http (vmess)"), (2, "tcp tls (vmess)"), (3, "tcp reality (vless)"),
	(4, "websocket (vmess)"), (5, "websocket tls (vmess)"), (6, "websocket tls (vless)"),
	(7, "mkcp (vmess)"), (8, "mkcp tls (vmess)"), (9, "mkcp tls (vless)"), (10, "trojan tls"),
]

def xray_opt_of(ib):
	proto = ib.get("protocol")
	stream = ib.get("streamSettings") or {}
	net = stream.get("network", "tcp")
	sec = stream.get("security", "none")
	if proto == "trojan":
		return 10
	if proto == "vless":
		if net == "tcp" and sec == "reality":
			return 3
		if net == "ws" and sec == "tls":
			return 6
		if net == "kcp" and sec == "tls":
			return 9
		return 0
	if proto == "vmess":
		if net == "tcp" and sec == "none":
			return 1
		if net == "tcp" and sec == "tls":
			return 2
		if net == "ws" and sec == "none":
			return 4
		if net == "ws" and sec == "tls":
			return 5
		if net == "kcp" and sec == "none":
			return 7
		if net == "kcp" and sec == "tls":
			return 8
	return 0

def xray_tls_obj():
	out = run("/usr/local/xray/xray tls cert 2>/dev/null")
	try:
		cert = json.loads(out)
	except Exception:
		cert = None
	if cert:
		return {"security": "tls", "tlsSettings": {"certificates": [cert]}}
	return {"security": "tls", "tlsSettings": {}}

def xray_reality_obj(uuid):
	out = run("/usr/local/xray/xray x25519 2>/dev/null")
	pvk = re.search(r"Private key:\s*(\S+)", out)
	if not pvk:
		return None
	return {"security": "reality", "realitySettings": {
		"show": False, "dest": "www.apple.com:443", "xver": 0,
		"serverNames": ["www.apple.com", "images.apple.com"],
		"privateKey": pvk.group(1), "shortIds": [uuid.split("-")[-1]],
	}}

def xray_build_inbound(opt, port, uuid, path="/"):
	port_s = str(port)
	tfo = os.path.isfile("/proc/sys/net/ipv4/tcp_fastopen")
	def vmess_clients(flow=None):
		c = {"id": uuid, "level": 0, "alterId": 0}
		if flow:
			c["flow"] = flow
		return [c]
	vm = {"udp": True, "clients": vmess_clients(), "decryption": "none"}
	vl = {"udp": True, "clients": vmess_clients("xtls-rprx-vision"), "decryption": "none"}
	if opt == 1:
		return {"port": port_s, "protocol": "vmess", "settings": vm,
			"streamSettings": {"sockopt": {"tcpFastOpen": tfo}, "network": "tcp", "tcpSettings": {"header": {"type": "http"}}}}
	if opt == 2:
		st = {"sockopt": {"tcpFastOpen": tfo}, "network": "tcp"}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "vmess", "settings": vm, "streamSettings": st}
	if opt == 3:
		ro = xray_reality_obj(uuid)
		if not ro:
			return None
		st = {"sockopt": {"tcpFastOpen": tfo}, "network": "tcp"}
		st.update(ro)
		return {"port": port_s, "protocol": "vless", "settings": vl, "streamSettings": st}
	if opt == 4:
		return {"port": port_s, "protocol": "vmess", "settings": vm,
			"streamSettings": {"sockopt": {"tcpFastOpen": tfo}, "network": "ws", "wsSettings": {"path": path}}}
	if opt == 5:
		st = {"sockopt": {"tcpFastOpen": tfo}, "network": "ws", "wsSettings": {"path": path}}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "vmess", "settings": vm, "streamSettings": st}
	if opt == 6:
		st = {"sockopt": {"tcpFastOpen": tfo}, "network": "ws", "wsSettings": {"path": path}}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "vless", "settings": {"udp": True, "clients": vmess_clients(), "decryption": "none"}, "streamSettings": st}
	if opt == 7:
		return {"port": port_s, "protocol": "vmess", "settings": vm,
			"streamSettings": {"network": "kcp", "kcpSettings": {"header": {"type": "utp"}}}}
	if opt == 8:
		st = {"network": "kcp", "kcpSettings": {"header": {"type": "none"}}}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "vmess", "settings": vm, "streamSettings": st}
	if opt == 9:
		st = {"network": "kcp", "kcpSettings": {"header": {"type": "none"}}}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "vless", "settings": {"udp": True, "clients": vmess_clients(), "decryption": "none"}, "streamSettings": st}
	if opt == 10:
		st = {"network": "tcp"}
		st.update(xray_tls_obj())
		return {"port": port_s, "protocol": "trojan",
			"settings": {"clients": [{"password": uuid, "level": 0}]}, "streamSettings": st}
	return None

def edit_xray():
	path = xray_json
	if not os.path.isfile(path):
		warn("xray 未安装，跳过")
		return
	title("修改 xray（协议 / 端口 / UUID）")
	print("   当前 UUID: %s" % (inbound_info((xray_data.get("inbounds") or [{}])[0], ip)[2] or "-"))
	ibs = xray_data.get("inbounds") or []
	uuid_now = inbound_info(ibs[0], ip)[2] if ibs else ""
	new_ports = {}
	for i, ib in enumerate(ibs, 1):
		label, port, uid, link = inbound_info(ib, ip)
		while True:
			ans = ask("   [%d] %s 当前 :%s  新端口(回车不改): " % (i, label, port))
			if not ans:
				break
			if not valid_port(ans):
				warn("端口要 1-65535 的整数")
				continue
			if ans == str(port):
				break
			if port_busy(ans):
				warn(":%s 已经有进程在监听，换一个" % ans)
				continue
			new_ports[i - 1] = ans
			break
	new_uuid = ask("   新 UUID（回车不改，输入 - 随机生成一个）: ")
	changed = False
	for idx, p in new_ports.items():
		old = ibs[idx].get("port", "")
		ibs[idx]["port"] = int(p) if isinstance(old, int) else str(p)
		changed = True
	if new_uuid:
		if new_uuid == "-":
			import uuid as _uuid
			new_uuid = str(_uuid.uuid4())
		if not re.match(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", new_uuid):
			warn("UUID 格式不对（要 8-4-4-4-12 的十六进制），本次不改 UUID")
		else:
			for ib in ibs:
				for c in ((ib.get("settings") or {}).get("clients") or []):
					if "id" in c:
						c["id"] = new_uuid
					elif "password" in c:
						c["password"] = new_uuid
			uuid_now = new_uuid
			changed = True
			print("   新 UUID: %s" % new_uuid)
	ans = ask("   要重新选协议组合吗?(y/N，回车保留现在的协议): ")
	if ans.lower().startswith("y"):
		title("xray 协议组合")
		cur = {}
		for ib in ibs:
			o = xray_opt_of(ib)
			if o and o not in cur:
				cur[o] = str(ib.get("port", ""))
		for num, label in XRAY_OPTS:
			print("   %2d. %-22s %s" % (num, label, ("当前 :%s" % cur[num]) if num in cur else ""))
		sel_txt = ask("   请输入选项(1-10，空格分隔，回车跳过): ")
		sel = sorted({int(x) for x in sel_txt.split() if x.isdigit() and 1 <= int(x) <= 10})
		if not sel:
			print("   没选任何协议，保留现状")
		else:
			new_ibs = []
			for o in sel:
				label = [l for n, l in XRAY_OPTS if n == o][0]
				default_p = cur.get(o, "")
				p = None
				while True:
					ans_p = ask("   [%d] %s 端口%s: " % (o, label, ("(回车沿用 :%s)" % default_p) if default_p else ""))
					cand = ans_p or default_p
					if not cand:
						warn("没填端口，跳过 %s" % label)
						break
					if not valid_port(cand):
						warn("端口要 1-65535 的整数")
						continue
					p = cand
					break
				if not p:
					continue
				wspath = "/"
				if o in (4, 5, 6):
					cur_path = "/"
					for ib in ibs:
						if xray_opt_of(ib) == o:
							cur_path = ((ib.get("streamSettings") or {}).get("wsSettings") or {}).get("path") or "/"
					wspath = ask("   [%d] %s websocket 路径(默认 %s): " % (o, label, cur_path)) or cur_path
				ib_new = xray_build_inbound(o, p, uuid_now, wspath)
				if not ib_new:
					warn("生成 %s 失败（可能是 xray 二进制不可用），跳过" % label)
					continue
				new_ibs.append(ib_new)
			if new_ibs:
				xray_data["inbounds"] = new_ibs
				ibs = new_ibs
				changed = True
	if not changed:
		print("   xray 没有改动")
		return
	bak = backup_file(path)
	try:
		write_json(path, xray_data)
	except Exception as e:
		fail("写配置失败: %s" % e)
		return
	ports = [str(ib.get("port")) for ib in ibs]
	restart_check("xray", ports, bak, path)
	try:
		fresh = json.load(open(path))
	except Exception:
		fresh = xray_data
	print("\n   %s新的分享链接：%s" % (CB, C0))
	for ib in (fresh.get("inbounds") or []):
		label, port, uid, link = inbound_info(ib, ip)
		print("   [%s] :%s" % (label, port))
		if link:
			print("     %s" % link)

def edit_cns():
	if not os.path.isfile(cns_json):
		warn("cns 未安装，跳过")
		return
	title("修改 cns（端口 / TLS 端口 / 加密密码 / 代理头域）")
	listen = cns_data.get("Listen_addr") or []
	cur_port = str(listen[0]).lstrip(":") if listen else ""
	tls = cns_data.get("Tls") or {}
	tls_listen = tls.get("Listen_addr") or []
	cur_tls = str(tls_listen[0]).lstrip(":") if tls_listen else ""
	changed = False
	while True:
		ans = ask("   当前 TCP 端口 :%s  新端口(回车不改): " % (cur_port or "-"))
		if not ans:
			break
		if not valid_port(ans):
			warn("端口要 1-65535 的整数")
			continue
		if port_busy(ans) and ans != cur_port:
			warn(":%s 已经有进程在监听，换一个" % ans)
			continue
		cns_data["Listen_addr"] = [":" + ans]
		changed = True
		break
	while True:
		ans = ask("   当前 TLS 端口 :%s  新 TLS 端口(回车不改，输入 0 关闭 TLS): " % (cur_tls or "-"))
		if not ans:
			break
		if ans == "0":
			cns_data.pop("Tls", None)
			changed = True
			print("   已关闭 TLS 监听")
			break
		if not valid_port(ans):
			warn("端口要 1-65535 的整数")
			continue
		if port_busy(ans) and ans != cur_tls:
			warn(":%s 已经有进程在监听，换一个" % ans)
			continue
		cns_data.setdefault("Tls", {})["Listen_addr"] = [":" + ans]
		changed = True
		break
	pw = cns_data.get("Encrypt_password") or ""
	ans = ask("   当前加密密码 %s  新密码(回车不改，输入 - 清空): " % (pw if pw else "（空）"))
	if ans:
		cns_data["Encrypt_password"] = "" if ans == "-" else ans
		changed = True
	ans = ask("   当前代理头域 %s  新头域(回车不改): " % str(cns_data.get("Proxy_key", "Meng")))
	if ans:
		cns_data["Proxy_key"] = ans
		changed = True
	if not changed:
		print("   cns 没有改动")
		return
	bak = backup_file(cns_json)
	try:
		write_json(cns_json, cns_data)
	except Exception as e:
		fail("写配置失败: %s" % e)
		return
	ports = [str(x).lstrip(":") for x in (cns_data.get("Listen_addr") or [])]
	if cns_data.get("Tls"):
		ports += [str(x).lstrip(":") for x in (cns_data["Tls"].get("Listen_addr") or [])]
	restart_check("cns", ports, bak, cns_json)
	print("   现在 cns 端口 %s，加密密码 %s，Proxy_key %s" % (
		",".join(":" + p for p in ports),
		cns_data.get("Encrypt_password") or "（空，不加密）",
		cns_data.get("Proxy_key", "Meng")))

def edit_amy4():
	if not os.path.isfile(amy_json):
		warn("amy4 未安装，跳过")
		return
	title("修改 amy4（端口 / ClientKey / IPv6）")
	ins = (amy_data.get("AmyIns") or [{}])[0]
	s = ins.setdefault("ANetSettings", {})
	cur = str(s.get("ListenAddr", "")).lstrip(":")
	cur_key = ", ".join(k for k in (s.get("ClientKeys") or []) if k)
	cur_v6 = s.get("IPv6Support", False)
	changed = False
	while True:
		ans = ask("   当前端口 :%s  新端口(回车不改): " % (cur or "-"))
		if not ans:
			break
		if not valid_port(ans):
			warn("端口要 1-65535 的整数")
			continue
		if port_busy(ans) and ans != cur:
			warn(":%s 已经有进程在监听，换一个" % ans)
			continue
		s["ListenAddr"] = ":" + ans
		changed = True
		break
	ans = ask("   当前 ClientKey %s  新 Key(回车不改，输入 - 清空不校验): " % (cur_key or "（空）"))
	if ans:
		s["ClientKeys"] = [] if ans == "-" else [ans]
		changed = True
	ans = ask("   当前 IPv6 %s  开启 IPv6?(y/n，回车不改): " % ("true" if cur_v6 is True else "false"))
	if ans:
		s["IPv6Support"] = ans.lower().startswith("y")
		changed = True
	if not changed:
		print("   amy4 没有改动")
		return
	bak = backup_file(amy_json)
	try:
		write_json(amy_json, amy_data)
	except Exception as e:
		fail("写配置失败: %s" % e)
		return
	restart_check("amy4", [str(s.get("ListenAddr", "")).lstrip(":")], bak, amy_json)
	print("   现在 amy4 端口 %s，ClientKey %s，IPv6 %s" % (
		s.get("ListenAddr", "-"),
		", ".join(k for k in (s.get("ClientKeys") or []) if k) or "（空，不校验）",
		"true" if s.get("IPv6Support") is True else "false"))

def edit_tinyproxy():
	conf = tinyproxy_conf_path()
	if not conf:
		warn("tinyproxy 未安装（本仓库不含该二进制，可 apt install tinyproxy 装上后再来改）")
		return
	title("修改 tinyproxy（端口 / BasicAuth 用户名密码）")
	txt = open(conf, errors="ignore").read()
	port_m = re.search(r"^\s*Port\s+(\d+)", txt, re.M)
	auth_m = re.search(r"^\s*BasicAuth\s+(\S+)\s+(\S+)", txt, re.M)
	user_m = re.search(r"^\s*BasicAuthUser\s+(.+)$", txt, re.M)
	pw_m = re.search(r"^\s*BasicAuthPassword\s+(.+)$", txt, re.M)
	cur_port = port_m.group(1) if port_m else ""
	if auth_m:
		cur_user, cur_pw = auth_m.group(1), auth_m.group(2)
	else:
		cur_user = user_m.group(1).strip() if user_m else ""
		cur_pw = pw_m.group(1).strip() if pw_m else ""
	changed = False
	while True:
		ans = ask("   当前端口 :%s  新端口(回车不改): " % (cur_port or "-"))
		if not ans:
			break
		if not valid_port(ans):
			warn("端口要 1-65535 的整数")
			continue
		if port_busy(ans) and ans != cur_port:
			warn(":%s 已经有进程在监听，换一个" % ans)
			continue
		cur_port = ans
		changed = True
		break
	ans = ask("   当前 BasicAuth %s  新用户名(回车不改，输入 - 关闭认证): " % (("%s : %s" % (cur_user, cur_pw)) if cur_user else "（无）"))
	auth_clear = False
	if ans == "-":
		auth_clear = True
		changed = True
		print("   已关闭 BasicAuth 认证")
	elif ans:
		cur_user = ans
		cur_pw = ask("   BasicAuth 密码: ") or cur_pw
		changed = True
	if not changed:
		print("   tinyproxy 没有改动")
		return
	content = txt if txt.endswith("\n") else txt + "\n"
	lines = content.splitlines()
	for i, line in enumerate(lines):
		if re.match(r"^\s*Port\s+", line) and cur_port:
			lines[i] = re.sub(r"(^\s*Port\s+)\d+", r"\g<1>" + str(cur_port), line)
	lines = [l for l in lines if not re.match(r"^\s*BasicAuth(User|Password)\s+", l) and not re.match(r"^\s*BasicAuth\s+", l)]
	if not auth_clear and cur_user:
		idx = next((i for i, l in enumerate(lines) if re.match(r"^\s*Port\s+", l)), 0)
		lines.insert(idx + 1, "BasicAuth %s %s" % (cur_user, cur_pw))
	bak = backup_file(conf)
	try:
		with open(conf, "w") as f:
			f.write("\n".join(lines) + "\n")
	except Exception as e:
		fail("写配置失败: %s" % e)
		return
	unit = run("systemctl list-unit-files 2>/dev/null | grep -o 'tinyproxy.service' | head -1")
	if not unit:
		warn("没找到 tinyproxy.service，配置已改，手动重启 tinyproxy 生效（备份 %s）" % bak)
		return
	restart_check("tinyproxy", [cur_port] if cur_port else [], bak, conf)
	print("   现在 tinyproxy 端口 %s，认证 %s" % (
		cur_port or "-",
		"（无）" if auth_clear or not cur_user else "%s : %s" % (cur_user, cur_pw)))

def svc_units():
	names = []
	for name, d in (("xray", "/usr/local/xray"), ("cns", "/usr/local/cns"), ("amy4", "/usr/local/amy4"), ("tinyproxy", "")):
		if name == "tinyproxy":
			if not (tinyproxy_conf_path() or run("command -v tinyproxy")):
				continue
		elif not os.path.isdir(d):
			continue
		names.append(name)
	return names

def do_power(action):
	names = svc_units()
	if not names:
		print("   没有已安装的服务")
		return
	title("停止服务" if action == "stop" else "启动服务")
	for i, n in enumerate(names, 1):
		st = run("systemctl is-active %s" % n) or "unknown"
		color = CG if st == "active" else CR
		print("   %d. %-10s %s%s%s" % (i, n, color, st, C0))
	sel = ask("   输入要%s的服务编号（多个用空格隔开，回车取消）: " % ("停止" if action == "stop" else "启动"))
	idxs = sorted({int(x) for x in sel.split() if x.isdigit()})
	targets = [names[i - 1] for i in idxs if 1 <= i <= len(names)]
	if not targets:
		print("   没选任何服务，取消")
		return
	for n in targets:
		log_action("power", "%s %s" % ("停止" if action == "stop" else "启动", n))
		run("systemctl %s %s 2>&1" % (action, n))
		if action == "stop":
			run("systemctl disable %s 2>&1" % n)
		else:
			run("systemctl enable %s 2>&1" % n)
		time.sleep(2)
		st = run("systemctl is-active %s" % n) or "unknown"
		en = run("systemctl is-enabled %s 2>/dev/null" % n) or "-"
		if action == "stop":
			if st == "inactive":
				ok("%s 已停止，开机自启已关闭（%s）" % (n, en))
			else:
				fail("%s 停止后状态是 %s" % (n, st))
		else:
			if st == "active":
				ok("%s 已启动，开机自启已打开（%s）" % (n, en))
			else:
				fail("%s 启动失败，状态是 %s" % (n, st))
				log = run("journalctl -u %s -n 8 --no-pager 2>/dev/null | tail -8" % n)
				if log:
					print(log)

def kit_builds_path():
	base = os.path.dirname(os.path.abspath(os.environ.get("PARSO_SELF", "") or "."))
	for c in (os.path.join(base, "parso", "builds.sh"),
	          "/root/1-main/parso/builds.sh", "/root/parso/builds.sh"):
		if os.path.isfile(c):
			return c
	return ""

def ensure_kit():
	p = kit_builds_path()
	if p:
		return p
	print("   本机还没有安装器 parso/builds.sh，先拉整包…")
	rc = 1
	if os.path.isfile("/root/pull.sh"):
		rc = subprocess.call(["sh", "/root/pull.sh", "kit"])
	if rc != 0:
		rc = subprocess.call(["sh", "-c", "curl -L --progress-bar https://codeload.github.com/abcc123445653/1/tar.gz/refs/heads/main | tar xz -C /root"])
	if rc != 0:
		fail("整包拉取失败，检查网络后重试")
		return ""
	return kit_builds_path()

def run_builds(mode):
	p = ensure_kit()
	if not p:
		return
	title("安装服务" if mode == "install" else "卸载服务")
	if mode == "install":
		print("   进入安装菜单，按提示选项目、填端口等参数；装完自动回到这里")
	else:
		print("   进入卸载菜单，按提示选要卸的项目；卸完自动回到这里")
	print("")
	log_action("builds", "进入%s菜单" % ("安装" if mode == "install" else "卸载"))
	env = dict(os.environ)
	env["PARSO_TASK"] = "1" if mode == "install" else "2"
	subprocess.call(["sh", p], stdin=sys.stdin, stdout=sys.stdout, stderr=sys.stderr, env=env)
	print("")
	view_config()

def view_config():
	p = os.environ.get("PARSO_SELF", "")
	if p and os.path.isfile(p):
		print("")
		env = dict(os.environ)
		env.pop("PARSO_EDIT", None)
		subprocess.call(["sh", os.path.abspath(p)], env=env)
		print("")
	else:
		warn("找不到脚本自身路径，刷新不了显示，请重新运行 sh status.sh")

def svc_port(kind):
	try:
		if kind == "xray":
			d = json.load(open(xray_json))
			return ":" + str((d.get("inbounds") or [{}])[0].get("port", "?"))
		if kind == "cns":
			d = json.load(open(cns_json))
			return (d.get("Listen_addr") or [":?"])[0]
		if kind == "amy4":
			d = json.load(open(amy_json))
			return d["AmyIns"][0]["ANetSettings"]["ListenAddr"]
		if kind == "tinyproxy":
			pth = tinyproxy_conf_path()
			if pth:
				for line in open(pth):
					if line.strip().lower().startswith("port "):
						return ":" + line.split()[1]
	except Exception:
		pass
	return ""

def svc_item(n, label, unit, kind):
	cfg = {"xray": xray_json, "cns": cns_json, "amy4": amy_json}.get(kind) or tinyproxy_conf_path()
	if not (cfg and os.path.isfile(cfg)):
		return "   %d. %s  \033[90m— 未安装\033[0m" % (n, label)
	st = run("systemctl is-active %s 2>/dev/null" % unit)
	if st == "active":
		state = "\033[32m● 运行中 %s\033[0m" % svc_port(kind)
	else:
		state = "\033[31m○ 未运行\033[0m"
	return "   %d. %s  %s" % (n, label, state)

title("修改配置")
log_action("panel", "打开配置面板")
modifiable = [n for n, p in (("xray", xray_json), ("cns", cns_json), ("amy4", amy_json), ("tinyproxy", tinyproxy_conf_path())) if os.path.isfile(p)]
if not modifiable:
	warn("没有检测到已安装的服务，输入 8 可以现在装")

while True:
	print("")
	print("   可修改项目（右侧为当前状态）：")
	print(svc_item(1, "xray（协议/端口/UUID）", "xray", "xray"))
	print(svc_item(2, "cns（端口/密码/TLS）", "cns", "cns"))
	print(svc_item(3, "amy4（端口/ClientKey）", "amy4", "amy4"))
	print(svc_item(4, "tinyproxy（端口/认证）", "tinyproxy", "tinyproxy"))
	print("   5. 停止服务（关自启）  6. 启动服务（开自启）")
	print("   7. 查看当前配置        8. 安装服务")
	print("   9. 卸载服务            0. 关闭")
	choice = ask("   选项目（多个用空格隔开；输入 0 回车关闭）: ")
	sel = set(choice.split())
	if not sel or sel & {"0", "q", "quit", "exit", "关闭"}:
		print("   已关闭。")
		print("")
		sys.exit(2)
	if "7" in sel:
		view_config()
		continue
	done = False
	if "8" in sel:
		run_builds("install")
		done = True
	if "9" in sel:
		run_builds("uninstall")
		done = True
	if "1" in sel and os.path.isfile(xray_json):
		b4 = snap("xray")
		edit_xray()
		aft = snap("xray")
		if b4 != aft:
			log_action("xray", "%s → %s" % (b4, aft))
		done = True
	if "2" in sel and os.path.isfile(cns_json):
		b4 = snap("cns")
		edit_cns()
		aft = snap("cns")
		if b4 != aft:
			log_action("cns", "%s → %s" % (b4, aft))
		done = True
	if "3" in sel and os.path.isfile(amy_json):
		b4 = snap("amy4")
		edit_amy4()
		aft = snap("amy4")
		if b4 != aft:
			log_action("amy4", "%s → %s" % (b4, aft))
		done = True
	if "4" in sel and tinyproxy_conf_path():
		b4 = snap("tinyproxy")
		edit_tinyproxy()
		aft = snap("tinyproxy")
		if b4 != aft:
			log_action("tinyproxy", "%s → %s" % (b4, aft))
		done = True
	if "5" in sel:
		do_power("stop")
		done = True
	if "6" in sel:
		do_power("start")
		done = True
	if not done:
		print("   没有改动")
	print("")

PY

chmod 600 "$PYFILE" 2>/dev/null
if [ "$1" = "edit" ] || [ "$1" = "-e" ]; then
	PARSO_SELF="$0" PARSO_EDIT=1 python3 "$PYFILE"
	rc=$?
	rm -f "$PYFILE"
	if [ "$rc" -eq 2 ]; then
		exit 0
	fi
	echo ""
	echo "已执行修改，下面是刷新后的完整状态："
	rm -f "$PYFILE"
	exec sh "$0"
else
	python3 "$PYFILE"
	rc=$?
	rm -f "$PYFILE"
	exit $rc
fi
