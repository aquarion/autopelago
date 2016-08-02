#!/bin/bash +x
#PASSWORD=$1 # Now using .my.cnf for password
LOC={{mysql_backup_location}}/$1

mkdir -p $LOC

mysql -u root -e 'show databases;' --skip-column-names --skip-pager | while read DATABASE; 
do 
	TMPFILE=`mktemp` || exit 1
	#echo $DATABASE;
	if [[ $DATABASE = performance_schema ]];
	then
		#echo "$DATABASE -eq performance_schema "
		continue;
	elif [[ $DATABASE = information_schema ]];
	then
		#echo "$DATABASE -eq information_schema"
		continue
	fi
	#aecho " ** $DATABASE";
	mysqldump --events -uroot $DATABASE > $TMPFILE
	bzip2 -c $TMPFILE > $LOC/$DATABASE.sql.bz2
	rm $TMPFILE
done;
