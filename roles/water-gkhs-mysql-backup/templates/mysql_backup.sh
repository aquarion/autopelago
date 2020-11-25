#!/bin/bash +x
#PASSWORD=$1 # Now using .my.cnf for password
LOC={{ mysql_backup_location }}/$1

# Exit immediately if a pipeline returns non-zero.
# Short form: set -e
set -o errexit

# Print a helpful message if a pipeline with non-zero exit code causes the
# script to exit as described above.
trap 'echo "Aborting due to errexit on line $LINENO. Exit code: $?" >&2' ERR

# Allow the above trap be inherited by all functions in the script.
# Short form: set -E
set -o errtrace

# Return value of a pipeline is the value of the last (rightmost) command to
# exit with a non-zero status, or zero if all commands in the pipeline exit
# successfully.
set -o pipefail


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
