#!/bin/bash
# server-side script to backup to NAS
# 02/11/2013
# Paul Pasika
# paulpas@petabit.net
#

HOME="/root"
DESTHOST=backupserver #.petabit.net will be assumed by servers
DESTUSER=root
DESTDIR=/export/backups_xen
CRONROOT=/var/spool/cron/crontabs
CRONUSER=root
SCRIPTUSER=$CRONUSER
SCRIPTROOT=/root/git/IT/scripts
SCRIPTNAME=`basename $0`
BAREMETALHOSTS='steak eggs'
SSHOPTIONS="-f -o PasswordAuthentication=no -o StrictHostKeyChecking=no"
TEMPDIR=`mktemp -d`
TARGETDIR=/xen
RSYNCOPTS=(-a --exclude-from $TEMPDIR/file.list -e 'ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no')

# Log script start
echo "Backups started on `date`." | logger -t $SCRIPTNAME

# verify that script is not already running to avoid duplicates.  Log to syslog if this happens.
NUMPROCS=`ps -ef | grep -v grep | grep -v ssh | grep -c $SCRIPTNAME`
if (( $NUMPROCS > 4 )) # I noticed two processes when running the script
then
	echo "ERROR: $SCRIPTNAME is still running on $HOSTNAME, exiting." | logger -t $SCRIPTNAME
	exit 1
fi

# verify running as root
if [[ `whoami` != $SCRIPTUSER ]]
then
	echo "ERROR: Running as user `whoami`, not $SCRIPTUSER, exiting." | logger -t $SCRIPTNAME
	exit 1
fi

# Verify that data resolve sand the domain tmxcredit.net is appended

host $DESTHOST &>/dev/null
HOSTSTATUS=$?

if (( $HOSTSTATUS != 0 ))
then
	echo "ERROR: Cannot resolve $DESTHOST, exiting." | logger -t $SCRIPTNAME
	exit 1
fi

# verify that keyless ssh worked

ssh -l $DESTUSER $SSHOPTIONS $DESTHOST exit
SSHSTATUS=$?

if (( $SSHSTATUS == 0 ))
then
	echo "STATUS: SSH Passwordless Authentication succeeded for $HOSTNAME to $DESTHOST." | logger -t $SCRIPTNAME
else
	echo "ERROR: SSH Passwordless Authentication failed for $HOSTNAME to $DESTHOST, exiting." | logger -t $SCRIPTNAME
	exit 1
fi

# verify hostname directory on NAS exists, if not create

ssh -l $DESTUSER $DESTHOST ls $DESTDIR/$HOSTNAME &>/dev/null
SSHDIRSTATUS=$?

if (( $SSHDIRSTATUS != 0 ))
then
	ssh -l $DESTUSER $DESTHOST mkdir $DESTDIR/$HOSTNAME &>/dev/null
	SSHMAKEDIRSTATUS=$?
	if (( $SSHMAKEDIRSTATUS != 0 ))
	then
		echo "ERROR: Failed to find and/or create directory $DESTDIR/$HOSTNAME, exiting." | logger -t $SCRIPTNAME
	fi
fi

# verify files transferred over by echoing date into a text file on server
rm -f /xen/$SCRIPTNAME.tmp
TMPCONTENT=$RANDOM
echo "$TMPCONTENT" > /xen/$SCRIPTNAME.tmp 

# rsync files, log time to run to syslog
# Old Bulk way, rsync randomly dies with no cause, I blame QNAP.
#ionice -c3 rsync -a --progress --delete -e 'ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no' $TARGETDIR $DESTUSER@$DESTHOST:$DESTDIR/$HOSTNAME 2>&1 | logger -t $SCRIPTNAME

# The new multiple file method
for i in `ls /xen/`
do
(ionice -c3 rsync -a --delete -e 'ssh -o PasswordAuthentication=no -o StrictHostKeyChecking=no' $TARGETDIR/$i $DESTUSER@$DESTHOST:$DESTDIR/$HOSTNAME/xen/ 2>&1 | logger -t $SCRIPTNAME )|| echo "ERROR: Rsync Transfer error for $i." | logger -t $SCRIPTNAME
done

# verifying rsync transferred backup file with $TMPCONTENT within on the NAS

ssh $SSHOPTIONS $DESTUSER@$DESTHOST grep $TMPCONTENT $DESTDIR/$HOSTNAME/$SCRIPTNAME.tmp &>/dev/null
SSHSTATUS=$?

if (( $SSHSTATUS == 0 ))
then
	echo "STATUS: Backups Verification: $DESTDIR/$HOSTNAME/$SCRIPTNAME.tmp transferred successfully and verified." | logger -t $SCRIPTNAME
else
	echo "ERROR: Backups Verification: Verify of $DESTDIR/$HOSTNAME/$SCRIPTNAME.tmp failed, backup may be invalid!" | logger -t $SCRIPTNAME
fi

# Remove temp file
rm /xen/$SCRIPTNAME.tmp

# Log script end
echo "Backups ended on `date`." | logger -t $SCRIPTNAME

exit 0
