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
    echo "Bắt đầu cài đặt 3proxy..."
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null 2>&1
    cd 3proxy-3proxy-0.8.6 || exit 1
    make -f Makefile.Linux >/dev/null 2>&1
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat} >/dev/null 2>&1
    cp src/3proxy /usr/local/etc/3proxy/bin/ >/dev/null 2>&1
    cd $WORKDIR || exit 1
    echo "Cài đặt 3proxy hoàn tất."
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 4000
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
auth iponly strong cache
allow 14.224.163.75
deny * * *

$(awk -F "/" '{print "\n" \
"" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA})
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

setup_environment() {
    echo "Cài đặt các gói cần thiết..."
    yum -y install gcc net-tools bsdtar zip make >/dev/null 2>&1
    yum install curl wget -y >/dev/null 2>&1
    yum install nano net-tools -y >/dev/null 2>&1
    echo "Hoàn tất cài đặt các gói cần thiết."
}

rotate_count=0

rotate_ipv6() {
    echo "Auto xoay IPv6..."
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    gen_data >$WORKDIR/data.txt
    gen_ifconfig >$WORKDIR/boot_ifconfig.sh
    bash $WORKDIR/boot_ifconfig.sh
    sudo service network restart
    echo "Xoay IPv6 hoàn tất."
    rotate_count=$((rotate_count + 1))
    echo "Delay xoay 1h: $rotate_count"
    sleep 3600
}

download_proxy() {
    cd $WORKDIR || return
    curl -F "file=@proxy.txt" https://file.io
}

# Tính thời gian bắt đầu
start_time=$(date +%s)

echo "Đang thiết lập môi trường..."
WORKDIR="/home/vlt"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR || exit 1

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

FIRST_PORT=25555
LAST_PORT=27777

echo "Cổng proxy: $FIRST_PORT"
echo "Số lượng proxy tạo: $(($LAST_PORT - $FIRST_PORT + 1))"
setup_environment
install_3proxy

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh /etc/rc.local
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 20048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.local
bash /etc/rc.local

gen_proxy_file_for_user

rm -rf /root/3proxy-3proxy-0.8.6
rm -rf lan.sh
echo "Hoàn tất tạo proxy. Tệp proxy tại: /home/vlt/proxy.txt"
echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l

# Tính thời gian kết thúc và hiển thị
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))
echo "Thời gian cài đặt: $(($elapsed_time / 60)) phút $(($elapsed_time % 60)) giây."

# Menu loop
while true; do
    echo "1. Thiết lập lại 3proxy"
    echo "2. Auto xoay IPV6 tự động"
    echo "3. Download proxy"
    echo "0. Thoát"
    echo -n "Nhập phím chọn: "
    read choice
    case $choice in
        1)
            install_3proxy
            ;;
        2)
            rotate_ipv6
            ;;
        3)
            download_proxy
            ;;
        0)
            echo "Thoát..."
            exit 0
            ;;
        *)
            echo "Lựa chọn không hợp lệ. Vui lòng thử lại."
            ;;
    esac
done
