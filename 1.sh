#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

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

ipv6=$(ping -6 -c 1 google.com | grep -oP '(?<=\().*?(?=\))')

gen_3proxy() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
    daemon
    maxconn 10000
    nserver 1.1.1.1
    nserver 8.8.4.4
    nserver 2001:4860:4860::1111
    nserver 2001:4860:4860::1001
    nserver 2606:4860:4860::8888
    nserver 2606:4860:4860::8844
    nscache 65536
    timeouts 1 5 30 60 180 1800 15 60
    setgid 65535
    setuid 65535
    stacksize 6291456
    dnsmaxttl 30m
    rotate 30
    flush
    auth none
    allow 127.0.0.1

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
        # Generate data entry in the format: //$IP4/$port/IPv6
        entry="//$IP4/$port/$(gen64 $IP6)"
        echo "$entry"
        echo "$IP4:$port" >> "$WORKDIR/ipv4.txt"
        echo "$(gen64 $IP6)" >> "$WORKDIR/ipv6.txt"
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
