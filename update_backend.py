#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import paramiko
from scp import SCPClient
import os
import sys
import io

# Устанавливаем UTF-8 для вывода
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

def deploy():
    server = "83.166.246.225"
    port = 22
    user = "root"
    password = "kcokmkzgHQ5dJOBF"
    
    # Путь к локальной папке бекенда
    backend_dir = "./бекенд"
    
    # Проверяем наличие файлов
    index_js = os.path.join(backend_dir, "index.js")
    package_json = os.path.join(backend_dir, "package.json")
    
    if not os.path.exists(index_js):
        print(f"ERROR: {index_js} not found")
        return
    
    if not os.path.exists(package_json):
        print(f"ERROR: {package_json} not found")
        return
    
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    print(f"Connecting to {server}...")
    try:
        ssh.connect(server, port, user, password, timeout=30)
        print("Connected successfully")
    except Exception as e:
        print(f"ERROR: Failed to connect: {e}")
        return
    
    # Создаем папку если её нет
    ssh.exec_command("mkdir -p /root/messenger/backend")
    
    try:
        with SCPClient(ssh.get_transport()) as scp:
            print("Uploading index.js and package.json...")
            # Загружаем основные файлы
            scp.put(index_js, "/root/messenger/backend/index.js")
            scp.put(package_json, "/root/messenger/backend/package.json")
            print("Files uploaded successfully")
    except Exception as e:
        print(f"ERROR uploading files: {e}")
        ssh.close()
        return
    
    print("Installing dependencies and restarting server...")
    # Установка зависимостей, затем перезапуск
    commands = [
        "cd /root/messenger/backend",
        "npm install express socket.io sqlite3 sqlite jsonwebtoken cors multer sms_ru bcrypt",
        "pm2 delete messenger-backend || true",
        "pm2 start index.js --name messenger-backend",
        "pm2 save",
        "sleep 2",
        "pm2 status",
        "pm2 logs messenger-backend --lines 10 --nostream"
    ]
    
    full_command = " && ".join(commands)
    stdin, stdout, stderr = ssh.exec_command(full_command)
    
    # Ждем завершения и выводим результат
    exit_status = stdout.channel.recv_exit_status()
    
    # Выводим вывод команды с правильной кодировкой
    try:
        output = stdout.read().decode('utf-8', errors='ignore')
        error_output = stderr.read().decode('utf-8', errors='ignore')
        print("=== Deployment Output ===")
        print(output)
        if error_output:
            print("=== Error Output ===")
            print(error_output)
    except Exception as e:
        print(f"Error reading output: {e}")
    
    if exit_status == 0:
        print("Deployment and restart complete successfully!")
    else:
        print(f"Error during deployment. Exit status: {exit_status}")

    ssh.close()

if __name__ == "__main__":
    deploy()
