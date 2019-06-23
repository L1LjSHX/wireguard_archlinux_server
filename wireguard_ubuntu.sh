#!/bin/bash
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))
}

upload() {
	passwordArchive=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c 20; echo)
	7z a /tmp/test.zip -p"$passwordArchive" /etc/wireguard/clients/$1.conf > /dev/null
	rawdata=$(curl -s -F "file=@/tmp/test.zip" https://anonfiles.com/api/upload)
	echo -e "------------------------------ File url's ------------------------------
Short url: $(echo $rawdata | jq '.data.file.url.short')
Full url: $(echo $rawdata | jq '.data.file.url.full')
Archive Passsword: $passwordArchive"
	rm /tmp/test.zip
}

wireguard_install() {
	apt install software-properties-common -y
	add-apt-repository ppa:wireguard/wireguard -y
	apt update
	apt install curl p7zip-full resolvconf qrencode wireguard-dkms wireguard-tools jq tmux -y
	mkdir -p /etc/wireguard/certs
	cd /etc/wireguard/certs
	wg genkey | tee sprivatekey | wg pubkey > spublickey
	wg genkey | tee cprivatekey | wg pubkey > cpublickey
	s1=$(cat sprivatekey)
	s2=$(cat spublickey)
	c1=$(cat cprivatekey)
	c2=$(cat cpublickey)
	serverip=$(curl -s ipv4.icanhazip.com)
	port=$(rand 10000 60000)
	eth=$(ls /sys/class/net | awk '/^e/{print}' | tail -n 1) # change line if first adapter not connedted to internet
	############### SYSCTL ######################
	if [ ! -z /etc/sysctl.d/99-sysctl.conf ]
		echo "move 99-sysctl.conf  /etc/sysctl.d/99-sysctl.conf.backupW"
		mv /etc/sysctl.d/99-sysctl.conf /etc/sysctl.d/99-sysctl.conf.backupW
	then
	fi
cat > /etc/sysctl.d/99-sysctl.conf  <<-EOF
#### https://wiki.archlinux.org/index.php/sysctl
net.ipv4.ip_forward = 1 # ip4 forwarding
net.ipv4.icmp_echo_ignore_all = 1 # block pind
net.core.rmem_max = 4194304 
net.core.wmem_max = 1048576
net.core.somaxconn = 1024 # Increase the maximum connections
net.ipv4.tcp_slow_start_after_idle = 0 # Disable TCP slow start on idle connections
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 1048576 2097152
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.tcp_fastopen = 3 # default 1
net.ipv4.tcp_mtu_probing = 1

EOF
	sysctl -p

	################ WIREGUARD CONFIG FILE #################
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
mkdir -p /etc/wireguard/clients
cat > /etc/wireguard/clients/client.conf <<-EOF
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
	content=$(cat /etc/wireguard/clients/client.conf)
	echo "${content}" | qrencode -o - -t UTF8
	upload client
}

add_user(){
    read -p "Set Client Name: " newname
    if [ -f /etc/wireguard/clients/$newname.conf ]
    	then
	    read -p "File config exists, do you want generate qr code? y/n : " question
	    if [ "$question" == "y" ]
	    then
		content=$(cat /etc/wireguard/clients/$newname.conf)
		echo "${content}" | qrencode -o - -t UTF8
		upload $newname
		exit
	    elif [ "$question" == "n" ]
	    then
			echo "good by"
			exit
	    else
			echo "error invalid argument..."
			exit
		fi
	fi

    cd /etc/wireguard/clients
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
    content=$(cat /etc/wireguard/clients/$newname.conf)
    echo "${content}" | qrencode -o - -t UTF8
    upload $newname
}


wireguard_remove() {
	systemctl stop wg-quick@wg0
	systemctl disable wg-quick@wg0
	apt remove wireguard-tools wireguard-dkms -y
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
	--add | add | adduser)
		add_user
		;;
	*)
		echo "invalid Command"
		help
		;;
esac
