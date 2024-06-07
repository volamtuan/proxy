#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Tự động lấy địa chỉ IPv4 từ thiết bị
IP4=$(ip addr show | grep -oP '(?<=inet\s)192(\.\d+){2}\.\d+' | head -n 1)

IPV6ADDR=$(ip -6 addr show | grep -oP '(?<=inet6\s)[\da-fA-F:]+(?=/64)' | head -n 1)

if ip link show eth0 &> /dev/null; then
    echo "Card mạng eth0 đã được tìm thấy."
    
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
TYPE=Ethernet
NAME=eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
IPV6_INIT=yes
IPV6_AUTOCONF=yes
IPV6_DEFROUTE=yes
IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=eui64
IPADDR="${IP4}"
NETMASK=255.255.255.0
GATEWAY=192.168.1.1
DNS="8.8.8.8"
DNS="8.8.4.4"
IPV6ADDR="${IPV6ADDR}/64"
IPV6_DEFAULTGW="${IPV6ADDR}::1"
EOF

# Khởi động lại dịch vụ mạng
systemctl restart network

# Kiểm tra kết nối IPv6
if ip -6 route get "${IPV6ADDR}" &> /dev/null; then
    echo "Kết nối IPv6 hoạt động."
else
    echo "Lỗi: Kết nối IPv6 không hoạt động."
fi

firewall-cmd --zone=public --add-source="${IP4}" --permanent
firewall-cmd --reload

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_3proxy() {
    echo "Installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth iponly
allow * $IP4

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4}' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

download_proxy() {
    cd $WORKDIR || return
    curl -F "file=@proxy.txt" https://file.io
}

# Thiết lập tập tin /etc/rc.local để khởi động các cấu hình mạng và 3proxy khi hệ thống khởi động
cat <<EOF >/etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

# Cài đặt các ứng dụng cần thiết
echo "Installing apps"
yum -y install wget gcc net-tools bsdtar zip >/dev/null

install_3proxy

# Thiết lập thư mục làm việc
WORKDIR="/home/cloudfly"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR

# Lấy địa chỉ IP
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External subnet for IPv6 = ${IP6}"

FIRST_PORT=40000
LAST_PORT=41290

echo "Cổng proxy: $FIRST_PORT"
echo "Số lượng proxy tạo: $(($LAST_PORT - $FIRST_PORT + 1))"

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local

# Tạo tập tin cấu hình 3proxy
gen_3proxy

# Cập nhật tập tin rc.local để khởi động các dịch vụ và cấu hình khi hệ thống khởi động
cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

# Thực thi rc.local
bash /etc/rc.local

# Tạo tập tin proxy cho người dùng
gen_proxy_file_for_user
rm -rf /root/3proxy-3proxy-0.8.6

echo "Starting Proxy"

echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l
download_proxy
