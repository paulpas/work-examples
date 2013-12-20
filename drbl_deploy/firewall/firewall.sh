#!/bin/bash

IPTABLES="/sbin/iptables"

WANeth=eth2
LANeth=eth1
LANIP=`grep -A1 $LANeth /etc/network/interfaces | awk '/address/ {print $2}'`

#
# Configure default policies (-P), meaning default rule to apply if no
# more specific rule below is applicable.  These rules apply if a more specific rule below
# is not applicable.  Defaults are to DROP anything sent to firewall or internal
# network, permit anything going out.
#

# Flush
$IPTABLES -F
$IPTABLES -X
$IPTABLES -F -t nat
$IPTABLES -X -t nat


#
# Forward all packets from eth1 (internal network) to eth2 (the internet).
#
iptables -A FORWARD -i $LANeth -o $WANeth -j ACCEPT

#
# Forward packets that are part of existing and related connections from eth2 to eth1.
#
iptables -A FORWARD -i $WANeth -o $LANeth -m state --state ESTABLISHED,RELATED -j ACCEPT

#
# Permit packets in to firewall itself that are part of existing and related connections.
#
iptables -A INPUT -i $WANeth -m state --state ESTABLISHED,RELATED -j ACCEPT

# Note, in the above two rules, a connection becomes ESTABLISHED in the
# iptables PREROUTING chain upon receipt of a SYNACK packet that is a
# response to a previously sent SYN packet. The SYNACK packet itself is
# considered to be part of the established connection, so no special
# rule is needed to allow the SYNACK packet itself.

#
# Allow all inputs to firewall from the internal network and local interfaces
#
iptables -A INPUT -i $LANeth -s 0/0 -d 0/0 -j ACCEPT
iptables -A INPUT -i lo -s 0/0 -d 0/0 -j ACCEPT

#  MASQUERADE
#
iptables -A POSTROUTING -t nat -o $WANeth -j MASQUERADE

#
# Deny any packet coming in on the public internet interface eth2
# which has a spoofed source address from our local networks:
#
iptables -A INPUT -i $WANeth -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i $WANeth -s 172.16.0.0/12 -j DROP
iptables -A INPUT -i $WANeth -s 192.168.0.0/16 -j DROP
iptables -A INPUT -i $WANeth -s 127.0.0.0/8 -j DROP

#
# Accept all tcp SYN packets for protocols SMTP, HTTP, HTTPS, and SSH:
# (SMTP connections are further audited by our SMTP server)
#
#iptables -A INPUT -p tcp -s 0/0 -d x.y.z.m/32 --destination-port 25 --syn -j ACCEPT
iptables -A INPUT -p tcp -s 0/0 -d 0/0 --destination-port 80 --syn -j ACCEPT
iptables -A INPUT -p tcp -s 0/0 -d 0/0 --destination-port 443 --syn -j ACCEPT
iptables -A INPUT -p tcp -s 0/0 -d 0/0 --destination-port 22 --syn -j ACCEPT
# may need to add twinkle stuff here

#
# Finally, DENY all connection requests to any UDP port not yet provided
# for and all SYN connection requests to any TCP port not yet provided
# for.  Using DENY instead of REJECT means that no 'ICMP port
# unreachable' response is sent back to the client attempting to
# connect.  I.e., DENY just ignores connection attempts.  Hence, use of
# DENY causes UDP connection requests to time out and TCP connection
# requests to hang.  Hence, using DENY instead of REJECT may have
# the effect of frustrating attackers due to increasing the amount of
# time taken to probe ports.
#
# Note that there is a fundamental difference between UDP and TCP
# protocols.  With UDP, there is no 'successful connection' response.
# With TCP, there is.  So an attacking client will be left in the dark
# about whether or not the denied UDP packets arrived and will hang
# waiting for a response from denied TCP ports.  An attacker will not
# be able to immediately tell if UDP connection requests are simply
# taking a long time, if there is a problem with connectivity between
# the attacking client and the server, or if the packets are being
# ignored.  This increases the amount of time it takes for an attacker
# to scan all UDP ports.  Similarly, TCP connection requests to denied
# ports will hang for a long time.  By using REJECT instead of DENY, you
# would prevent access to a port in a more 'polite' manner, but give out
# more information to wannabe attackers, since the attacker can positively
# detect that a port is not accessible in a small amount of time from
# the 'ICMP port unreachable' response.

iptables -A INPUT -s 0/0 -d 0/0 -p udp -j DROP
iptables -A INPUT -s 0/0 -d 0/0 -p tcp --syn -j DROP

# Get IP for kronos
kronos=`host tmtime.titlemax.biz | awk '{print $NF}'`

# Allow ICMP
iptables -A INPUT -p icmp --icmp-type 8 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p icmp --icmp-type 0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow Hobbit from these IPs
$IPTABLES -A INPUT -s 10.56.25.1/24 -m state --state NEW -m tcp -p tcp --dport 1984 -j ACCEPT
# Allow SSH from these IPs
$IPTABLES -A INPUT -s 10.56.25.1/24 -m state --state NEW -m tcp -p tcp --dport 22 -j ACCEPT
# Allow Kronos
$IPTABLES -t nat -A PREROUTING -p tcp -m tcp -i $LANeth --dport 443 -j DNAT --to-destination $kronos


# pop redirect
$IPTABLES -t nat -A PREROUTING -i $LANeth -p tcp -m tcp --dport 995 -j DNAT --to-destination 64.78.56.45:995
# imap redirect
$IPTABLES -t nat -A PREROUTING -i $LANeth -p tcp -m tcp --dport 993 -j DNAT --to-destination 64.78.56.45:993
# smtp tls redirect
$IPTABLES -t nat -A PREROUTING -i $LANeth -p tcp -m tcp --dport 465 -j DNAT --to-destination 64.78.56.45:465
$IPTABLES -t nat -A PREROUTING -i $LANeth -p tcp -m tcp --dport 25 -j DNAT --to-destination 64.78.56.45:25

# Squid transparent proxy
$IPTABLES -t nat -A PREROUTING -i $LANeth -p tcp -m tcp --dport 80 -j DNAT --to-destination $LANIP:6969
# Log
$IPTABLES -A INPUT -j LOG
$IPTABLES -A INPUT -j DROP
