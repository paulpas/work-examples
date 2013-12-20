#!/bin/sh
#
# Script to query database and parse output for emails
# SQL is out of scope for this script
# Paul Pasika
# 03/21/2013
#


logname=`basename $0`
today="`date +%Y%m%d_%H`"

# Sender address
email_to="supervisors@petabit.net"

# error log
errortmp=/tmp/$logname.error.log
cat /dev/null > $errortmp
errorlog="$HOME/reports/log/$logname.error.log"

# tmp file
temp=`mktemp`

# Location of sql to run
sqlfile="$HOME/reports/tmx_credit/application_status_changes.sql"

# DB config
requiresuser=dbreporting
dbuser=reporter
dbenv=prod
export PGPASSWORD='xxxxxxxxxx'

if [[ $dbenv == "prod" ]]
then
	dbhost=petabit-psql-production-master
	db=petabit_production
elif [[ $dbenv == "dev" ]]
then
	dbhost=petabit-psql-development-master
	db=petabit_development
fi
# End DB config

# Email top
function email_top {
echo '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">' >> $temp
echo '<html>' >> $temp
echo '<head><title></title>' >> $temp
echo '</head>' >> $temp
echo '<body>' >> $temp
echo '<font face="Courier New" size=2>' >> $temp
echo '<pre>' >> $temp
}

# Email middle
function psqlexe {
	date >> $temp
	psql -d $db -h $dbhost -f $sqlfile -q -U $dbuser -F , >> $temp 2>> $errortmp
	if [ -s $errortmp ]
	then
		cat $errortmp | mailx -s "$logname errors" it@petabit.net
	fi
		cat $errortmp | while read xx
		do
			echo "`date` $xx" >> $errorlog
			echo "" >> $errorlog
		done
	rm -f $errortmp
	(egrep "\(0 rows\)|\(No rows\)" $temp >/dev/null && rm -rf $temp) && exit 1
}

# Email bottom
function email_bottom {
echo '</pre>' >> $temp
echo '</font>' >> $temp
echo '</body>' >> $temp
echo '</html>' >> $temp
}


function mailer {
	cat $temp | mailx -a "MIME-Version: 1.0"  -a "Content-Type: text/html" -s "Application Status Changes Report" $email_to
}

email_top
psqlexe 
email_bottom
mailer
rm -f $temp
