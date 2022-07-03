#!/bin/sh

fetch https://raw.githubusercontent.com/bcosden/opnsense-nva/master/2nic/config.xml
sed -i "" "s/yyy.yyy.yyy.yyy/10.1.4.1/" config.xml
sed -i "" "s/zzz.zzz.zzz.zzz/1.1.1.1\/32/" config.xml
cp config.xml /usr/local/etc/config.xml

fetch https://github.com/mihakralj/opnsense-theme-dark/raw/main/os-theme-dark-devel-0.1.txz
tar xvf os-theme-dark-devel-0.1.txz -C /
cp /usr/local/opnsense/www/themes/dark/build/css/DarkOrange.css /usr/local/opnsense/www/themes/dark/build/css/colors.css

# 1. Package to get root certificate bundle from the Mozilla Project (FreeBSD)
# 2. Install bash to support Azure Backup integration
env IGNORE_OSVERSION=yes
pkg bootstrap -f -y; pkg update -f
env ASSUME_ALWAYS_YES=YES pkg install ca_root_nss && pkg install -y bash

#Download OPNSense Bootstrap and Permit Root Remote Login
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in

sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#OPNSense
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in
sh ./opnsense-bootstrap.sh.in -y -r "22.1"

# Installing bash - This is a requirement for Azure custom Script extension to run
pkg install -y bash

# Remove wrong route at initialization
cat > /usr/local/etc/rc.syshook.d/start/22-remoteroute <<EOL
#!/bin/sh
route delete 168.63.129.16
EOL
chmod +x /usr/local/etc/rc.syshook.d/start/22-remoteroute

#Adds support to LB probe from IP 168.63.129.16
# Add Azure VIP on Arp table
echo # Add Azure Internal VIP >> /etc/rc.conf
echo static_arp_pairs=\"azvip\" >>  /etc/rc.conf
echo static_arp_azvip=\"168.63.129.16 12:34:56:78:9a:bc\" >> /etc/rc.conf
# Makes arp effective
service static_arp start
# To survive boots adding to OPNsense Autorun/Bootup:
echo service static_arp start >> /usr/local/etc/rc.syshook.d/start/20-freebsd
