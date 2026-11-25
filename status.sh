#!/bin/sh
# 查看本机当前运行的所有配置信息
# 用法: sh status.sh

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

if ! command -v python3 >/dev/null 2>&1; then
	echo "需要 python3 才能完整显示配置，先用 apt-get install -y python3 装一下。" >&2
	exit 1
fi

python3 - <<'PY'
import json, os, re, shutil, subprocess, datetime, socket

C0 = "\033[0m"
CY = "\033[36m"
CB = "\033[1m"
CG = "\033[32m"
CR = "\033[31m"
CYEL = "\033[33m"

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

# ---------- 基础信息 ----------
host = socket.gethostname()
def pick_ip():
	env_ip = os.environ.get("PUBLIC_IP", "").strip()
	if re.match(r"^\d+\.\d+\.\d+\.\d+$", env_ip):
		return env_ip, True
	# 服务器常在 NAT 后面（本机只有 172.x），所以先问外网探针要公网 IP
	for url in ("https://ifconfig.me/ip", "https://ipinfo.io/ip", "https://api.ipify.org", "https://4.ipw.cn"):
		out = run("curl -k -s -m 4 %s" % url)
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

title("服务状态")
print("   %s%-10s %-10s %-10s %-22s %s%s" % (CB, "项目", "状态", "开机自启", "监听端口", "PID", C0))
installed = []
for name, d in SERVICES:
	if not os.path.isdir(d):
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
if not os.path.isdir("/usr/local/xray"):
	print("   %s未安装%s" % ("\033[90m", C0))
elif not os.path.isfile(xray_json):
	fail("目录存在但没找到 %s" % xray_json)
else:
	try:
		data = json.load(open(xray_json))
	except Exception as e:
		fail("配置解析失败: %s" % e)
		data = {}
	ib_list = data.get("inbounds") or []
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
		outbounds = data.get("outbounds") or []
		if outbounds:
			kv("出站", ",".join(o.get("protocol", "") for o in outbounds))

# ---------- cns ----------
title("cns")
cns_dir = "/usr/local/cns"
if not os.path.isdir(cns_dir):
	print("   %s未安装%s" % ("\033[90m", C0))
else:
	cns_json = os.path.join(cns_dir, "cns.json")
	kv("安装目录", cns_dir)
	if not os.path.isfile(cns_json):
		fail("目录存在但没找到 %s" % cns_json)
	else:
		try:
			c = json.load(open(cns_json))
		except Exception as e:
			fail("配置解析失败: %s" % e)
			c = {}
		kv("配置文件", cns_json)
		listen = c.get("Listen_addr") or []
		kv("监听端口", ",".join(str(x) for x in listen) or "-")
		tls = c.get("Tls") or {}
		if tls:
			kv("TLS 监听", ",".join(str(x) for x in (tls.get("Listen_addr") or [])) or "-")
		pw = c.get("Encrypt_password") or ""
		kv("加密密码", pw if pw else "（空，不加密）")
		kv("Proxy_key", str(c.get("Proxy_key", "Meng")))
		kv("Udp_flag", str(c.get("Udp_flag", "httpUDP")))
		kv("UDP/TCP 超时", "%s / %s 秒" % (c.get("Udp_timeout", "-"), c.get("Tcp_timeout", "-")))

# ---------- amy4 ----------
title("amy4")
amy_dir = "/usr/local/amy4"
if not os.path.isdir(amy_dir):
	print("   %s未安装%s" % ("\033[90m", C0))
else:
	amy_json = os.path.join(amy_dir, "amy4.json")
	kv("安装目录", amy_dir)
	if not os.path.isfile(amy_json):
		fail("目录存在但没找到 %s" % amy_json)
	else:
		try:
			a = json.load(open(amy_json))
		except Exception as e:
			fail("配置解析失败: %s" % e)
			a = {}
		kv("配置文件", amy_json)
		for ins in (a.get("AmyIns") or []):
			s = ins.get("ANetSettings") or {}
			kv("服务端口", str(s.get("ListenAddr", "-")))
			keys = s.get("ClientKeys") or []
			key_txt = ", ".join(k for k in keys if k)
			kv("ClientKey", key_txt if key_txt else "（空，不校验）")
			v6 = s.get("IPv6Support", "-")
			kv("IPv6 支持", "true" if v6 is True else ("false" if v6 is False else str(v6)))

# ---------- tinyproxy ----------
title("tinyproxy")
tp_dir = "/usr/local/tinyproxy"
if not os.path.isdir(tp_dir):
	print("   %s未安装（本仓库不含该二进制，安装时会跳过）%s" % ("\033[90m", C0))
else:
	kv("安装目录", tp_dir)
	conf = os.path.join(tp_dir, "tinyproxy.conf")
	if os.path.isfile(conf):
		txt = open(conf, errors="ignore").read()
		port = re.search(r"^\s*Port\s+(\d+)", txt, re.M)
		kv("监听端口", port.group(1) if port else "-")
		for key in ("Allow", "BasicAuthUser", "BasicAuthPassword"):
			m = re.search(r"^\s*%s\s+(.+)$" % key, txt, re.M)
			if m:
				kv(key, m.group(1).strip())

# ---------- 汇总 ----------
title("汇总")
kv("已安装", ", ".join(installed) if installed else "无")
kv("开机自启", ", ".join(x for x in installed if run("systemctl is-enabled %s 2>/dev/null" % x) == "enabled") or "无")
for name, d in SERVICES:
	if os.path.isdir(d):
		sz = run("du -sh %s 2>/dev/null | awk '{print $1}'" % d)
		kv("占用 %s" % name, sz or "-")
print("")
PY
