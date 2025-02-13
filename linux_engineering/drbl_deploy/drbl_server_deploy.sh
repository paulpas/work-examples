#!/bin/bash
# Make sure you're in the correct directory and all requirement directories are there
[ -d squid ] && [ -d skel ] || echo "Please enter the direcory that $0 is in" || exit 1

# Perform system upgrade
echo "to system update and reboot before proceeding!"
echo "apt-get -y update && apt-get -y dist-upgrade && reboot"
echo "Hit ctrl-C to abort and perform these steps immediately!"
echo "This message will self-destruct in 20 seconds"
echo
sleep 20
host=`hostname`

# NICs are set up as follows:
# eth0 XOVR
# eth1 LAN 
# eth2 WAN 

# Remove network-manager for manual network configuration
apt-get purge network-manager aqualung mplayer
echo "auto lo" > /etc/network/interfaces
echo "iface lo inet loopback" >> /etc/network/interfaces
echo >> /etc/network/interfaces


# Sets up eth0
function xover {
echo "auto $XOVReth" >> /etc/network/interfaces
echo "iface $XOVReth inet static" >> /etc/network/interfaces
echo "address $XOVRsubnet.$XOVRIP" >> /etc/network/interfaces
echo "broadcast $XOVRsubnet.255" >> /etc/network/interfaces
echo "netmask 255.255.255.0" >> /etc/network/interfaces
echo >> /etc/network/interfaces
}

# Sets up eth1
function lan {
echo "auto $LANeth" >> /etc/network/interfaces
echo "iface $LANeth inet static" >> /etc/network/interfaces
echo "address $LANsubnet.$LANIP" >> /etc/network/interfaces
echo "broadcast $LANsubnet.255" >> /etc/network/interfaces
echo "netmask 255.255.255.0" >> /etc/network/interfaces
echo >> /etc/network/interfaces
}

# Sets up eth2
function wan {
echo "auto $WANeth" >> /etc/network/interfaces
echo "iface $WANeth inet static" >> /etc/network/interfaces
echo "address $WANsubnet.$WANIP" >> /etc/network/interfaces
echo "broadcast $WANsubnet.255" >> /etc/network/interfaces
echo "netmask 255.255.255.0" >> /etc/network/interfaces
echo "gateway $WANsubnet.1" >> /etc/network/interfaces
}

# Sets up eth3
function voip {
echo "auto $WANeth" >> /etc/network/interfaces
echo "iface $WANeth inet dhcp" >> /etc/network/interfaces
# Add route to direct fonality traffic through voip LAN
echo "/sbin/route add -host 74.122.116.17 gw 10.10.10.1" >> /etc/rc.local
}

# Set up networking
if [[ $host == "drbl101" ]] # dev/lab
then
        LANeth=eth0
        LANsubnet=192.168.255
        LANIP=40
        WANeth=eth2
        WANsubnet=10.56.25
        WANIP=200
        lan
        wan
elif [[ $host == "drbl001" ]] # prod
then
	XOVReth=eth0
	XOVRsubnet=172.16.0
	XOVRIP=40
	LANeth=eth1
	LANsubnet=192.168.255
	LANIP=40
	WANeth=eth2
	WANsubnet=10.56.25
	WANIP=40
	xover
	lan
	wan
	voip
elif [[ $host == "drbl002" ]] # prod
then
	XOVReth=eth0
	XOVRsubnet=172.16.0
	XOVRIP=41
	LANeth=eth1
	LANsubnet=192.168.255
	LANIP=41
	WANeth=eth2
	WANsubnet=10.56.25
	WANIP=41
	xover
	lan
	wan
	voip
fi

# Set up resolv.conf
echo "domain tmxcredit.net" > /etc/resolv.conf
echo "search tmxcredit.net" >> /etc/resolv.conf
echo "nameserver 10.56.25.50" >> /etc/resolv.conf
echo "nameserver 10.56.25.51" >> /etc/resolv.conf

# Force read-only so drblpush scripts cannot overwrite
chattr +i /etc/resolv.conf

/etc/init.d/networking restart

# Copy default settings to /etc/skel
rsync -avz skel --delete /etc/

# install squid and ntp
apt-get -y install squid ntp

cp squid/squid.conf /etc/squid/

# Change Listen IP to the LAN IP
sed -i 's/qwertyuiop/'$LANsubnet.$LANIP'/' /etc/squid/squid.conf

# Copy blacklist to squid config directory
cp squid/domain_blacklist.acl /etc/squid/

# Install thunderbird ksnapshot and firefox
apt-get -y install thunderbird ksnapshot firefox

# Configure USB Headset to work consistently.  Set as default for audio
sed -i 's/defaults.ctl.card 0/defaults.ctl.card 1/;s/defaults.pcm.card 0/defaults.pcm.card 1/' /usr/share/alsa/alsa.conf

# install gdm
# Choose to use gdm as the login manager
apt-get -y install gdm

# Remove menu items on desktop
for i in gucharmap palimpsest lxterminal penguin-canfield penguin-freecell penguin-golf penguin-freecell penguin-golf penguin-mastermind penguin-merlin penguin-minesweeper penguin-pegged penguin-solitaire penguin-spider penguin-taipei penguin-taipei-editor penguin-thornq mtpaint simple-scan transmission-gtk osmo gnome-mplayer guvcview xfburn gdebi system-config-printer synaptic synaptic-kde hardinfo time update-manager users jockey-gtk palimpsest software-properties-gtk pidgin sylpheed abiword gnumeric audacious2 xfburn language-selector lxkeymap openjdk-6-java openjdk-7-java aqualung bluetooth-properties cheese manage-print-jobs pyNeighborhood users xarchiver xfburn
do
	echo "NoDisplay=true" >> /usr/share/applications/$i.desktop 
done


# Remove xsession options 
for i in `find /usr/share/xsessions/ -type f | grep -v Lubuntu.desktop`; do rm $i ; done

# autoconfigure removal of tbird and firefox lock files in case of an ungraceful reboot
echo "find /home/`whoami` -type f -name \".parentlock\" -exec rm -f {} \;" > /usr/local/bin/removelocks.sh
chown 755 /usr/local/bin/removelocks.sh
echo "/usr/local/bin/removelocks.sh" >>  /etc/xdg/lxsession/Lubuntu/autostart

# Remove language options
sed -i 's/keyboard=1/keyboard=0/g' /etc/alternatives/lxdm.conf

# disable update-manager popup
for i in `ls /home`
do
	su - $i gconftool -s --type bool /apps/update-notifier/auto_launch false
done

# Install Chrome v22+ for Livechat notifications
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
apt-get update
apt-get install google-chrome-stable

# Install Office suite and java plugins
apt-get install openoffice.org libreoffice openjdk* icedtea6*

# Remove jkd7 items - doesn't apply for 10.04LTS
#apt-get -y remove openjdk-7-demo openjdk-7-jdk openjdk-7-jre openjdk-7-jre-headless openjdk-7-jre-lib openjdk-7-jre-lib openjdk-7-dbg openjdk-7-doc openjdk-7-jre-zero openjdk-7-source icedtea-7-jre-jamvm 

### Install drbl
wget -q http://drbl.org/GPG-KEY-DRBL -O- | sudo apt-key add -

# Get ubuntu code name
ubuntucode=`grep CODENAME /etc/lsb-release | awk -F= '{print $2}'`

# Add drbl repos
echo "deb http://archive.ubuntu.com/ubuntu $ubuntucode main restricted universe multiverse" >> /etc/apt/sources.list
echo "deb http://drbl.sourceforge.net/drbl-core drbl stable" >> /etc/apt/sources.list

# Finally, do the install
apt-get update
apt-get -y install drbl #dhcp3-server tftpd-hpa


# Configure screen to 1280x1024
echo "Section \"Monitor\"" > /usr/lib/X11/xorg.conf.d/40-monitor.conf
echo "   Identifier	\"VGA1\"" >> /usr/lib/X11/xorg.conf.d/40-monitor.conf
echo "   Option		\"PreferredMode\" \"1280x1024\"" >> /usr/lib/X11/xorg.conf.d/40-monitor.conf
echo "EndSection" >> /usr/lib/X11/xorg.conf.d/40-monitor.conf

# install start menu icon
mv /usr/share/lubuntu/images/lubuntu-logo.png /usr/share/lubuntu/images/lubuntu-logo.png.orig

wget -O /usr/share/lubuntu/images/lubuntu-logo.png https://s3.amazonaws.com/uploads.hipchat.com/17374/73744/bbadg6dyunscv20/character.png

# configure drbl

# Install the network installation boot images - No
# Use serial console output on the client computer - No
# CPU acrhitecture - 2 (same as server)
# Do you want to upgrade the OS - No
# Pick kernel - 1 (from this DRBL server)
/opt/drbl/sbin/drblsrv -i


# DNS domain: drbl[001/002].tmxcredit.net
# set domain: Enter (drbl)
# client hostname prefix: callcenter
# Ethernet port for public internet access: eth2 (Airport)
# Collect MAC address of clients: N
# DHCP in DRBL to offer same IP: N
# Initial number to use in the last set of digits for client IPs 100
# Number of DRBL clients connected to the server: 154
# Final number in the client's IP is 31: Y
# DRBL mode: 1 (DRBL SSI)
# Clonezilla mode: 1 (Clonezilla box)
# Directory to store saved images: default (hit Enter)
# Use local drive (if exists) for swap: Y
# Max size for swap: default (1024 MB)
# Client mode: 1 (Graphic mode)
# Login mode: 0 (normal login)
# Set root password for clients instead of using server's password: N
# Set boot password for clients: N
# Set boot prompt for clients: N
# Use graphic mode for boot: Y (note: to switch to text mode run /opt/drbl/sbin/switch-pxe-bg-mode -m text)
# Add users to audio, video, USB device, etc groups: Y
# Setup public IP for clients: N
# Let DRBL clients have option to run terminal mode: N
# Let DRBL server run as a NAT server: Y
# Continue to deploy files: Y (firewall rules backed up as iptables.drblslave to sys config dir (/etc/sysconfig or /etc/default)); (The config file is saved as /etc/drbl/drblpush.conf. Therefore if you want to run drblpush with the same config again, you may run it as: /opt/drbl/sbin/drblpush -c /etc/drbl/drblpush.conf)
# turn on the ntp server for client by sudo /opt/drbl/sbin/drbl-client-service ntp on
#
# Note: The script will set up DHCP for both eth0 and eth1. 
# You must remove the config entries for eth0 in /etc/drbl/drblpush.conf and in /etc/dhcp3/dhcpd.conf !!!
#
/opt/drbl/sbin/drblpush -i

# Set up NFS server for UDP
sed -i 's/tcp/udp/' /etc/drbl/drbl_deploy.conf

# configure firewall, drbl doesn't do it the way we want
bash firewall/firewall.sh
iptables-save > /etc/default/drbl-nat.up.rules
chattr +i /etc/default/drbl-nat.up.rules
/etc/init.d/drbl-clients-nat restart

# reboot
echo "Done, now we will reboot in 10 seconds."
sleep 10
reboot
