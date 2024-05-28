#!/bin/bash

WORKDIR="/home/cloudfly"
MAXCOUNT=2222
IFCFG="eth0"
START_PORT=10000

# Function to generate IPv6 addresses
gen_ipv6_64() {
    rm "$WORKDIR/data.txt"
    count_ipv6=1
    while [ "$count_ipv6" -le "$MAXCOUNT" ]; do
        array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f )
        ip64() {
            echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
        }
        echo "$IP6:$(ip64):$(ip64):$(ip64):$(ip64):$(ip64)" >> "$WORKDIR/data.txt"
        let "count_ipv6 += 1"
    done
}

# Function to generate ifconfig commands
gen_ifconfig() {
    while read -r line; do
        echo "ifconfig $IFCFG inet6 add $line/64"
    done < "$WORKDIR/data.txt" > "$WORKDIR/boot_ifconfig.sh"
}

# Rotate IPv6 addresses manually
rotate_ipv6_manual() {
    echo "Rotating IPv6 addresses manually..."
    gen_ipv6_64
    gen_ifconfig
    bash "$WORKDIR/boot_ifconfig.sh"
    service network restart
    echo "IPv6 addresses have been rotated manually."
}

# Rotate IPv6 addresses automatically
rotate_ipv6_auto() {
    echo "Rotating IPv6 addresses automatically..."
    while true; do
        gen_ipv6_64
        gen_ifconfig
        bash "$WORKDIR/boot_ifconfig.sh"
        service network restart
        echo "IPv6 addresses have been rotated automatically."
        sleep 600 # Wait for 10 minutes before rotating again
    done
}

# Main
echo "Kiểm tra kết nối IPv6 ..."
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

if [ -z "$IP4" ] || [ -z "$IP6" ]; then
    echo "[ERROR]: Không thể lấy IP."
    exit 1
fi

echo "[OKE]: Thành công"
echo "IPV4: $IP4"
echo "IPV6: $IP6"
echo "Mạng chính: $IFCFG"

rotate_ipv6_auto & # Start automatic rotation in the background

# Proxy configuration
gen_proxy_config() {
    cat <<EOF > "$WORKDIR/proxy.cfg"
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
stacksize 60000
auth iponly strong cache
allow * * 127.0.0.0/8
allow 14.224.163.75
deny * * *
flush
$(awk -F "/" '{print "\n" \
"" $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' "${WORKDIR}/data.txt")
EOF
}

gen_proxy_config

/usr/local/etc/3proxy/bin/3proxy "$WORKDIR/proxy.cfg"
