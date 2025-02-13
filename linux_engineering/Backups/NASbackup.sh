#!/bin/bash 
# Script to do backups, then incremental backups.
# Paul Pasika
# paulpas@petabit.net
# 02/25/2013
#

RUNHOST=hostnameofbackupserver
HOME="/root"
DAYOFWEEK=`date +%a`
CRONUSER=root
SCRIPTUSER=$CRONUSER
SCRIPTNAME=`basename $0`
LOGDIR=/var/log
ECHO=/bin/echo
SSH=/usr/bin/ssh
RSYNC=/usr/bin/rsync
SSHOPTIONS="-f -o PasswordAuthentication=no -o StrictHostKeyChecking=no"

# Sets kernel to handle the high memory use for rsyncs
sysctl -w "vm.overcommit_ratio=90" 2>/dev/null
sysctl -w "vm.overcommit_memory=2" 2>/dev/null

# verify running on $RUNHOST
if [[ `hostname` != $RUNHOST ]]
then
        $ECHO "`date '+%c'` ERROR: Must be run on $RUNHOST, exiting." | logger -t $SCRIPTNAME
        exit 1
fi

# verify running as root
if [[ `whoami` != $SCRIPTUSER ]]
then
        $ECHO "`date '+%c'` ERROR: Running as user `whoami`, not $SCRIPTUSER, exiting." | logger -t $SCRIPTNAME
        exit 1
fi

# verify that script is not already running to avoid duplicates.  Log to syslog if this happens.
NUMPROCS=`ps -ef | grep -v grep | grep -v ssh | grep -v tail | grep -c $SCRIPTNAME`
if (( $NUMPROCS > 4 )) # I noticed three processes when running the script
then
        $ECHO "`date '+%c'` ERROR: $SCRIPTNAME is still running on $HOSTNAME, exiting." | logger -t $SCRIPTNAME
        exit 1
fi

# verify NFS shares exist
for mounts in /backups_prod /backups_xen /incremental_xen /incremental_backups /Corp /homes
do
	grep "$mounts" /proc/mounts &>/dev/null || ($ECHO "`date '+%c'` ERROR: The mount /export$mounts doesn't exist, exiting." | logger -t $SCRIPTNAME; exit 1)
done


SERVERLIST="steak eggs tool syslog001 dns001 dns002 drbl001"
DOMAINSUFFIX=petabit.net
# Todays date in ISO-8601 format:
DAY0=`date -I`
XenDAY0=`date -I`

# Yesterdays date in ISO-8601 format:
DAY1=`date -I -d "1 day ago"`
XenDAY1=`date -I -d "1 week ago"`

# The source directory:
CORPHOMESRCDIR="/export/Corp /export/homes"
SRC="/export/backups_prod/"
XenSRC="/export/backups_xen/"

# The target directory:
TRG="/export/incremental_backups/$DAY0"
XenTRG="/export/incremental_xen/$XenDAY0"

# The link destination directory:
LNK="/export/incremental_backups/$DAY1"
XenLNK="/export/incremental_xen/$XenDAY1"

# The incremental rsync options:
OPT="-a --delete --link-dest=$LNK --exclude=incremental_backups --exclude=xen --exclude=backups_xen --delete-excluded --exclude=logs"
XenOPT="-a --delete --link-dest=$XenLNK --exclude=incremental_backups --delete-excluded --exclude=logs"

# The Corp rsync backup options:
CORPOPT="-a --delete"

# Pull backups from servers
for i in $SERVERLIST
do
	$SSH $SSHOPTIONS root@$i.$DOMAINSUFFIX "/root/git/IT/scripts/tool_backup_scripts/server2NASbackups.sh 2>&1| logger -t server2NASbackups.sh" || echo "ERROR: Rsync Transfer error for $i." | logger -t $SCRIPTNAME
	if [[ $i == steak ]] || [[ $i == eggs ]]
	then
		if [[ $DAYOFWEEK == "Sun" ]]
		then
			$SSH $SSHOPTIONS root@$i.$DOMAINSUFFIX "bash -x /root/git/IT/scripts/tool_backup_scripts/Xenserver2NASbackups.sh 2>&1| logger -t Xenserver2NASbackups.sh" || echo "ERROR: Rsync Transfer error for $i." | logger -t $SCRIPTNAME
		fi
	fi
done

# Backup Corp and home shares to $SRC

for i in $CORPHOMESRCDIR
do
	(ionice -c3 $RSYNC $CORPOPT $i $SRC 2>&1 | logger -t $SCRIPTNAME ) || echo "Rsync transfer ERROR.  Aborted." | logger -t $SCRIPTNAME
done

# Execute the Incremental backup
sleep 5
while true
do
	if [[ `ps -ef | grep "ssh -f -o PasswordAuthentication=no -o StrictHostKeyChecking=no" | grep @ | grep -v grep | grep -c "tmxcredit.net"` != 0 ]]
	then
		sleep 5
	else
		$RSYNC $OPT $SRC $TRG 2>&1 | logger -t $SCRIPTNAME
		if [[ $DAYOFWEEK == "Sun" ]]
		then
			$RSYNC $XenOPT $XenSRC $XenTRG 2>&1 | logger -t $SCRIPTNAME
		fi
		break
	fi
done


# 15 days ago in ISO-8601 format
DAY29=`date -I -d "10 days ago"`
XenDAY29=`date -I -d "1 week ago"`

# Delete the backup from 29 days ago, if it exists
if [ -d /export/incremental_backups/$DAY29 ]
then
	rm -rf /export/incremental_backups/$DAY29
fi
# Delete the Xen backup from 1 week ago, if it exists
if [ -d /export/incremental_xen/$XenDAY29 ]
then
	rm -rf /export/incremental_xen/$XenDAY29
fi
