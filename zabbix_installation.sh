#!/bin/bash
#https://github.com/p1raya/zabbix_installer_script
#此脚本只能用于CentOS 7，全新安装Zabbix Server和Grafana。

#以下为软件安装预设信息，需在安装前修改好
#预设Zabbix数据库密码
DB_PASSWORD='Passw0rd'

#添加磁盘作为独立数据库分区（无需添加请置空）
DISK_MYSQL="/dev/sdb"

#是否在安装前更新系统？(Yes or No)
NEED_UPDATE=Yes

#是否添加时钟同步任务？(Yes or No)
NEED_NTP=Yes

#NTP服务器地址
NTP_SERVER="cn.pool.ntp.org"

#是否将DocumentRoot设置为Zabbix页面？(Yes or No)
NEED_DOCUMENTROOT=Yes

#是否安装企业微信报警功能？(Yes or No)
NEED_WECHAT=Yes
#企业微信应用信息（不安装请置空）
MYCORPID=""
MYSECRET=""
MYAGENTID="1"

#是否需要安装Grafana？(Yes or No):
NEED_GRAFANA=Yes

echo "开始安装..."

if [ -b "$DISK_MYSQL" ]; then
    #"配置数据库专用LVM卷"
    pvcreate -q $DISK_MYSQL
    vgcreate -q vg_zabbixdb $DISK_MYSQL
    free_pe=$(vgdisplay vg_zabbixdb | grep "Free" | awk '{print $5}')
    lvcreate -q -l $free_pe -n lv_mariadb vg_zabbixdb
    mkfs.xfs /dev/vg_zabbixdb/lv_mariadb > /dev/null
    mkdir /var/lib/mysql
    mount /dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql \
	&& echo "磁盘\"$DISK_MYSQL\"配置LVM并挂载完成"
    echo '/dev/mapper/vg_zabbixdb-lv_mariadb /var/lib/mysql xfs  defaults  0 0' >> /etc/fstab
fi

#配置软件源，安装所需软件
yum install -q -y epel-release
case $NEED_UPDATE in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        yum -q -y update && echo "系统更新完成"
        ;;
esac
echo "下载并安装 Zabbix 及相关依赖软件包"
yum install -q -y https://repo.zabbix.com/zabbix/4.0/rhel/7/x86_64/zabbix-release-4.0-1.el7.noarch.rpm
yum install -q -y mariadb-server zabbix-server-mysql zabbix-web-mysql zabbix-agent net-snmp net-snmp-utils ntp \
    && echo "Zabbix 软件包安装完成" || { echo "Zabbix 安装失败，请检查出错原因再重试。"; exit; }
echo -e "\n开始进行软件配置..."

{
#同步服务器时间
ntpdate $NTP_SERVER > /dev/null && echo "时钟同步完成"
case $NEED_NTP in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        #替换NTP Server地址，请按需自行修改或添加
        sed -i "s/centos.pool.ntp.org/$NTP_SERVER/" /etc/ntp.conf
        #开启ntpd服务
        /bin/systemctl -q enable ntpd.service
        /bin/systemctl -q start ntpd.service && echo "已启用 ntpd"
        ;;
esac
}&

{
#初始化数据库
#开启独立表空间
sed -i '/\[mysqld\]/a innodb_file_per_table=1' /etc/my.cnf
#启动mariadb数据库服务
/bin/systemctl -q start mariadb && echo "MariaDB 已启动"
#创建zabbix数据库
echo "create database zabbix character set utf8 collate utf8_bin;" | mysql -s -uroot
#创建zabbix用户，并设置权限和密码
echo "grant all privileges on zabbix.* to zabbix@localhost identified by '$DB_PASSWORD';" | mysql -s -uroot
#导入zabbix数据
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -s -uzabbix -p"$DB_PASSWORD" zabbix \
    && echo "Zabbix 数据库导入成功" || { echo "Zabbix 数据库导入失败，请检查原因再重试。"; exit; }

if [ -f "zabbix-mysql.sql" ]; then
    #zabbix数据表分区
    mysql -s -uzabbix -p"$DB_PASSWORD" zabbix < zabbix-mysql.sql
    mysql -s -uzabbix -p"$DB_PASSWORD" zabbix -e "CALL partition_maintenance_all('zabbix');" > /dev/null \
	&& echo "Zabbix 数据表分区完成"
    #添加定时维护任务
    echo "01 01 * * * mysql -uzabbix -p'$DB_PASSWORD' zabbix -e \"CALL partition_maintenance_all('zabbix');\"" >> /var/spool/cron/root
fi
}&

{
#修改Zabbix服务器配置（非*最优*配置，请按需要自行修改）
#修改数据库密码
sed -i "/^# DBPassword=/c DBPassword=$DB_PASSWORD" /etc/zabbix/zabbix_server.conf
#其它配置优化
sed -i '/^# StartPingers=/c StartPingers=4' /etc/zabbix/zabbix_server.conf \
    && grep "StartPingers=" /etc/zabbix/zabbix_server.conf
sed -i '/^# StartDiscoverers=/c StartDiscoverers=8' /etc/zabbix/zabbix_server.conf \
    && grep "StartDiscoverers=" /etc/zabbix/zabbix_server.conf
sed -i '/^# CacheSize=/c CacheSize=128M' /etc/zabbix/zabbix_server.conf \
    && grep "^CacheSize=" /etc/zabbix/zabbix_server.conf
sed -i '/^# CacheUpdateFrequency=/c CacheUpdateFrequency=120' /etc/zabbix/zabbix_server.conf \
    && grep "CacheUpdateFrequency=" /etc/zabbix/zabbix_server.conf
sed -i '/^# HistoryCacheSize=/c HistoryCacheSize=256M' /etc/zabbix/zabbix_server.conf \
    && grep "HistoryCacheSize=" /etc/zabbix/zabbix_server.conf
sed -i '/^# HistoryIndexCacheSize=/c HistoryIndexCacheSize=64M' /etc/zabbix/zabbix_server.conf \
    && grep "HistoryIndexCacheSize=" /etc/zabbix/zabbix_server.conf
sed -i '/^# TrendCacheSize=/c TrendCacheSize=64M' /etc/zabbix/zabbix_server.conf \
    && grep "TrendCacheSize=" /etc/zabbix/zabbix_server.conf
sed -i '/^# ValueCacheSize=/c ValueCacheSize=128M' /etc/zabbix/zabbix_server.conf \
    && grep "ValueCacheSize=" /etc/zabbix/zabbix_server.conf

#修改PHP配置
sed -i 's/memory_limit 128M/memory_limit 256M/' /etc/httpd/conf.d/zabbix.conf \
    && grep "php_value memory_limit " /etc/httpd/conf.d/zabbix.conf | sed -e 's/^\s*//'
sed -i 's/post_max_size 16M/post_max_size 32M/' /etc/httpd/conf.d/zabbix.conf \
    && grep "php_value post_max_size " /etc/httpd/conf.d/zabbix.conf | sed -e 's/^\s*//'
sed -i 's/upload_max_filesize 2M/upload_max_filesize 4M/' /etc/httpd/conf.d/zabbix.conf \
    && grep "php_value upload_max_filesize " /etc/httpd/conf.d/zabbix.conf | sed -e 's/^\s*//'
sed -i '/php_value date.timezone/c\        php_value date.timezone Asia\/Shanghai' /etc/httpd/conf.d/zabbix.conf \
    && grep "php_value date.timezone " /etc/httpd/conf.d/zabbix.conf | sed -e 's/^\s*//'

#修改SELINUX配置
#setsebool -P httpd_can_connect_zabbix on
setenforce 0 && echo "SELinux 已停用"
#设置"SELINUX=permissive"
sed -i -e 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config

#写入Zabbix配置文件"/etc/zabbix/web/zabbix.conf.php"
cat > /etc/zabbix/web/zabbix.conf.php <<EOF && echo "zabbix.conf.php 已写入"
<?php
// Zabbix GUI configuration file.
global \$DB;

\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '$DB_PASSWORD';

// Schema name. Used for IBM DB2 and PostgreSQL.
\$DB['SCHEMA'] = '';

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = '';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF

#修改DocumentRoot为Zabbix页面
case $NEED_DOCUMENTROOT in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        #'DocumentRoot "/usr/share/zabbix"'
        sed -i '/DocumentRoot "\/var\/www\/html"/c DocumentRoot "\/usr\/share\/zabbix"' /etc/httpd/conf/httpd.conf
        #'<Directory "/usr/share/zabbix">'
        sed -i '/<Directory "\/var\/www\/html">/c <Directory "\/usr\/share\/zabbix">' /etc/httpd/conf/httpd.conf
        ;;
esac

#防火墙放行服务端口
firewall-cmd -q --permanent --add-port=10050/tcp
firewall-cmd -q --permanent --add-port=10051/tcp
firewall-cmd -q --permanent --add-service=http
firewall-cmd -q --permanent --add-service=snmp

#设置服务开机启动
/bin/systemctl -q enable mariadb
/bin/systemctl -q enable httpd
/bin/systemctl -q enable zabbix-server
/bin/systemctl -q enable zabbix-agent
}&

{
#下载SourceHanSansCN字体
mkdir /usr/share/fonts/SourceHanSansCN
curl -s -o /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/SubsetOTF/CN/SourceHanSansCN-Normal.otf
ln -fs /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf /etc/alternatives/zabbix-web-font \
&& echo "Zabbix 图形字体修改为 SourceHanSansCN"
}&

{
case $NEED_WECHAT in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        #安装requests库
        yum install -q -y python-pip
        pip install -q requests
        pip install -q --upgrade requests
        #获取报警脚本
        curl -s -o /usr/lib/zabbix/alertscripts/wechat.py https://raw.githubusercontent.com/X-Mars/Zabbix-Alert-WeChat/master/wechat.py \
        && echo -e "微信报警脚本 wechat.py 已添加\n作者：火星小刘[https://github.com/X-Mars/Zabbix-Alert-WeChat]"
        sed -i "s/Corpid = \".*\"/Corpid = \"$MYCORPID\"/g" /usr/lib/zabbix/alertscripts/wechat.py
        sed -i "s/Secret = \".*\"/Secret = \"$MYSECRET\"/g" /usr/lib/zabbix/alertscripts/wechat.py
        sed -i "s/Agentid = \".*\"/Agentid = \"$MYAGENTID\"/g" /usr/lib/zabbix/alertscripts/wechat.py
        chmod +x /usr/lib/zabbix/alertscripts/wechat.py
        ;;
esac

case $NEED_GRAFANA in
    yes|Yes|YEs|YES|Y|y|ye|YE|Ye)
        #安装Grafana
        cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packagecloud.io/grafana/stable/el/7/\$basearch
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packagecloud.io/gpg.key https://grafanarel.s3.amazonaws.com/RPM-GPG-KEY-grafana
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        #国内YUM Repository方式安装可能会因为网络原因失败，可直接通过YUM直接下软件包安装（注意更新版本）
        #yum install -q -y https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-5.3.2-1.x86_64.rpm > /dev/null
        yum install -q -y grafana > /dev/null || { echo "Grafana 安装失败"; exit; }
        #安装Zabbix插件
        grafana-cli plugins install alexanderzobnin-zabbix-app > /dev/null && echo "Grafana 安装完成"
        #安装其它图形插件
        #grafana-cli plugins install grafana-piechart-panel > /dev/null
        #grafana-cli plugins install vonage-status-panel > /dev/null
        #防火墙放行端口TCP 3000
        firewall-cmd -q --permanent --add-port=3000/tcp
        #设置Grafana为开机启动
        /bin/systemctl -q enable grafana-server.service
        /bin/systemctl -q start grafana-server.service && echo "Grafana 已启动"
        ;;
esac
}&

wait

#启动服务
/bin/systemctl -q restart firewalld.service && echo "防火墙已放行服务端口"
/bin/systemctl -q start zabbix-server.service && echo "Zabbix Server 已启动"
/bin/systemctl -q start zabbix-agent.service && echo "Zabbix Agent 已启动"
/bin/systemctl -q start httpd.service && echo "Apache httpd 已启动"

echo "安装完毕！"
