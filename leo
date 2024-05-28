#!/usr/local/bin/bash

# Function to generate IPv6 addresses
gen_ipv6_64() {
    rm $WORKDIR/ipv6.txt
    for ((count_ipv6=1; count_ipv6<=2000; count_ipv6++)); do
        for _ in {1..6}; do
            echo -n "${hex_chars[$((RANDOM % 16))]}"
        done | sed 's/.\{4\}/&:/g; s/:$//' >> $WORKDIR/ipv6.txt
    done
}

# Function to install and configure 3proxy
install_3proxy() {
    echo "Installing 3proxy..."
    sudo yum install gcc make nano git -y
    git clone https://github.com/z3apa3a/3proxy
    cd 3proxy || exit
    ln -s Makefile.Linux Makefile
    make
    sudo make install
    systemctl daemon-reload
    echo "* hard nofile 999999" >>  /etc/security/limits.conf
    echo "* soft nofile 999999" >>  /etc/security/limits.conf
    systemctl stop firewalld
    systemctl disable firewalld
    ulimit -n 65535
    chkconfig 3proxy on
    cd "$WORKDIR" || exit
}

# Function to generate 3proxy configuration
gen_3proxy_cfg() {
    cat <<EOF > /etc/3proxy/3proxy.cfg
daemon
maxconn 3000
nserver 1.1.1.1
nserver [2606:4700:4700::1111]
nserver [2606:4700:4700::1001]
nserver [2001:4860:4860::8888]
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
authcache user 86400
auth strong cache
users vlt:CL:vlt
allow 14.224.163.75
EOF
    
    port=$START_PORT
    while read -r ip; do
        echo "proxy -6 -n -a -p$port -i$IP4 -e$ip"
        ((port+=1))
    done < "$WORKDIR/ipv6.txt"
}

# Function to generate ifconfig commands for IPv6
gen_ifconfig() {
    while read -r line; do    
        echo "ifconfig $IFCFG inet6 add $line/64"
    done < "$WORKDIR/ipv6.txt"
}

# Function to export proxy settings
export_txt() {
    port=$START_PORT
    for ((i=1; i<=$MAXCOUNT; i++)); do
        echo "$IP4:$port:vlt:vlt"
        ((port+=1))
    done
}

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo 'Error: this script must be run as root'
    exit 1
fi

# Create directory and set permissions
mkdir -p /home/proxy
chmod -R 777 /home/proxy

# Install and configure 3proxy
install_3proxy

# Restart network services
service network restart
systemctl stop firewalld
ulimit -n 65535
yum -y install gcc net-tools bsdtar zip psmisc wget >/dev/null

# Retrieve IPv4 and IPv6 addresses
if ping6 -c3 icanhazip.com &> /dev/null; then
    IP4=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n1)
    IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
    main_interface=$(ip route get 2001:4860:4860::8888 | awk -- '{printf $5}')
    
    echo "[OK]: Successfully obtained IP addresses"
    echo "IPv4: $IP4"
    echo "IPv6: $IP6"
else
    echo "[ERROR]: Failed to retrieve IP addresses"
fi

# Set variables
IFCFG="$main_interface" 
WORKDIR="/home/proxy"
START_PORT=50000
MAXCOUNT=2000

# Generate IPv6 addresses
echo "Generating $MAXCOUNT IPv6 addresses..."
gen_ipv6_64

# Generate ifconfig commands
echo "Generating ifconfig commands for IPv6..."
gen_ifconfig > "$WORKDIR/boot_ifconfig.sh"
bash "$WORKDIR/boot_ifconfig.sh"

# Configure 3proxy
echo "Configuring 3proxy..."
gen_3proxy_cfg

# Export proxy settings
echo "Exporting proxy settings..."
export_txt > "$IP4.txt"

# Upload proxy file
upload_proxy() {
    URL=$(curl -s --upload-file "$IP4.txt" "https://transfer.sh/$IP4.txt")
    echo "Proxy setup completed! Format: IP:PORT:LOGIN:PASSWORD"
    echo "Download proxy file at: ${URL}"
}
upload_proxy

# Generate script for rotating IPs
xoay_proxy() {
    cat <<EOF > /home/proxy/xoay.sh
#!/usr/bin/bash
gen_ipv6_64() {
    rm $WORKDIR/ipv6.txt
    for ((count_ipv6=1; count_ipv6<=$MAXCOUNT; count_ipv6++)); do
        for _ in {1..6}; do
            echo -n "${hex_chars[$((RANDOM % 16))]}"
        done | sed 's/.\{4\}/&:/g; s/:$//' >> $WORKDIR/ipv6.txt
    done
}
gen_3proxy_cfg() {
    cat <<EOF2 > /etc/3proxy/3proxy.cfg
daemon
maxconn 3000
nserver 1.1.1.1
nserver [2606:4700:4700::1111]
nserver [2606:4700:4700::1001]
nserver [2001:4860:4860::8888]
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
authcache user 86400
auth strong cache
users vlt:CL:vlt
allow 14.224.163.75
EOF2
    
    port=$START_PORT
    while read -r ip; do
        echo "proxy -6 -n -a -p$port -i$IP4 -e$ip"
        ((port+=1))
    done < "$WORKDIR/ipv6.txt"
}
gen_ifconfig() {
    while read -r line; do    
        echo "ifconfig $IFCFG inet6 add $line/64"
    done < "$WORKDIR/ipv6.txt"
}
if [ "$(id -u)" -ne 0 ]; then
    echo 'Error: this script must be run as root'
    exit 1
fi
service network restart
ulimit -n 65535

EOF
}
xoay_proxy
