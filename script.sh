#!/bin/bash
set -e

HOST="ha-prx01"
IP_ADDR="10.1.20.21"
IP6_ADDR="2001:db8:1001:20::21"
PRIORITY="100" # Для ha-prx02 измените на 90

echo "==> Настройка $HOST..."
hostnamectl set-hostname $HOST.dmz.ws.kz
timedatectl set-timezone Asia/Almaty
apt-get update -y
export DEBIAN_FRONTEND=noninteractive
apt-get install -y locales keepalived haproxy

sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

echo "==> Настройка сети..."
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ens3
iface ens3 inet static
    address $IP_ADDR/24
    gateway 10.1.20.1
iface ens3 inet6 static
    address $IP6_ADDR/64
    gateway 2001:db8:1001:20::1
EOF
systemctl restart networking || true

echo "==> Настройка Keepalived (VRRP VIP)..."
cat <<EOF > /etc/keepalived/keepalived.conf
vrrp_instance VI_1 {
    state MASTER
    interface ens3
    virtual_router_id 51
    priority $PRIORITY
    virtual_ipaddress {
        10.1.20.20/24
        2001:db8:1001:20::20/64
    }
}
EOF
systemctl restart keepalived

echo "==> Настройка HAProxy..."
cat <<EOF > /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend http_front
    bind *:80
    default_backend web_servers

backend web_servers
    balance roundrobin
    server web01 10.1.20.31:80 check
    server web02 10.1.20.32:80 check
EOF
systemctl restart haproxy

echo "==> Готово! $HOST настроен."
