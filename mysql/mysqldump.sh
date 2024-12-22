mysql_username=
mysql_password=
mysql_host=
back_path=/data/back/mysql/path
dbs=(
contract
)

#### backup database
for db in ${dbs[@]}
do
    echo "backup" $db
    mysqldump -h $mysql_host -P3306 -u $mysql_username -p$mysql_password -B $db > $back_path/$db.sql
done