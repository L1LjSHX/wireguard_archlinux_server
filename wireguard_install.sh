#!/bin/bash
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))
}

wireguard_install() {
	pacman -S wireguard-arch wireguard-tools --needed --noconfirm
	echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
	sysctl -p
	echo "1"> /proc/sys/net/ipv4/ip_forward
	mkdir /etc/wireguard
	cd /etc/wireguard
	wg genkey | tee sprivatekey | wg pubkey > spublickey
	wg genkey | tee cprivatekey | wg pubkey > cpublickey
	s1=$(cat sprivatekey)
	s2=$(cat spublickey)
	c1=$(cat cprivatekey)
	c2=$(cat cpublickey)
	serverip=$(curl ipv4.icanhazip.com)
	port=$(rand 10000 60000)
	eth=$(ls /sys/class/net | awk '/^e/{print}')

cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
SaveConfig = true
Address = 192.168.100.1/24
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = $port
DNS = 1.1.1.1


[Peer]
PublicKey = $c2
AllowedIPs = 10.0.0.2/32
EOF
	systemctl enable --now wg-quick@wg0
}

