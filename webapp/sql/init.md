# mysqlのデータ初期化手順

$ sudo /etc/init.d/mysql stop
$ cd /var/lib
$ sudo rm -rf ./mysql
$ sudo mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql

$ sudo /etc/init.d/mysql start
$ mysql -uroot

> CREATE DATABASE isucon5q;
> exit

$ mysql -uroot isucon5q < SQL
