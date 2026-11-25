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

cat >"$PYFILE" <<'PY'
import json, os, re, shutil, subprocess, datetime, socket, time, sys

C0 = "\033[0m"
CY = "\033[36m"
CB = "\033[1m"
CG = "\033[32m"
CR = "\033[31m"
CYEL = "\033[33m"

EDIT = os.environ.get("PARSO_EDIT") == "1"

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
		return b
	except Exception:
		return ""

def write_json(path, obj):
	tmp = path + ".new"
	with open(tmp, "w") as f:
		json.dump(obj, f, ensure_ascii=False, indent=2)
	os.replace(tmp, path)

def restart_check(name, ports, bak=""):
	run("systemctl restart %s 2>&1" % name)
	time.sleep(2)
	st = run("systemctl is-active %s" % name)
	missing = [p for p in ports if not port_busy(p)]
	if st != "active" or missing:
		fail("重启后状态 %s%s" % (st, ("，端口没在监听: " + ", ".join(":" + p for p in missing)) if missing else ""))
		log = run("journalctl -u %s -n 10 --no-pager 2>/dev/null | tail -10" % name)
		if log:
			print(log)
		if bak:
			warn("原配置备份在 %s ，要回退直接 cp 回去再 systemctl restart %s" % (bak, name))
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

if not EDIT:
	print("")
	print("   改端口 / 密码 / UUID / ClientKey：\033[36msh status.sh edit\033[0m")
	print("")
	sys.exit(0)

# ================= 修改配置 =================
def edit_xray():
	path = xray_json
	if not os.path.isfile(path):
		warn("xray 未安装，跳过")
		return
	title("修改 xray（端口 / UUID）")
	print("   当前 UUID: %s" % (inbound_info((xray_data.get("inbounds") or [{}])[0], ip)[2] or "-"))
	ibs = xray_data.get("inbounds") or []
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
			changed = True
			print("   新 UUID: %s" % new_uuid)
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
	restart_check("xray", ports, bak)
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
	restart_check("cns", ports, bak)
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
	restart_check("amy4", [str(s.get("ListenAddr", "")).lstrip(":")], bak)
	print("   现在 amy4 端口 %s，ClientKey %s，IPv6 %s" % (
		s.get("ListenAddr", "-"),
		", ".join(k for k in (s.get("ClientKeys") or []) if k) or "（空，不校验）",
		"true" if s.get("IPv6Support") is True else "false"))

title("修改配置")
modifiable = [n for n, p in (("xray", xray_json), ("cns", cns_json), ("amy4", amy_json)) if os.path.isfile(p)]
if not modifiable:
	print("   没有已安装的服务，先 sh builds.sh 装一个再来改。")
	print("")
	sys.exit(0)
print("   可修改：1. xray（端口/UUID）  2. cns（端口/TLS端口/加密密码/代理头域）  3. amy4（端口/ClientKey/IPv6）")
choice = ask("   选项目（多个用空格隔开，直接回车退出）: ")
sel = set(choice.split())
done = False
if "1" in sel and os.path.isfile(xray_json):
	edit_xray()
	done = True
if "2" in sel and os.path.isfile(cns_json):
	edit_cns()
	done = True
if "3" in sel and os.path.isfile(amy_json):
	edit_amy4()
	done = True
if not done:
	print("   没有改动")
print("")
PY

chmod 600 "$PYFILE" 2>/dev/null
if [ "$1" = "edit" ] || [ "$1" = "-e" ]; then
	PARSO_EDIT=1 python3 "$PYFILE"
	rc=$?
	rm -f "$PYFILE"
	echo ""
	echo "已执行修改，下面是刷新后的完整状态："
	exec sh "$0"
else
	python3 "$PYFILE"
	rc=$?
	rm -f "$PYFILE"
	exit $rc
fi
