#!/bin/bash
set -euo pipefail

setup_ipv6() {
    echo "Setting up IPv6..."
    ip -6 addr flush dev eth0
    bash <(curl -s "https://raw.githubusercontent.com/quanglinh0208/3proxy/main/ipv6.sh") 
}

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
    sudo mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    sudo cp src/3proxy /usr/local/etc/3proxy/bin/
    cd -
}

gen_3proxy() {
    cat <<EOF | sudo tee /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 5000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
nscache6 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth none
allow 127.0.0.1

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\nflush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4}' ${WORKDATA} >proxy.txt
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

gen_ifconfig() {
    awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA}
}

download_proxy() {
    cd $WORKDIR || exit 1
    curl -F "proxy.txt" https://transfer.sh
}

# Main script execution starts here

# Install dependencies
echo "Installing apps"
sudo yum -y install curl wget gcc net-tools bsdtar zip >/dev/null

install_3proxy

# Setup work directory
WORKDIR="/home/kiet"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR
cd $WORKDIR

# Get IP addresses
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal IP = ${IP4}. External subnet for IPv6 = ${IP6}"

FIRST_PORT=10000
LAST_PORT=12444

echo "Cổng proxy: $FIRST_PORT"
echo "Số lượng proxy tạo: $(($LAST_PORT - $FIRST_PORT + 1))"

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh

gen_3proxy

# Set up /etc/rc.local for persistence
cat <<EOF | sudo tee /etc/rc.d/rc.local
#!/bin/bash
touch /var/lock/subsys/local
systemctl start NetworkManager.service
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
EOF

sudo chmod +x /etc/rc.d/rc.local

# Start necessary services and configurations
sudo systemctl start NetworkManager.service
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 65535
sudo /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

# Generate proxy file for user
gen_proxy_file_for_user
rm -rf /root/3proxy-3proxy-0.8.6

echo "Starting Proxy"

echo "Tổng số IPv6 hiện tại:"
ip -6 addr | grep inet6 | wc -l
download_proxy
