# Setup Dropbear SSH for LUKS Unlock

This is a basic guide to help you setup an SSH server for remote unlock of LUKS full disk encryption on initramfs side.

NOTE: You need additional setup if you use Wi-Fi as main adapter for network conection.

Pre-requisites - private/public RSA/ECDSA SSH keypair.

## Debian/Ubuntu Based Distributions - LAN

```bash
sudo apt install dropbear-initramfs -y
# NOTE: Place your public key below:
echo "ssh-rsa AAAABXXXXXX id_luks_unlocker" | sudo tee -a /etc/dropbear/initramfs/authorized_keys
sudo chmod 600 /etc/dropbear/initramfs/authorized_keys
echo "DROPBEAR_OPTIONS=\"-I 600 -j -k -p 2222 -s\"" | sudo tee -a /etc/dropbear/initramfs/dropbear.conf
echo -e "IP=::::$(hostname)::dhcp:::" | sudo tee /etc/initramfs-tools/conf.d/dropbear
# NOTE: On every change, even SSH key you need to run this:
sudo update-initramfs -u -k all
# NOTE: Now you can reboot.
```

## Debian/Ubuntu Based Distributions - WLAN

1. Get your wifi interface name (ex. wlp0s20f3).
2. Get your Wi-Fi ESSID and password.
3. Find your used Wi-Fi modules (ex. iwlmvm, mac80211, iwlwifi, cfg80211 with `lsmod | grep iwl`).
4. Bash time:

```bash
sudo su
cd /opt
git clone https://github.com/fangfufu/wifi-on-debian-initramfs
cd wifi-on-debian-initramfs
cp wpa_supplicant.conf.example wpa_supplicant.conf
# NOTE: Add your Wi-Fi network credentials:
nano wpa_supplicant.conf
# NOTE: You might need to change the key_mgmt type based on your Wi-Fi security settings.
# NOTE: Add your wifi kernel modules in the correct order (lsmod | grep iw) to: 
nano /etc/initramfs-tools/modules
# Example:
# iwlmvm
# mac80211
# iwlwifi
# cfg80211
# NOTE: Now edit the Wi-Fi script to accomodate your interface name. Comment out INTERFACE= and add INTERFACE=wlp0s20f3
nano initramfs-tools/scripts/init-premount/01-enable-wireless
bash install.sh
sudo update-initramfs -u -k all
# NOTE: Now you can reboot.
```
