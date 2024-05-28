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
  echo "installing 3proxy"
  URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
  wget -qO- $URL | bsdtar -xvf-
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  cd $WORKDIR
}

gen_3proxy_no_pass() {
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
"flush\n"}' ${WORKDATA1})
EOF
}

gen_3proxy_with_pass() {
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
"auth strong\n" \
"users $2:CL:$(echo -n $3 | base64)\n" \
"allow $2\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA2})
EOF
}

gen_proxy_file_for_user() {
  cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 }' ${WORKDATA_NO_PASS})
$(awk -F "/" '{print $3 ":" $4 ":" $2 ":" $3 }' ${WORKDATA_WITH_PASS})
EOF
}

gen_data_no_pass() {
  seq $FIRST_PORT $LAST_PORT | while read port; do
    echo "//$IP4/$port/$(gen64 $IP6)"
  done
}

gen_data_with_pass() {
    seq $FIRST_PORT_WITH_PASS $LAST_PORT_WITH_PASS | while read port; do
        echo "vlt$port/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
  cat <<EOF
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA_NO_PASS}) 
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA_WITH_PASS}) 
EOF
}

gen_ifconfig() {
  cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA_NO_PASS})
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA_WITH_PASS})
EOF
}

rotate_ipv6() {
  while true; do
    echo "Rotating IPv6 addresses"
    gen_ifconfig | sh
    sleep 600
  done
}

setup_environment() {
  echo "installing apps"
  yum -y install wget gcc net-tools bsdtar zip >/dev/null

  install_3proxy

  echo "Cau Hinh Proxy..."
  WORKDIR="/home/proxy1"
  WORKDIR2="/home/proxy2"
  WORKDATA_NO_PASS="${WORKDIR}/data_no_pass.txt"
  WORKDATA_WITH_PASS="${WORKDIR2}/data_with_pass.txt"
  mkdir $WORKDIR && mkdir $WORKDIR2 && cd $_

  IP4=$(curl -4 -s icanhazip.com)
  IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

  echo "Internal ip = ${IP4}. External sub for ip6 = ${IP6}"

  FIRST_PORT=30000
  LAST_PORT=$(($FIRST_PORT + 999))

  FIRST_PORT2=20000
  FIRST_PORT_WITH_PASS=$(($FIRST_PORT + 1000))
  LAST_PORT_WITH_PASS=$(($FIRST_PORT_WITH_PASS + 1999))

  echo "First port for no-pass proxies: $FIRST_PORT"
  echo "Last port for no-pass proxies: $LAST_PORT"
  echo "First port for proxies with pass: $FIRST_PORT_WITH_PASS"
  echo "Last port for proxies with pass: $LAST_PORT_WITH_PASS"
}

create_proxies_no_pass() {
  echo "Generating proxy data without password"
  gen_data_no_pass >$WORKDATA_NO_PASS

  echo "Generating iptables rules"
  gen_iptables >$WORKDIR/boot_iptables.sh
  echo "Generating ifconfig commands"
  gen_ifconfig >$WORKDIR/boot_ifconfig.sh
  chmod +x $WORKDIR/boot_*.sh

  echo "Generating 3proxy configuration"
  gen_3proxy_no_pass > /usr/local/etc/3proxy/3proxy.cfg

  echo "Applying configuration"
  bash $WORKDIR/boot_iptables.sh
  bash $WORKDIR/boot_ifconfig.sh
  /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

  gen_proxy_file_for_user
  echo "Proxies without password created"
}

create_proxies_with_pass() {
  echo "Generating proxy data with password"
  gen_data_with_pass >$WORKDATA_WITH_PASS

  echo "Generating 3proxy configuration"
  gen_3proxy_with_pass >> /usr/local/etc/3proxy/3proxy.cfg

  echo "Applying configuration"
  /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

  gen_proxy_file_for_user
  echo "Proxies with password created"
}

download_proxies() {
    cd $WORKDIR || exit 1
    curl -F "proxy.txt" https://transfer.sh
}

echo "Starting Proxy"
echo "Current IPv6 Address Count:"
ip -6 addr | grep inet6 | wc -l

main_menu() {
  setup_environment

  while true; do
    echo "1. Create proxies without password"
    echo "2. Create proxies with password"
    echo "3. Rotate IPv6 every 10 minutes"
    echo "4. Download proxy list"
    echo "5. Exit"
    read -p "Choose an option: " choice
    case $choice in
      1) create_proxies_no_pass ;;
      2) create_proxies_with_pass ;;
      3) rotate_ipv6 & ;;
      4) download_proxies ;;
      5) exit 0 ;;
      *) echo "Invalid option" ;;
    esac
  done
}

main_menu
