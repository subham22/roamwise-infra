#!/bin/bash
# Paste into: Create instance > Advanced options > Management > cloud-init script (roamwise-api)
# shared part; each VM's script appends its own .env lines
set -e
iptables -I INPUT 6 -p tcp -m multiport --dports 80,443,8080 -j ACCEPT
netfilter-persistent save
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
sudo -u ubuntu git clone -b oracle-migration https://github.com/subham22/roamwise-infra.git /home/ubuntu/roamwise-infra
cat > /home/ubuntu/roamwise-infra/.env <<ENV
COMPOSE_PROFILES=api
BACKEND_BIND=$(hostname -I | awk '{print $1}')
JAVA_OPTS=-Xmx320m -XX:+UseSerialGC -Xss512k -XX:MaxMetaspaceSize=160m
ENV
chown ubuntu:ubuntu /home/ubuntu/roamwise-infra/.env
touch /home/ubuntu/SETUP_DONE
