#!/bin/sh
echo "0、配置数据库分区[可选项]"
if [ -b "/dev/sdb" ]; then
    pvcreate /dev/sdb
    vgcreate vg_zabbixdb /dev/sdb
    free_pe=$(vgdisplay vg_zabbixdb | grep "Free" | awk '{print $5}')
    lvcreate -l $free_pe -n lv_mariadb vg_zabbixdb
    unset free_pe
    mkfs.xfs /dev/vg_zabbixdb/lv_mariadb
    mkdir /usr/lib/mysql
    mount /dev/vg_zabbixdb/lv_mariadb /usr/lib/mysql
    echo '/dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql xfs  defaults  0 0' >> /etc/fstab
fi
sleep 2
clear

echo "1、配置软件安装源，安装所需软件"
yum install -y epel-release
yum install -y http://repo.zabbix.com/zabbix/3.4/rhel/7/x86_64/zabbix-release-3.4-1.el7.centos.noarch.rpm
yum install -y zabbix-agent mariadb mariadb-server zabbix-server-mysql zabbix-web-mysql
yum install -y python-pip net-snmp net-snmp-utils ntpdate wget vim

echo "同步服务器时间"
ntpdate cn.pool.ntp.org
sleep 2
clear

echo "2、初始化数据库"
echo "开启独立表空间"
sed -i '/\[mysqld\]/a innodb_file_per_table=1' /etc/my.cnf
echo "启动mariadb数据库服务"
systemctl start mariadb
echo "创建zabbix数据库"
echo "create database zabbix character set utf8 collate utf8_bin;" | mysql -uroot
echo "创建zabbix用户，并设置权限和密码"
echo "grant all privileges on zabbix.* to zabbix@localhost identified by 'Passw0rd';" | mysql -uroot
echo "导入zabbix数据到新建的库中……"
zcat /usr/share/doc/zabbix-server-mysql-3.4.*/create.sql.gz | mysql -uzabbix -p'Passw0rd' zabbix
echo "zabbix数据导入完成。"
sleep 2

if [ -f "zabbix-mysql.sql" ]; then
    echo "zabbix数据表分区。"
    mysql -uzabbix -p'Passw0rd' zabbix < zabbix-mysql.sql
    mysql -uzabbix -p'Passw0rd' zabbix -e "CALL partition_maintenance_all('zabbix');"
    echo "01 01 * * * mysql -uzabbix -p'Passw0rd' zabbix -e \"CALL partition_maintenance_all('zabbix');\"" >> /var/spool/cron/root
fi
sleep 2
clear

echo "3、修改Zabbix服务器配置"
echo "修改数据库密码"
sed -i '/^# DBPassword=/a DBPassword=Passw0rd' /etc/zabbix/zabbix_server.conf
echo "其它配置优化"
sed -i '/^# StartPingers=/a StartPingers=4' /etc/zabbix/zabbix_server.conf
sed -i '/^# StartDiscoverers=/a StartDiscoverers=8' /etc/zabbix/zabbix_server.conf
sed -i '/^# CacheSize=/a CacheSize=128M' /etc/zabbix/zabbix_server.conf
sed -i '/^# CacheUpdateFrequency=/a CacheUpdateFrequency=120' /etc/zabbix/zabbix_server.conf
sed -i '/^# HistoryCacheSize=/a HistoryCacheSize=256M' /etc/zabbix/zabbix_server.conf
sed -i '/^# HistoryIndexCacheSize=/a HistoryIndexCacheSize=64M' /etc/zabbix/zabbix_server.conf
sed -i '/^# TrendCacheSize=/a TrendCacheSize=64M' /etc/zabbix/zabbix_server.conf
sed -i '/^# ValueCacheSize=/a ValueCacheSize=128M' /etc/zabbix/zabbix_server.conf

echo "写入Zabbix配置"
cat > /etc/zabbix/web/zabbix.conf.php <<EOF
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = 'Passw0rd';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF

echo "修改PHP时区"
sed -i '/date.timezone/c php_value date.timezone Asia\/Shanghai' /etc/httpd/conf.d/zabbix.conf

echo "修改SELINUX配置"
setsebool -P httpd_can_connect_zabbix on
setenforce 0
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

echo "修改DocumentRoot为Zabbix页面"
sed -i '/DocumentRoot "\/var\/www\/html"/c DocumentRoot "\/usr\/share\/zabbix"' /etc/httpd/conf/httpd.conf
sed -i '/<Directory "\/var\/www\/html">/c <Directory "\/usr\/share\/zabbix">' /etc/httpd/conf/httpd.conf

echo "防火墙放行服务端口"
firewall-cmd  --permanent --add-port=10050/tcp
firewall-cmd  --permanent --add-port=10051/tcp
firewall-cmd  --permanent --add-service=http
firewall-cmd  --permanent --add-service=snmp
systemctl restart firewalld

echo "修正Zabbix图片中文字体"
mkdir /usr/share/fonts/SourceHanSansCN
wget -O /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf https://github.com/adobe-fonts/source-han-sans/raw/release/SubsetOTF/CN/SourceHanSansCN-Normal.otf
ln -fs /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf /etc/alternatives/zabbix-web-font

echo "启动服务"
service httpd start
service zabbix-server start
service zabbix-agent start

echo "设置服务为开机启动"
systemctl enable mariadb
systemctl enable httpd
systemctl enable zabbix-server
systemctl enable zabbix-agent
sleep 2
clear

echo "4、添加微信报警脚本"
pip install requests
pip install --upgrade requests
wget -O /usr/lib/zabbix/alertscripts/wechat.py https://github.com/X-Mars/Zabbix-Alert-WeChat/raw/master/wechat.py
sed -i 's/Corpid = ".*"/Corpid = "**你的CORPID**"/g' /usr/lib/zabbix/alertscripts/wechat.py
sed -i 's/Secret = ".*"/Secret = "**你的Secret**"/g' /usr/lib/zabbix/alertscripts/wechat.py
sed -i 's/Agentid = ".*"/Agentid = "**你的Agentid**"/g' /usr/lib/zabbix/alertscripts/wechat.py
chmod +x /usr/lib/zabbix/alertscripts/wechat.py
sleep 2
clear

echo "5、安装Grafana"
yum install -y https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.4.3-1.x86_64.rpm
echo "启动Grafana，并设置为开机启动"
systemctl start grafana-server
systemctl enable grafana-server
echo "安装Zabbix插件"
grafana-cli plugins install alexanderzobnin-zabbix-app
echo "安装其它图形插件"
grafana-cli plugins install grafana-piechart-panel
grafana-cli plugins install vonage-status-panel
echo "防火墙放行"
firewall-cmd  --permanent --add-port=3000/tcp
systemctl restart firewalld
