#!/bin/sh
#此脚本只能用于CentOS 7，全新安装Zabbix Server和Grafana。
#预设输入超时时间
timeout=120
#预设密码
passwd='Passw0rd'
#预设企业微信Corpid
Corpid='CCCCCCCCCCCCCCCCCC'
#预设企业应用Secret
Secret='SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS'
#预设企业应用Agentid
Agentid='1'

echo "0、配置数据库LVM卷[可选项]"
echo "请输入要添加的磁盘（如“sdb”）[直接按回车跳过]："
read -t $timeout -p "/dev/" disk
disk=${disk%\/}
disk='/dev/'${disk##*\/}
if [ -b "$disk" ]; then
    echo "pvcreate $disk"
    pvcreate $disk
    echo "vgcreate vg_zabbixdb $disk"
    vgcreate vg_zabbixdb $disk
    free_pe=$(vgdisplay vg_zabbixdb | grep "Free" | awk '{print $5}')
    echo "lvcreate -l $free_pe -n lv_mariadb vg_zabbixdb"
    lvcreate -l $free_pe -n lv_mariadb vg_zabbixdb
    unset free_pe
    echo "mkfs.xfs /dev/vg_zabbixdb/lv_mariadb"
    mkfs.xfs /dev/vg_zabbixdb/lv_mariadb
    echo "mkdir /var/lib/mysql"
    mkdir /var/lib/mysql
    echo "mount /dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql"
    mount /dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql
    echo '/dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql xfs  defaults  0 0' >> /etc/fstab
else
    echo "未指定有效磁盘设备，忽略添加数据库分区..."
fi
sleep 2
clear

echo "1、配置软件安装源，安装所需软件"
yum install -y epel-release
yum -y update
yum install -y http://repo.zabbix.com/zabbix/3.4/rhel/7/x86_64/zabbix-release-3.4-2.el7.noarch.rpm
yum install -y mariadb mariadb-server zabbix-server-mysql zabbix-web-mysql zabbix-agent
yum install -y python-pip net-snmp net-snmp-utils ntpdate wget

echo "同步服务器时间"
echo "ntpdate cn.pool.ntp.org"
ntpdate cn.pool.ntp.org
echo -n "添加定时同步时钟任务请按Y(yes): "
read -t $timeout need
case $need in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        echo "59 23 * * * ntpdate cn.pool.ntp.org"
        echo "59 23 * * * ntpdate cn.pool.ntp.org" >> /var/spool/cron/root
    ;;
    *)
    ;;
esac
sleep 1
clear

echo "2、初始化数据库"
echo "开启独立表空间"
echo "innodb_file_per_table=1"
sed -i '/\[mysqld\]/a innodb_file_per_table=1' /etc/my.cnf
echo "启动mariadb数据库服务"
systemctl start mariadb
echo "创建zabbix数据库"
echo "MariaDB > create database zabbix character set utf8 collate utf8_bin;"
echo "create database zabbix character set utf8 collate utf8_bin;" | mysql -uroot
echo "创建zabbix用户，并设置权限和密码"
echo "MariaDB > grant all privileges on zabbix.* to zabbix@localhost identified by 'password';"
echo "grant all privileges on zabbix.* to zabbix@localhost identified by '$passwd';" | mysql -uroot
echo "导入zabbix数据......"
echo "zcat /usr/share/doc/zabbix-server-mysql-3.4.*/create.sql.gz | mysql -uzabbix -p'password' zabbix"
zcat /usr/share/doc/zabbix-server-mysql-3.4.*/create.sql.gz | mysql -uzabbix -p"$passwd" zabbix

if [ -f "zabbix-mysql.sql" ]; then
    echo "zabbix数据表分区..."
    mysql -uzabbix -p"$passwd" zabbix < zabbix-mysql.sql
    mysql -uzabbix -p"$passwd" zabbix -e "CALL partition_maintenance_all('zabbix');"
    echo "添加定时维护任务..."
    echo "01 01 * * * mysql -uzabbix -p'password' zabbix -e \"CALL partition_maintenance_all('zabbix');\""
    echo "01 01 * * * mysql -uzabbix -p'$passwd' zabbix -e \"CALL partition_maintenance_all('zabbix');\"" >> /var/spool/cron/root
fi
sleep 1
clear

echo "3、修改Zabbix服务器配置"
echo "修改数据库密码"
sed -i "/^# DBPassword=/a DBPassword=$passwd" /etc/zabbix/zabbix_server.conf
echo "其它配置优化"
echo "StartPingers=4"
sed -i '/^# StartPingers=/a StartPingers=4' /etc/zabbix/zabbix_server.conf
echo "StartDiscoverers=8"
sed -i '/^# StartDiscoverers=/a StartDiscoverers=8' /etc/zabbix/zabbix_server.conf
echo "CacheSize=128M"
sed -i '/^# CacheSize=/a CacheSize=128M' /etc/zabbix/zabbix_server.conf
echo "CacheUpdateFrequency=120"
sed -i '/^# CacheUpdateFrequency=/a CacheUpdateFrequency=120' /etc/zabbix/zabbix_server.conf
echo "HistoryCacheSize=256M"
sed -i '/^# HistoryCacheSize=/a HistoryCacheSize=256M' /etc/zabbix/zabbix_server.conf
echo "HistoryIndexCacheSize=64M"
sed -i '/^# HistoryIndexCacheSize=/a HistoryIndexCacheSize=64M' /etc/zabbix/zabbix_server.conf
echo "TrendCacheSize=64M"
sed -i '/^# TrendCacheSize=/a TrendCacheSize=64M' /etc/zabbix/zabbix_server.conf
echo "ValueCacheSize=128M"
sed -i '/^# ValueCacheSize=/a ValueCacheSize=128M' /etc/zabbix/zabbix_server.conf

echo "修改PHP配置"
echo "php_value memory_limit 128M"
sed -i 's/memory_limit 128M/memory_limit 256M/' /etc/httpd/conf.d/zabbix.conf
echo "php_value post_max_size 32M"
sed -i 's/post_max_size 16M/post_max_size 32M/' /etc/httpd/conf.d/zabbix.conf
echo "php_value upload_max_filesize 4M"
sed -i 's/upload_max_filesize 2M/upload_max_filesize 4M/' /etc/httpd/conf.d/zabbix.conf
echo "php_value date.timezone Asia/Shanghai"
sed -i '/date.timezone/c\        php_value date.timezone Asia\/Shanghai' /etc/httpd/conf.d/zabbix.conf

echo "修改SELINUX配置"
#setsebool -P httpd_can_connect_zabbix on
echo "SELINUX=permissive"
setenforce 0
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

echo "写入Zabbix配置"
echo "/etc/zabbix/web/zabbix.conf.php"
cat > /etc/zabbix/web/zabbix.conf.php <<EOF
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '$passwd';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF

echo "修改DocumentRoot为Zabbix页面"
echo 'DocumentRoot "/usr/share/zabbix"'
sed -i '/DocumentRoot "\/var\/www\/html"/c DocumentRoot "\/usr\/share\/zabbix"' /etc/httpd/conf/httpd.conf
echo '<Directory "/usr/share/zabbix">'
sed -i '/<Directory "\/var\/www\/html">/c <Directory "\/usr\/share\/zabbix">' /etc/httpd/conf/httpd.conf

echo "防火墙放行服务端口"
echo "firewall-cmd  --permanent --add-port=10050/tcp"
firewall-cmd  --permanent --add-port=10050/tcp
echo "firewall-cmd  --permanent --add-port=10051/tcp"
firewall-cmd  --permanent --add-port=10051/tcp
echo "firewall-cmd  --permanent --add-service=http"
firewall-cmd  --permanent --add-service=http
echo "firewall-cmd  --permanent --add-service=snmp"
firewall-cmd  --permanent --add-service=snmp
systemctl restart firewalld

echo "修正Zabbix图形中文字体"
mkdir /usr/share/fonts/SourceHanSansCN
echo "下载SourceHanSansCN..."
wget -O /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/SubsetOTF/CN/SourceHanSansCN-Normal.otf
ln -fs /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf /etc/alternatives/zabbix-web-font

echo "启动服务"
echo "service httpd start"
service httpd start
echo "service zabbix-server start"
service zabbix-server start
echo "service zabbix-agent start"
service zabbix-agent start

echo "设置服务为开机启动"
echo "systemctl enable mariadb"
systemctl enable mariadb
echo "systemctl enable httpd"
systemctl enable httpd
echo "systemctl enable zabbix-server"
systemctl enable zabbix-server
echo "systemctl enable zabbix-agent"
systemctl enable zabbix-agent
sleep 1
clear

echo "4、添加微信报警脚本"
echo "安装requests"
pip install requests
pip install --upgrade requests
echo "下载报警脚本..."
wget -O /usr/lib/zabbix/alertscripts/wechat.py https://raw.githubusercontent.com/X-Mars/Zabbix-Alert-WeChat/master/wechat.py
echo "添加企业应用信息..."
read -t $timeout -p "请输入企业微信Corpid：" myCorpid
if [ ! $myCorpid ]; then
    myCorpid="$Corpid"
fi
sed -i "s/Corpid = \".*\"/Corpid = \"$myCorpid\"/g" /usr/lib/zabbix/alertscripts/wechat.py
read -t $timeout -p "请输入企业应用Secret：" mySecret
if [ ! $mySecret ]; then
    mySecret="$Secret"
fi
sed -i "s/Secret = \".*\"/Secret = \"$mySecret\"/g" /usr/lib/zabbix/alertscripts/wechat.py
read -t $timeout -p "请输入企业应用Agentid：" myAgentid
if [ ! $myAgentid ]; then
    myAgentid="$Agentid"
fi
sed -i "s/Agentid = \".*\"/Agentid = \"$myAgentid\"/g" /usr/lib/zabbix/alertscripts/wechat.py
echo "/usr/lib/zabbix/alertscripts/wechat.py"
chmod +x /usr/lib/zabbix/alertscripts/wechat.py
sleep 2
clear

echo "5、安装Grafana [可选项]"
echo -n "确认安装Grafana请按Y(yes): "
read -t $timeout need
case $need in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        yum install -y https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-4.5.1-1.x86_64.rpm
        echo "启动Grafana，并设置为开机启动"
        echo "systemctl start grafana-server"
        systemctl start grafana-server
        echo "systemctl enable grafana-server"
        systemctl enable grafana-server
        echo "安装Zabbix插件"
        echo "grafana-cli plugins install alexanderzobnin-zabbix-app"
        grafana-cli plugins install alexanderzobnin-zabbix-app
        echo "安装其它图形插件"
        echo "grafana-cli plugins install grafana-piechart-panel"
        grafana-cli plugins install grafana-piechart-panel
        echo "grafana-cli plugins install vonage-status-panel"
        grafana-cli plugins install vonage-status-panel
        systemctl restart grafana-server
        echo "防火墙放行"
        echo "firewall-cmd  --permanent --add-port=3000/tcp"
        firewall-cmd  --permanent --add-port=3000/tcp
        echo "systemctl restart firewalld"
        systemctl restart firewalld
    ;;
    *)
        echo "忽略Grafana安装..."
    ;;
esac

echo "安装完毕！"
