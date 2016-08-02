#!/bin/bash +x
#PASSWORD=$1 # Now using .my.cnf for password
LOC={{mysql_backup_location}}/$1

mkdir -p $LOC

mysql -u root -e 'show databases;' --skip-column-names --skip-pager | while read DATABASE; 
do 
	TMPFILE=`mktemp` || exit 1
	echo "$DATABASE";
	if [[ $DATABASE = performance_schema ]];
	then
		echo ">> $DATABASE skipped: performance_schema "
		continue;
	elif [[ $DATABASE = information_schema ]];
	then
		echo ">> $DATABASE skipped: information_schema "
		#echo "$DATABASE -eq information_schema"
		continue
	fi
	echo ">> Dump...";
	mysqldump --events -uroot $DATABASE > $TMPFILE
	echo ">> Squeeze...";
	bzip2 -c $TMPFILE > $LOC/$DATABASE.sql.bz2
	echo ">> Clean...";
	rm $TMPFILE
	echo ">> $LOC/$DATABASE.sql.bz2"
done | ts;
