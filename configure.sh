#!/bin/sh

fetch https://raw.githubusercontent.com/bcosden/opnsense-nva/master/config-1nic.xml
cp config-snic.xml /usr/local/etc/config.xml

# 1. Package to get root certificate bundle from the Mozilla Project (FreeBSD)
# 2. Install bash to support Azure Backup integration
env IGNORE_OSVERSION=yes
pkg bootstrap -f; pkg update -f
env ASSUME_ALWAYS_YES=YES pkg install ca_root_nss && pkg install -y bash

#Download OPNSense Bootstrap and Permit Root Remote Login
fetch https://raw.githubusercontent.com/opnsense/update/master/src/bootstrap/opnsense-bootstrap.sh.in

sed -i "" 's/#PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#OPNSense
sed -i "" "s/reboot/shutdown -r +1/g" opnsense-bootstrap.sh.in
sh ./opnsense-bootstrap.sh.in -y -r "22.1"

# Add Azure waagent
fetch https://github.com/Azure/WALinuxAgent/archive/refs/tags/v2.7.0.6.tar.gz
tar -xvzf v2.7.0.6.tar.gz
cd WALinuxAgent-2.7.0.6/
python3 setup.py install --register-service --lnx-distro=freebsd --force
cd ..

# Fix waagent by replacing configuration settings
ln -s /usr/local/bin/python3.8 /usr/local/bin/python
##sed -i "" 's/command_interpreter="python"/command_interpreter="python3"/' /etc/rc.d/waagent
##sed -i "" 's/#!\/usr\/bin\/env python/#!\/usr\/bin\/env python3/' /usr/local/sbin/waagent
sed -i "" 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/' /etc/waagent.conf
fetch $1actions_waagent.conf
cp actions_waagent.conf /usr/local/opnsense/service/conf/actions.d

# Installing bash - This is a requirement for Azure custom Script extension to run
sudo pkg install -y bash

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
