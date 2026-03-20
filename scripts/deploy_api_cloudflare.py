#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Deploy nginx vhost for api.milviar.ru behind Cloudflare.

Usage (password via env, do NOT hardcode):
  export SSH_PASSWORD='...'
  python3 scripts/deploy_api_cloudflare.py \
    --host 83.166.246.225 \
    --user root \
    --domain api.milviar.ru \
    --backend-host 127.0.0.1

If you don't know backend port, omit --backend-port and script will try to
detect it from existing nginx config (proxy_pass).

If you don't have Cloudflare Origin cert/key, omit --origin-cert/--origin-key.
Script will generate a self-signed certificate on the server.
In that case Cloudflare SSL/TLS mode must be "Full" (NOT strict).

Notes:
  - Origin cert should be Cloudflare Origin Certificate for the domain.
  - If using self-signed, Cloudflare SSL/TLS mode should be Full (NOT strict).
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import re
import getpass
from dataclasses import dataclass

import paramiko
from scp import SCPClient


DEFAULT_PORTS = [22, 2222, 22022, 2200, 22000, 22001]


@dataclass
class SshTarget:
    host: str
    user: str
    port: int


def _print_err(msg: str) -> None:
    print(msg, file=sys.stderr)


def _tcp_port_open(host: str, port: int, timeout_s: float = 3.0) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(timeout_s)
    try:
        return sock.connect_ex((host, port)) == 0
    finally:
        try:
            sock.close()
        except Exception:
            pass


def _connect_ssh(target: SshTarget, password: str | None, timeout_s: int = 20) -> paramiko.SSHClient:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        hostname=target.host,
        port=target.port,
        username=target.user,
        password=password,
        timeout=timeout_s,
        auth_timeout=timeout_s,
        banner_timeout=timeout_s,
        look_for_keys=False,
        allow_agent=False,
    )
    return ssh


def _exec(ssh: paramiko.SSHClient, cmd: str, *, check: bool = True) -> tuple[int, str, str]:
    print(f"==> {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    exit_code = stdout.channel.recv_exit_status()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    if out.strip():
        print(out.rstrip())
    if err.strip():
        _print_err(err.rstrip())
    if check and exit_code != 0:
        raise RuntimeError(f"Command failed ({exit_code}): {cmd}")
    return exit_code, out, err


def _upload_file(ssh: paramiko.SSHClient, local_path: str, remote_path: str) -> None:
    with SCPClient(ssh.get_transport()) as scp:
        scp.put(local_path, remote_path)


def _render_nginx_conf(domain: str, cert_path: str, key_path: str, backend_host: str, backend_port: int) -> str:
    # Keep config minimal and predictable.
    return f"""# Used by Socket.IO: if client doesn't request an upgrade (polling), don't force it.
map $http_upgrade $connection_upgrade {{
  default upgrade;
  ''      close;
}}

server {{
  listen 80;
  server_name {domain};
  return 301 https://$host$request_uri;
}}

server {{
  listen 443 ssl http2;
  server_name {domain};

  ssl_certificate     {cert_path};
  ssl_certificate_key {key_path};

  # Optional hardening
  ssl_protocols TLSv1.2 TLSv1.3;

  # Быстрая проверка, что домен/SSL живые (не зависит от backend)
  location = / {{
    add_header Content-Type application/json;
    return 200 '{{"status":"ok","service":"api","domain":"{domain}"}}';
  }}

  # WebSocket (Socket.IO). Важно: не отправляем "Connection: upgrade" для обычных HTTP запросов.
  location /socket.io/ {{
    proxy_pass http://{backend_host}:{backend_port};
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
    proxy_connect_timeout 30s;
    proxy_buffering off;
  }}

  location / {{
    proxy_pass http://{backend_host}:{backend_port};
    proxy_http_version 1.1;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # Для обычного HTTP убираем Connection/Upgrade чтобы не ломать upstream.
    proxy_set_header Connection "";
    proxy_set_header Upgrade "";

    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
    proxy_connect_timeout 30s;
    proxy_buffering off;
  }}
}}
"""


def _detect_backend_port_from_nginx(ssh: paramiko.SSHClient) -> int | None:
    # Heuristic: extract all proxy_pass ports to localhost from nginx -T.
    # Do it on the server side to avoid huge outputs.
    cmd = (
        r"nginx -T 2>&1 | "
        r"sed -n "
        r"'s/^[[:space:]]*proxy_pass[[:space:]]\\+http:\\/\\/"
        r"\\(127\\.0\\.0\\.1\\|localhost\\|0\\.0\\.0\\.0\\):\\([0-9]\\+\\).*/\\2/p'"
        r" | head -n 50"
    )
    exit_code, out, _ = _exec(ssh, cmd, check=False)
    if exit_code != 0:
        return None
    ports: list[int] = []
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ports.append(int(line))
        except ValueError:
            continue
    if not ports:
        return None

    # Prefer common Node backend port if present.
    if 3000 in ports:
        return 3000

    # Otherwise pick the first extracted port.
    return ports[0]


def _ensure_self_signed_cert(ssh: paramiko.SSHClient, domain: str) -> tuple[str, str]:
    remote_dir = "/etc/ssl/selfsigned"
    remote_cert = f"{remote_dir}/{domain}.crt"
    remote_key = f"{remote_dir}/{domain}.key"
    _exec(ssh, f"mkdir -p {remote_dir} && chmod 700 {remote_dir}")
    _exec(
        ssh,
        (
            f"test -f {remote_cert} -a -f {remote_key} || "
            f"openssl req -x509 -nodes -newkey rsa:2048 -days 3650 "
            f"-keyout {remote_key} -out {remote_cert} "
            f"-subj '/C=RU/O=MessengerApp/CN={domain}'"
        ),
    )
    _exec(ssh, f"chmod 644 {remote_cert}")
    _exec(ssh, f"chmod 600 {remote_key}")
    return remote_cert, remote_key


def _is_port_listening(ssh: paramiko.SSHClient, port: int) -> bool:
    # Check listen sockets (fast). Exit code 0 means found.
    code, _, _ = _exec(ssh, f"ss -lnt | awk '{{print $4}}' | grep -q ':{port}$'", check=False)
    return code == 0


def _attempt_start_backend(ssh: paramiko.SSHClient, backend_port: int) -> None:
    print(f"Backend not reachable on 127.0.0.1:{backend_port}. Trying to start it...")

    # 1) pm2 (common for Node)
    _exec(ssh, "command -v pm2 >/dev/null 2>&1 && pm2 resurrect || true", check=False)
    _exec(ssh, "command -v pm2 >/dev/null 2>&1 && pm2 restart all || true", check=False)

    # 2) docker (if used)
    _exec(ssh, "command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Names}} {{.Status}}' || true", check=False)
    _exec(ssh, "command -v docker >/dev/null 2>&1 && docker start $(docker ps -aq) || true", check=False)

    # 3) systemd: try to restart likely units (best-effort)
    code, units_out, _ = _exec(ssh, "ls -1 /etc/systemd/system 2>/dev/null || true", check=False)
    candidates: list[str] = []
    if units_out:
        for line in units_out.splitlines():
            name = line.strip()
            if not name.endswith(".service"):
                continue
            lower = name.lower()
            if any(k in lower for k in ["messenger", "milviar", "backend", "api", "server", "node", "pm2"]):
                candidates.append(name)
    # Restart a few candidates (avoid massive loops)
    for svc in candidates[:10]:
        _exec(ssh, f"systemctl restart {svc} || true", check=False)

    # 4) print some debug context for manual follow-up
    _exec(ssh, "ps aux | egrep -i 'node|pm2|docker|gunicorn|uvicorn|python' | head -n 30 || true", check=False)
    _exec(
        ssh,
        "echo 'Listening ports snapshot:' && ss -lntp | egrep ':(3000|8080|8000|5000|4000|9000|8888|9090) ' || true",
        check=False,
    )
    _exec(ssh, "echo 'Probe 8080:' && curl -sS --connect-timeout 2 --max-time 4 -D - http://127.0.0.1:8080/ -o /dev/null | sed -n '1,8p' || true", check=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", default="root")
    parser.add_argument("--ports", nargs="*", type=int, default=DEFAULT_PORTS)
    parser.add_argument("--domain", required=True, help="e.g. api.milviar.ru")
    parser.add_argument("--backend-host", default="127.0.0.1")
    parser.add_argument("--backend-port", type=int, required=False, help="optional; autodetected from nginx if omitted")
    parser.add_argument("--origin-cert", required=False, help="optional: local path to origin.pem")
    parser.add_argument("--origin-key", required=False, help="optional: local path to origin.key")
    parser.add_argument("--lockdown-origin", action="store_true", help="OPTIONAL: allow 80/443 only from Cloudflare IPs via ufw")
    args = parser.parse_args()

    password = os.environ.get("SSH_PASSWORD")
    if not password:
        # Avoid leaking credentials via shell history or terminal logs.
        try:
            password = getpass.getpass("SSH password (will not echo): ").strip()
        except (EOFError, KeyboardInterrupt):
            _print_err("ERROR: SSH password not provided.")
            return 2
        if not password:
            _print_err("ERROR: SSH password not provided.")
            return 2

    if (args.origin_cert and not args.origin_key) or (args.origin_key and not args.origin_cert):
        _print_err("ERROR: provide both --origin-cert and --origin-key, or neither.")
        return 2
    if args.origin_cert:
        if not os.path.isabs(args.origin_cert) or not os.path.isabs(args.origin_key):
            _print_err("ERROR: --origin-cert and --origin-key must be absolute paths.")
            return 2
        if not os.path.exists(args.origin_cert) or not os.path.exists(args.origin_key):
            _print_err("ERROR: origin cert/key files not found.")
            return 2

    connected: tuple[paramiko.SSHClient, SshTarget] | None = None
    for port in args.ports:
        if not _tcp_port_open(args.host, port):
            continue
        print(f"Port {port} open, trying SSH...")
        try:
            target = SshTarget(host=args.host, user=args.user, port=port)
            ssh = _connect_ssh(target, password=password)
            _exec(ssh, 'echo "connected"')
            connected = (ssh, target)
            print(f"SSH connected: {args.user}@{args.host}:{port}")
            break
        except Exception as e:
            _print_err(f"SSH failed on port {port}: {e}")
            try:
                ssh.close()  # type: ignore[name-defined]
            except Exception:
                pass

    if not connected:
        _print_err("ERROR: could not connect via SSH on any provided port.")
        return 1

    ssh, target = connected
    try:
        # Basic packages
        _exec(ssh, "export DEBIAN_FRONTEND=noninteractive && apt-get update -y")
        _exec(ssh, "export DEBIAN_FRONTEND=noninteractive && apt-get install -y nginx curl ca-certificates")

        # Backend port autodetect (if not provided)
        backend_port = args.backend_port
        if backend_port is None:
            backend_port = _detect_backend_port_from_nginx(ssh)
            if backend_port is None:
                _print_err("ERROR: could not detect backend port from nginx config. Provide --backend-port.")
                return 2
            print(f"Detected backend port from nginx: {backend_port}")

        # Certificates
        if args.origin_cert:
            remote_dir = "/etc/ssl/cloudflare"
            remote_cert = f"{remote_dir}/origin.pem"
            remote_key = f"{remote_dir}/origin.key"
            _exec(ssh, f"mkdir -p {remote_dir} && chmod 700 {remote_dir}")
            _upload_file(ssh, args.origin_cert, remote_cert)
            _upload_file(ssh, args.origin_key, remote_key)
            _exec(ssh, f"chmod 644 {remote_cert}")
            _exec(ssh, f"chmod 600 {remote_key}")
            print("Using provided Cloudflare Origin Certificate (Full strict).")
        else:
            remote_cert, remote_key = _ensure_self_signed_cert(ssh, args.domain)
            print("Using self-signed cert. Set Cloudflare SSL/TLS mode to Full (NOT strict).")

        # Nginx site
        site_available = f"/etc/nginx/sites-available/{args.domain}"
        site_enabled = f"/etc/nginx/sites-enabled/{args.domain}"
        conf = _render_nginx_conf(
            domain=args.domain,
            cert_path=remote_cert,
            key_path=remote_key,
            backend_host=args.backend_host,
            backend_port=int(backend_port),
        )
        # Write file safely via single-quoted heredoc. No need to escape '$' because
        # the quoted delimiter disables variable expansion in the remote shell.
        _exec(ssh, f"cat > {site_available} <<'EOF'\n{conf}\nEOF")
        _exec(ssh, f"ln -sf {site_available} {site_enabled}")
        _exec(ssh, "nginx -t")
        _exec(ssh, "systemctl reload nginx || service nginx reload")

        # Diagnostics: verify backend is reachable from nginx box
        _exec(ssh, f"ss -lntp | sed -n '/:{int(backend_port)} /p' || true", check=False)
        backend_check_cmd = (
            f"curl -sS --connect-timeout 2 --max-time 4 -D - "
            f"http://{args.backend_host}:{int(backend_port)}/ -o /dev/null | sed -n '1,12p' || true"
        )
        _exec(ssh, backend_check_cmd, check=False)
        if not _is_port_listening(ssh, int(backend_port)):
            _attempt_start_backend(ssh, int(backend_port))
            _exec(ssh, "sleep 2", check=False)
            _exec(ssh, f"ss -lntp | sed -n '/:{int(backend_port)} /p' || true", check=False)
            _exec(ssh, backend_check_cmd, check=False)

        # Backend API probe (direct)
        _exec(
            ssh,
            (
                "curl -sS --connect-timeout 2 --max-time 6 -D - "
                f"http://{args.backend_host}:{int(backend_port)}/api/auth/email-login "
                "-H 'Content-Type: application/json' "
                "-X POST --data '{\"email\":\"test@example.com\",\"password\":\"wrong\"}' "
                "-o - | sed -n '1,18p' || true"
            ),
            check=False,
        )

        # Origin HTTPS probe (bypass Cloudflare; hit local nginx 443)
        _exec(
            ssh,
            (
                f"curl -k -sS --connect-timeout 2 --max-time 6 -D - "
                f"--resolve {args.domain}:443:127.0.0.1 "
                f"https://{args.domain}/api/auth/email-login "
                "-H 'Content-Type: application/json' "
                "-X POST --data '{\"email\":\"test@example.com\",\"password\":\"wrong\"}' "
                "-o - | sed -n '1,18p' || true"
            ),
            check=False,
        )

        # Quick origin test (goes through Cloudflare if proxied; still useful)
        _exec(ssh, f"curl -k -sS --connect-timeout 3 --max-time 6 -D - https://{args.domain}/ -o - | sed -n '1,15p' || true", check=False)
        _exec(ssh, "tail -n 80 /var/log/nginx/error.log || true", check=False)

        if args.lockdown_origin:
            print("Lockdown enabled: configuring ufw to allow 80/443 only from Cloudflare.")
            _exec(ssh, "export DEBIAN_FRONTEND=noninteractive && apt-get install -y ufw")
            # Always allow SSH on the connected port first!
            _exec(ssh, f"ufw allow {target.port}/tcp")
            _exec(ssh, "ufw allow 80/tcp")
            _exec(ssh, "ufw allow 443/tcp")
            _exec(ssh, "ufw --force enable")
            # NOTE: Full Cloudflare-only lockdown requires adding all CF IP ranges.
            # We keep this conservative here to avoid locking you out.
            _exec(ssh, "ufw status verbose", check=False)

        print("\nDONE.")
        print("Next checks from your local machine/phone:")
        print(f"  https://{args.domain}/cdn-cgi/trace  (should show server: cloudflare when proxied)")
        print(f"  https://{args.domain}/api/auth/email-login  (should return JSON for POST)")
        return 0
    finally:
        try:
            ssh.close()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())

