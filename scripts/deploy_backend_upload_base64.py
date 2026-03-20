#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Deploy backend/index.js to the server and restart backend process.

Usage:
  export SSH_PASSWORD='...'
  python3 scripts/deploy_backend_upload_base64.py --host 83.166.246.225 --user root

What it does:
  - SSH in
  - Find a backend/index.js on the server (heuristic search under /root and /home)
  - Backup existing file
  - Upload local backend/index.js
  - Restart via pm2/systemd (best-effort)
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
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
    _, stdout, stderr = ssh.exec_command(cmd)
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


def _find_remote_backend_index_js(ssh: paramiko.SSHClient) -> str | None:
    # Keep it bounded; servers can have huge filesystems.
    # We only search likely places.
    cmd = (
        "set -euo pipefail; "
        "for base in /root /home; do "
        "  test -d \"$base\" || continue; "
        "  find \"$base\" -maxdepth 5 -type f -path '*/backend/index.js' 2>/dev/null; "
        "done | head -n 5"
    )
    code, out, _ = _exec(ssh, cmd, check=False)
    if code != 0:
        return None
    paths = [l.strip() for l in out.splitlines() if l.strip()]
    if not paths:
        return None
    # Prefer a path that looks like the repo name.
    for p in paths:
        if "msngIosAndroidv2" in p:
            return p
    return paths[0]


def _restart_backend_best_effort(ssh: paramiko.SSHClient) -> None:
    _exec(ssh, "command -v pm2 >/dev/null 2>&1 && pm2 ls || true", check=False)
    _exec(ssh, "command -v pm2 >/dev/null 2>&1 && pm2 restart all || true", check=False)

    # Common systemd unit names (best-effort).
    for svc in ("backend", "api", "messenger", "node", "app"):
        _exec(ssh, f"systemctl restart {svc} >/dev/null 2>&1 || true", check=False)

    _exec(ssh, "ps aux | egrep -i 'node|pm2' | head -n 25 || true", check=False)
    _exec(ssh, "curl -sS --connect-timeout 2 --max-time 6 -D - https://api.milviar.ru/ -o /dev/null | sed -n '1,10p' || true", check=False)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", default="root")
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()

    password = os.environ.get("SSH_PASSWORD") or None
    if not password:
        _print_err("SSH_PASSWORD is NOT set. Set it in your shell env and re-run.")
        return 2

    ports = [args.port] if args.port else DEFAULT_PORTS
    open_ports = [p for p in ports if _tcp_port_open(args.host, p)]
    if not open_ports:
        _print_err(f"No SSH ports reachable on {args.host}. Tried: {ports}")
        return 3

    target = SshTarget(host=args.host, user=args.user, port=open_ports[0])
    print(f"Connecting to {target.user}@{target.host}:{target.port} ...")
    ssh = _connect_ssh(target, password)
    try:
        remote_index = _find_remote_backend_index_js(ssh)
        if not remote_index:
            _print_err("Could not find remote backend/index.js under /root or /home")
            return 4

        local_index = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "backend", "index.js"))
        if not os.path.exists(local_index):
            _print_err(f"Local file not found: {local_index}")
            return 5

        print(f"Remote backend file: {remote_index}")
        _exec(ssh, f"cp -a {remote_index} {remote_index}.bak.$(date +%s) || true", check=False)
        _upload_file(ssh, local_index, remote_index)
        _exec(ssh, f"ls -l {remote_index}", check=False)

        _restart_backend_best_effort(ssh)
        print("✅ Deploy complete.")
        return 0
    finally:
        try:
            ssh.close()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())

