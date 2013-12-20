#!/bin/bash
# Put Script in /etc/cron.weekly folder
# Install security updates automatically
# Be weary that Desktop OSs may break due to kernel/module mismatches
#
# Paul Pasika
# 09/23/2013
# paul@petabit.net
#

SCRIPTNAME=`basename $0`


# Copy the newest script to run in cron.weekly for the next run
if [ ! -f /etc/cron.weekly/$SCRIPTNAME ]
then
	cp -f /root/git/IT/scripts/$SCRIPTNAME /etc/cron.weekly/
fi
	

# Detect OS to populate the $NAME var
if [ -f /etc/os-release ]
then
	. /etc/os-release
else
	echo "The file /etc/os-release is not found.  Unable to detect OS version." | logger -t $SCRIPTNAME
	exit 1
fi

# To populate the $DISTRIB_CODENAME var
if [[ $NAME == "Ubuntu" ]] && [ -f /etc/lsb-release ]
then
	. /etc/lsb-release
elif [[ $NAME == "Debian GNU/Linux" ]]
then
	DISTRIB_CODENAME=`lsb_release -a 2>&1 | awk '/Codename/, awk {print $2}'`
fi

if [ -z $DISTRIB_CODENAME ]
then
	echo "$DISTRIB_CODENAME was NULL. No OS could be detected.  Aborting."  | logger -t $SCRIPTNAME
fi


grep $DISTRIB_CODENAME /etc/apt/sources.list | grep security > /etc/apt/secsrc.list
apt-get -o Dir::Etc::sourcelist="secsrc.list" -o Dir::Etc::sourceparts="-" update | logger -t $SCRIPTNAME
apt-get --assume-yes dist-upgrade 2>&1  | logger -t $SCRIPTNAME
apt-get --assume-yes autoremove | logger -t $SCRIPTNAME
