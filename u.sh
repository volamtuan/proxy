#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Function to generate a random IPv6 address
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)" >> "${WORKDATA}/ipv6.txt"
}

# Function to install 3proxy
install_3proxy() {
    URL="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,stat}
    cp bin/3proxy /usr/local/etc/3proxy/bin/
    cp ../init.d/3proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

# Function to download proxy file
download_proxy() {
    cd /home/cloudfly || return
    curl -F "file=@proxy.txt" https://file.io
}

# Function to generate 3proxy configuration
gen_3proxy() {
    cat <<EOF
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

$(awk -F "/" '{print "\n" \
"" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

# Function to generate proxy file for user
gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Function to generate data for proxies
gen_data() {
    for port in $(seq $FIRST_PORT $LAST_PORT); do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

# Function to generate iptables rules
gen_iptables() {
    cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

# Function to generate ifconfig commands
gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}

# Create rc.local file
cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
EOF

echo "installing apps"
yum -y install wget gcc net-tools bsdtar zip >/dev/null

install_3proxy

WORKDIR="/home/cloudfly"
mkdir -p "$WORKDIR" && cd "$WORKDIR" || exit

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

FIRST_PORT=10000

LAST_PORT=$((FIRST_PORT + 999))
echo "FIRST_PORT is $FIRST_PORT. LAST_PORT is $LAST_PORT. Continuing..."

# Generate proxies
gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

bash /etc/rc.local

gen_proxy_file_for_user
rm -rf /root/3proxy-0.9.4

echo "Starting Proxy"

check_ipv6_live() {
    local ipv6_address=$1
    ping6 -c 3 $ipv6_address
}

# Sử dụng hàm để kiểm tra tính sống của một địa chỉ IPv6 cụ thể
check_all_ipv6_live() {
    ip -6 addr | grep inet6 | while read -r line; do
        address=$(echo "$line" | awk '{print $2}')
        ip6=$(echo "$address" | cut -d'/' -f1)
        ping6 -c 1 $ip6 > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "$ip6 is live"
        else
            echo "$ip6 is not live"
        fi
    done
}
check_all_ips
check_all_ipv6_live

check_all_ips() {
    while IFS= read -r line; do
        ipv6=$(echo "$line" | cut -d '/' -f 5)
        echo "Kiểm tra IPv6: $ipv6"
        ping6 -c 3 $ipv6
        echo "-----------------------------------"
    done < /home/cloudfly/data.txt
}
echo "Number of IPv6 Addresses Currently:"
ip -6 addr | grep inet6 | wc -l
download_proxy
