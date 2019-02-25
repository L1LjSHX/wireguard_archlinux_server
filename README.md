# Wireguard-install

**Support LTS(wireguard-lts)  and not official support kernels (wireguard-dkms, for Hardened and Zen kernel's too)**


First upgrade system & reboot
```
pacman -Syu
reboot
```
After download script
```
wget -q https://raw.githubusercontent.com/qusstem/wireguard_archlinux_server/master/wireguard_install.sh
```
Or just clone repo...
For install run:
```
chmod +x ./wireguard_install.sh install
```
For remove
```
./wireguard_install.sh remove
```
And add client
```
./wireguard_install.sh add
```
