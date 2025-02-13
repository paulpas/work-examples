#!/bin/bash
#
# Check if hardware RAID is in degraded state and send alerts
# Paul Pasika
# 07/31/2013
# paulpas@petabit.net
#

temp=`mktemp`
scriptname=`basename $0`

#Collect status 
/opt/dell/srvadmin/bin/omreport storage vdisk controller=0 > $temp

# Detect number of arrays and their ID
NumberRAIDVolumes=`grep -c ^ID $temp`

# Detect non-OK status
RAIDstatus=`grep Status $temp | grep -c Ok`

# RAIDstatus Ok should equal NumberRAIDVolumes
if (( $NumberRAIDVolumes != RAIDstatus ))
then
	# Print results and email to it@petabit.net
	cat $temp | mailx -s "ALERT: RAID Issue found on `hostname`. Immediate attention needed." it@petabit.net

	# Send to syslog
	echo ALERT: RAID Issue found on `hostname`. Immediate attention needed." | logger -t $scriptname
	cat $temp | logger -t $scriptname
fi


# Delete temp
rm -rf $temp
