#!/bin/bash
clear
while true
echo "1.安装VSFTP
2.卸载VSFTP
3.创建用户
4.删除用户
5.退出"
    read -p '请输入数字：' number
    do
        case $number in
            1)
            #关闭SElinux
                getselinux=`getenforce`
                if [[ $getselinux == Enforcing || $getselinux == Permissive ]];then
                    
                    setenforce 0
                    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
                    echo "已关闭SElinux"
                else
                    echo "SElinux Disabled"
                fi
            #安装vsftp
                if [ -f /usr/lib/systemd/system/vsftpd.service ];then
                    echo "vsftpd.service服务已安装"
                else
                    echo "vsftpd.service服务未安装，正在执行安装..."
                    yum install -y vsftpd
                #清除iptables规则（lnmp默认会打开iptables规则）
                    #iptables -F
                    mkdir -p /etc/vsftpd/vusers_dir
                    mkdir -p /data/wwwroot
                    systemctl start vsftpd.service
                #开启防火墙，开放50021-50025端口
                    systemctl start firewalld.service
                    firewall-cmd --zone=public --add-port=50021-50025/tcp --permanent
                    firewall-cmd --reload
                    systemctl enable firewalld
                    echo "安装完成。"
                fi
                exit
                ;;
            2)
            #卸载vsftp
                 if [ -f /usr/lib/systemd/system/vsftpd.service ];then
                    echo "vsftpd.service服务已安装,正在卸载..."
                    systemctl stop vsftpd.service
                    yum remove -y vsftpd
                    rm -rf /etc/vsftpd/*
                    rm -rf /etc/pam.d/vsftpd.bak
                    firewall-cmd --zone=public --remove-port=50021-50025/tcp --permanent
                    firewall-cmd --reload
                    echo "卸载完成。"
                else
                    echo "vsftpd.service未安装"
                fi
                exit
                ;;
            3)
            #创建用户
                clear
                read -p "请输入新账号：" newuser
                grep $newuser /etc/vsftpd/vusers.list 2> /dev/null
                if [ $? -eq 0 ];then
                echo "账号已存在"
                exit
            else
                read -p "请输入密码：" newpasswd
                if [ `echo "$newpasswd" | wc -L` -ge 8 ] && [ `echo "$newpasswd" | wc -L` -le 24 ];then
cat >> /etc/vsftpd/vusers.list << EOF
$newuser
$newpasswd
EOF
                else
                    echo "密码必须大于8位数小于24位数。"
                    exit
                fi
            #创建数据库文件
                cd /etc/vsftpd/
                db_load -T -t hash -f vusers.list vusers.db
                chmod 600 /etc/vsftpd/vusers.*
            #添加虚拟用户的映射账号、ftp根目录
                ftpdir="/data/wwwroot/"
                mkdir -p ${ftpdir}
                useradd -d ${ftpdir} -s /sbin/nologin www &>/dev/null
                #chmod -R 755 ${ftpdir}         #目录无数据时不注释，有数据时会导致赋予权限过慢
                #chown -R www:www ${ftpdir}     #目录无数据时不注释，有数据时会导致赋予权限过慢
            #为虚拟用户建立pam认证文件
                cp /etc/pam.d/vsftpd /etc/pam.d/vsftpd.bak
                sed -i "s/^/#/g" /etc/pam.d/vsftpd
cat > /etc/pam.d/vsftpd << EOF
auth    required        pam_userdb.so db=/etc/vsftpd/vusers
account required        pam_userdb.so db=/etc/vsftpd/vusers
EOF
            #修改vsftp配置，添加虚拟用户支持
                cp /etc/vsftpd/vsftpd.conf /etc/vsftpd/vsftpd.conf.bak
cat > /etc/vsftpd/vsftpd.conf << EOF
#禁止匿名访问
anonymous_enable=NO
#允许本地用户模式
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
xferlog_std_format=YES
#限制ftp根目录
chroot_local_user=YES
#所有用户不允许列出上一级目录
force_dot_files=YES
#允许禁锢的FTP根目录可写而不拒绝用户登入请求
allow_writeable_chroot=YES
listen=NO
listen_ipv6=YES
userlist_enable=YES
tcp_wrappers=YES

#被动模式
listen_port=50021
pasv_enable=YES
pasv_min_port=50022
pasv_max_port=50025

#被动模式配置，加外网IP是防止xftp登陆返回内网ip作为被动模式ip的问题
#pasv_enable=YES             #可不加
#pasv_address=47.100.5.67    #可不加
#pasv_addr_resolve=YES       #可不加

#开启虚拟模式
guest_enable=YES
#虚拟用户
guest_username=www
#指定pam文件
pam_service_name=vsftpd
EOF
#添加用户配置
echo "user_config_dir=/etc/vsftpd/vusers_dir" >>  /etc/vsftpd/vsftpd.conf
cat > /etc/vsftpd/vusers_dir/$newuser << EOF
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
anon_umask=022
local_root=${ftpdir}
EOF
                systemctl restart vsftpd.service
                inet=`ip a | grep -w "inet" | grep -v 127.0.0.1 | awk -F "/" '{print $1}' | tr -d " inet"`
                onet=`curl https://ifconfig.me/`
                clear
                echo -e "您的账号为：$newuser\n您的密码为：$newpasswd\n内网IP：$inet\n外网IP：$onet\n端口号：50021"
                exit
            fi
                ;;
            4)
            #删除账号
                clear
                awk 'NR%2==1' /etc/vsftpd/vusers.list
                read -p "请输入要删除的账号：" userdel
                grep -nw $userdel /etc/vsftpd/vusers.list > /dev/null
                if [ $? -eq 0 ];then
                    
                    udel=`sed -n -e "/^$userdel$/=" /etc/vsftpd/vusers.list`
                    #echo "$udel"
                    sed -i ''$udel',+1d' /etc/vsftpd/vusers.list
                    #cat /etc/vsftpd/vusers.list
                #重新生成DB文件
                    rm -rf /etc/vsftpd/vusers.db
                    cd /etc/vsftpd/
                    db_load -T -t hash -f vusers.list vusers.db
                    chmod 600 /etc/vsftpd/vusers.*
                    rm -rf /etc/vsftpd/vusers_dir/$userdel
                    echo "已删除账号：$userdel"
                    exit
                else
                    echo "账号不存在"
                    exit
                fi
                ;;
            5)
            #退出
                echo '正在退出...'
                exit
                ;;
            *)
                clear
                echo '请重新输入'
                echo '----------------------------------------'
                ;;
        esac
    done