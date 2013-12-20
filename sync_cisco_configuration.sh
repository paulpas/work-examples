#!/bin/bash
# Author:  Paul Pasika 
# EMail: paul@petabit.net
# Date: 10.08.2012
#
# Pulls configs from networking equipment and pushes to git
#

hosts="metallica megadeth switch cisco10 cisco10repeater"
uname=scripter
passwd=cleartextpassword
gitrepo="/root/git/IT"
destination="/root/git/IT/networking/configs"

cd $gitrepo
git pull 2>&1 | logger -t `basename $0`

for i in $hosts
do

/usr/bin/expect << EOF > $destination/$i
 
spawn ssh -l $uname $i
set timeout 10
expect "assword:"
send -- "$passwd\r"
expect "#"
send -- "terminal length 0\r"
expect "#"
set timeout 60
send -- "sh run\r"
expect "#"
send -- "exit\r"
EOF

sed -i '/^$/d;/\#/d;/scripter/d;/Password:/d;/Building configuration/d' $destination/$i
#sed -i '/\! Last/d;/\! NVRAM/d;/^[[:space:]]/d;/\#/d;/scripter/d;/Password:/d;/Building configuration/d' $destination/$i
awk '/Current/{i++}i' $destination/$i > /tmp/$i
mv /tmp/$i $destination/$i

git add $destination/$i 2>&1 | logger -t `basename $0`
done

git commit -m "Router configs `date`" 2>&1 | logger -t `basename $0`
git push 2>&1 | logger -t `basename $0`
