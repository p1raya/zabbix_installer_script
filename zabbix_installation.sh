#!/bin/bash
# https://github.com/p1raya/zabbix_installer_script
#此脚本适用于 CentOS 8 全新安装Zabbix Server和Grafana。
#不同发行版的安装方法类似，可按需自行修改。

#===以下为软件安装预设信息，需在安装前修改好===
#预设Zabbix数据库密码
DB_PASSWORD='Passw0rd'

#添加磁盘作为独立数据库分区（无需添加请置空）
DISK_MYSQL="/dev/sdb"

#是否在安装前更新系统？(Yes or No)
NEED_UPDATE=Yes

#指定Nginx server_name，默认使用IP地址
#SERVER_NAME=example.com

#是否安装企业微信报警功能？(Yes or No)
NEED_WECHAT=Yes
#企业微信应用信息（自行补充）
MYCORPID="***Your Id***"
MYSECRET="***Your Secret***"
MYAGENTID="1"

#是否需要安装 Grafana？(Yes or No):
NEED_GRAFANA=Yes


echo "开始安装..."

if [ -b "$DISK_MYSQL" ]; then
    #"配置数据库专用 LVM 卷"
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
echo -e "\n开始进行软件安装..."
yum install -q -y https://repo.zabbix.com/zabbix/4.3/rhel/8/x86_64/zabbix-release-4.3-3.el8.noarch.rpm
yum install -q -y epel-release
case $NEED_UPDATE in
    yes|Yes|YEs|YES|Y|y)
        yum -q -y update && echo "系统更新完成"
        ;;
esac
echo "安装 Zabbix 服务及相关依赖软件包"
yum install -q -y mariadb-server zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-agent net-snmp net-snmp-utils\
    && echo "Zabbix 软件包安装完成" || { echo "Zabbix 安装失败，请检查出错原因再重试。"; exit; }
echo -e "\n开始进行软件配置..."

{
#初始化数据库
#启动 mariadb 服务
/bin/systemctl -q start mariadb && echo "MariaDB 已启动"
#创建zabbix数据库
echo "create database zabbix character set utf8 collate utf8_bin;" | mysql -s -uroot
#创建zabbix用户，并设置权限和密码
echo "grant all privileges on zabbix.* to zabbix@localhost identified by '$DB_PASSWORD';" | mysql -s -uroot
#导入zabbix数据
zcat /usr/share/doc/zabbix-server-mysql*/create.sql.gz | mysql -s -uzabbix -p"$DB_PASSWORD" zabbix \
    && echo "Zabbix 数据库导入成功" || { echo "Zabbix 数据库导入失败，请检查原因再重试。"; exit; }

#zabbix数据表分区
curl -sLO https://raw.githubusercontent.com/p1raya/zabbix_installer_script/master/zabbix-mysql.sql
mysql -s -uzabbix -p"$DB_PASSWORD" zabbix < zabbix-mysql.sql
mysql -s -uzabbix -p"$DB_PASSWORD" zabbix -e "CALL partition_maintenance_all('zabbix');" > /dev/null \
&& echo "Zabbix 数据表分区完成"
#添加定时维护任务
echo "01 01 * * * mysql -uzabbix -p'$DB_PASSWORD' zabbix -e \"CALL partition_maintenance_all('zabbix');\"" >> /var/spool/cron/root
}&

{
#修改Zabbix服务器配置（*非*最*优*配置，请按需要自行修改）
#修改数据库密码
sed -i "/^# DBPassword=/c DBPassword=$DB_PASSWORD" /etc/zabbix/zabbix_server.conf

#其它配置优化（*按需调整*）
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
sed -i '/memory_limit/s/128M/256M/' /etc/php-fpm.d/zabbix.conf \
    && grep "memory_limit" /etc/php-fpm.d/zabbix.conf
sed -i '/post_max_size/s/16M/32M/' /etc/php-fpm.d/zabbix.conf \
    && grep "post_max_size" /etc/php-fpm.d/zabbix.conf
sed -i '/upload_max_filesize/s/2M/4M/' /etc/php-fpm.d/zabbix.conf \
    && grep "upload_max_filesize" /etc/php-fpm.d/zabbix.conf
echo 'php_value[date.timezone] = Asia/Shanghai' >> /etc/php-fpm.d/zabbix.conf \
    && grep "Asia/Shanghai" /etc/php-fpm.d/zabbix.conf

#修改SELINUX配置
setenforce 0 && echo "SELinux 已停用"
#设置 "SELINUX=permissive"
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

#修改 Nginx 配置
sed -i '/listen\s\+80/s/^#//' /etc/nginx/conf.d/zabbix.conf
sed -i '/server_name\s\+example.com/s/^#//' /etc/nginx/conf.d/zabbix.conf
if [ ! $SERVER_NAME ]; then
    IPv4=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d '/')
    sed -i "s/example.com/$IPv4/" /etc/nginx/conf.d/zabbix.conf
else
    sed -i "s/example.com/$SERVER_NAME/" /etc/nginx/conf.d/zabbix.conf
fi

#防火墙放行服务端口
firewall-cmd -q --permanent --add-port=10050/tcp
firewall-cmd -q --permanent --add-port=10051/tcp
firewall-cmd -q --permanent --add-service=http
firewall-cmd -q --permanent --add-service=snmp

#设置服务开机启动
/bin/systemctl -q enable mariadb nginx php-fpm
/bin/systemctl -q enable zabbix-server
/bin/systemctl -q enable zabbix-agent
}&

{
#下载SourceHanSansCN字体
mkdir /usr/share/fonts/SourceHanSansCN
curl -sLo /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf \
    https://raw.githubusercontent.com/adobe-fonts/source-han-sans/release/SubsetOTF/CN/SourceHanSansCN-Normal.otf
ln -fs /usr/share/fonts/SourceHanSansCN/SourceHanSansCN-Normal.otf /etc/alternatives/zabbix-web-font \
&& echo "Zabbix 图形字体修改为 SourceHanSansCN"
}&

{
case $NEED_WECHAT in
    yes|Yes|YEs|YES|Y|y)
        #安装 python3 和requests 库
        yum install -q -y python3 python3-requests
        pip3 install -q --upgrade requests
        #获取微信报警脚本
        curl -sLo /usr/lib/zabbix/alertscripts/wechat.py https://raw.githubusercontent.com/p1raya/zabbix_installer_script/master/wechat.py\
        && echo -e "微信报警脚本 wechat.py 已添加"
        sed -i "s/self.CORPID = .*/self.CORPID = \'$MYCORPID\'/g" /usr/lib/zabbix/alertscripts/wechat.py
        sed -i "s/self.SECRET = .*/self.SECRET = \'$MYSECRET\'/g" /usr/lib/zabbix/alertscripts/wechat.py
        sed -i "s/self.AGENTID = .*/self.AGENTID = \"$MYAGENTID\"/g" /usr/lib/zabbix/alertscripts/wechat.py
        chmod +x /usr/lib/zabbix/alertscripts/wechat.py
        ;;
esac

case $NEED_GRAFANA in
    yes|Yes|YEs|YES|Y|y)
        #安装Grafana
        echo "安装 Grafana..."
        cat > /etc/yum.repos.d/grafana.repo <<EOF
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF
        yum install -q -y grafana > /dev/null || { echo "Grafana 安装失败"; exit; }
        #安装Zabbix插件
        grafana-cli plugins install alexanderzobnin-zabbix-app > /dev/null && echo "Grafana 安装完成"
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
/bin/systemctl -q start php-fpm.service && echo "php-fpm 已启动"
/bin/systemctl -q start nginx.service && echo "Nginx 已启动"
/bin/systemctl -q start zabbix-server.service && echo "Zabbix Server 已启动"
/bin/systemctl -q start zabbix-agent.service && echo "Zabbix Agent 已启动"

echo "安装完毕！"
