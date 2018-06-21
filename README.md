# zabbix_installer_script
Zabbix Installation on Centos 7

适用于最小化安装的CentOS 7系统。
功能包括：

0、数据库分区配置（独立LVM分区）

1、软件源配置和软件下载安装

2、数据库配置（MariaDB，开启独立表空间，数据表分区）

3、Zabbix服务相关配置

4、微信报警脚本

5、Grafana安装

安装前根据需求编辑好zabbix_installation.sh前面的预设信息，直接在服务器上执行该文件即可。为了加快安装速度，脚本软件配置部分并发执行。
