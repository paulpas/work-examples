#!/bin/bash
#
# Check if hardware RAID is in degraded state and send alerts
# using sas2ircu
# Paul Pasika
# 07/31/2013
# paulpas@petabit.net
#
# Modified for sas2ircu
# Paul Pasika
# 4/14/2014
# paulpas@petabit.net

temp=`mktemp`
scriptname=`basename $0`

#Collect status
/usr/local/sbin/sas2ircu 0 display > $temp

# Detect number of arrays and their ID
NumberRAIDVolumes=`grep -c "Volume ID" $temp`

# Detect non-OK status
RAIDstatus=`grep "Status of volume" $temp | grep -c Okay`

# RAIDstatus Ok should equal NumberRAIDVolumes
if (( $NumberRAIDVolumes != RAIDstatus ))
then
        # Print results and email to it@citizensrx.com
        cat $temp | mailx -s "ALERT: RAID Issue found on `hostname`. Immediate attention needed." it@citizensrx.com

        # Send to syslog
        echo "ALERT: RAID Issue found on `hostname`. Immediate attention needed." | logger -t $scriptname
        cat $temp | logger -t $scriptname
fi


# Delete temp
rm -rf $temp
