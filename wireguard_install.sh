#!/bin/bash
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))
}

wireguard_install() {
	#pacman -Syyu # can broke system :^
	pacman -Syy qrencode wireguard-arch wireguard-tools --needed --noconfirm
	echo net.ipv4.ip_forward = 1 >> /etc/sysctl.conf
	echo net.ipv4.icmp_echo_ignore_all = 1 >> /etc/sysctl.conf
	sysctl -p
	echo "1"> /proc/sys/net/ipv4/ip_forward
	echo "1" >  /proc/sys/net/ipv4/icmp_echo_ignore_all
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
	eth=$(ls /sys/class/net | awk '/^e/{print}' | tail -n 1) # change line if first adapter not connedted to internet

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
AllowedIPs = 192.168.100.2/32
EOF
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 192.168.100.2/32
DNS = 1.1.1.1


[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 21
EOF

	systemctl enable --now wg-quick@wg0
	content=$(cat /etc/wireguard/client.conf)
	echo "${content}" | qrencode -o - -t UTF8
}

add_user(){
    read -p "Name: " newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | tee temprikey | wg pubkey > tempubkey
    ipnum=$(grep Allowed /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = 192.168.100.$newnum\/24"'%' $newname.conf

cat >> /etc/wireguard/wg0.conf <<-EOF
[Peer]
PublicKey = $(cat tempubkey)
AllowedIPs = 192.168.100.$newnum/32
EOF
    wg set wg0 peer $(cat tempubkey) allowed-ips 192.168.100.$newnum/32
    rm -f temprikey tempubkey
    content=$(cat /etc/wireguard/$newname.conf)
    echo "${content}" | qrencode -o - -t UTF8
}


wireguard_remove() {
	systemctl stop wg-quick@wg0
	systemctl disable wg-quick@wg0
	pacman -Rnu wireguard-tools wireguard-arch --noconfirm
	rm -rf /etc/wireguard
}


help() {
	echo -e "----------------------- HELP MENU :3 -----------------------
./winreguard_install.sh install - Install wireguard server
./wireguard_install.sh remove - Remove Wireguard server
./wireguard_install.sh add -  For add user"
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

case "$1" in
	-h | --help | help)
		help
		;;
	--install | install)
		wireguard_install
		;;
	--remove | remove)
		wireguard_remove
		;;
	*)
		echo "invalid Command"
		help
		;;
esac
