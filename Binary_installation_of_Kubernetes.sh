#!/bin/bash

###
#   作者：陈步云
#   微信：15648907522
#   使用说明：
#       该脚本需要八台服务器，在八台服务器中有一台是用于执行该脚本的，另外有五台k8s服务器，其他俩台作为lb负载均衡服务器。
#       将其中七台服务器配置好静态IP，修改如下变量中的IP即可。
#       同时查看服务器中的网卡名，并将其修改。
#       执行脚本可使用bash -x 即可显示执行中详细信息。
#       该脚本暂时不支持自定义k8s结构，需要严格执行该结构。
### 

#每个节点的IP
export k8s_master01="192.168.1.40"
export k8s_master02="192.168.1.41"
export k8s_master03="192.168.1.42"
export k8s_node01="192.168.1.43"
export k8s_node02="192.168.1.44"
export lb_01="192.168.1.45"
export lb_02="192.168.1.46"
export lb_vip="192.168.1.55"

#物理网络ip地址段
export ip_segment="192.168.1.0\/24"

#k8s自定义域名
export domain="x.oiox.cn"

#服务器网卡名
export eth="ens18"

export master01="k8s-master01"
export master02="k8s-master02"
export master03="k8s-master03"
export node01="k8s-node01"
export node02="k8s-node02"
export lb01="lb01"
export lb02="lb02"


export IP="k8s-master01 k8s-master02 k8s-master03 k8s-node01 k8s-node02 lb01 lb02"
export other="k8s-master02 k8s-master03 k8s-node01 k8s-node02 lb01 lb02"
export k8s_other="k8s-master02 k8s-master03 k8s-node01 k8s-node02"
export k8s="k8s-master01 k8s-master02 k8s-master03 k8s-node01 k8s-node02"
export Master='k8s-master01 k8s-master02 k8s-master03'
export Work='k8s-node01 k8s-node02'
export lb='lb01 lb02'



function ping_test() {
        a=()
        for ip in $k8s
                do
                        ping -c 2 $ip >/dev/null
                        [[ $? -ne 0 ]] && a+=($ip)
                done
        echo ${a[*]}
}

function os() {
    os=$(cat /etc/os-release 2>/dev/null | grep ^ID= | awk -F= '{print $2}')

    if [ "$os" = "\"centos\"" ]; then
        yum update ; yum install -y sshpass
    fi
    if [ ! "$os" = "ubuntu" ]; then
        apt update ; apt install -y sshpass
    fi

    echo $os
}

function set_local() {

echo "本机写入hosts配置文件..."

cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$k8s_master01 k8s-master01
$k8s_master02 k8s-master02
$k8s_master03 k8s-master03
$k8s_node01 k8s-node01
$k8s_node02 k8s-node02
$lb_01 lb01
$lb_02 lb02
$lb_vip lb-vip
EOF


echo "本机配置ssh免密..."


os

if [ $? == 0 ]; then
    echo "sshpass安装成功"
else
    echo '安装失败请检查安装机的安装源'
fi

rm -f /root/.ssh/id_rsa 
ssh-keygen -f /root/.ssh/id_rsa -P ''
export SSHPASS=123123
for HOST in $IP;do
     sshpass -e ssh-copy-id -o StrictHostKeyChecking=no $HOST
done
}


function init_all() {

for HOST in $k8s;do
{

echo "在主机 $HOST 配置hosts配置..."

ssh root@$HOST "cat > /etc/hosts << EOF 
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
$k8s_master01 k8s-master01
$k8s_master02 k8s-master02
$k8s_master03 k8s-master03
$k8s_node01 k8s-node01
$k8s_node02 k8s-node02
$lb_01 lb01
$lb_02 lb02
$lb_vip lb-vip
EOF
" 


echo "配置 $HOST 主机名"

ssh root@$HOST "hostnamectl set-hostname  $HOST"

echo "配置主机 $HOST yum源"

ssh root@$HOST "sed -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://mirror.centos.org/\$contentdir|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos|g' -i.bak /etc/yum.repos.d/CentOS-*.repo"

echo "安装$HOST 基础环境"

ssh root@$HOST "yum update ; yum -y install wget jq psmisc vim net-tools  telnet yum-utils device-mapper-persistent-data lvm2 git network-scripts tar curl chrony -y"
ssh root@$HOST "yum install epel* -y"

echo "安装$HOST docker"

ssh root@$HOST "curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun"

echo "关闭$HOST 防火墙"

ssh root@$HOST "systemctl disable --now firewalld"

echo "关闭$HOST selinux"

ssh root@$HOST "setenforce 0"
ssh root@$HOST "sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/sysconfig/selinux"


echo "关闭$HOST swa分区"
ssh root@$HOST "sed -ri 's/.*swap.*/#&/' /etc/fstab"
ssh root@$HOST "swapoff -a && sysctl -w vm.swappiness=0"

echo "在$HOST 修改fastab"
ssh root@$HOST "cat /etc/fstab"

echo "关闭$HOST NetworkManager"
ssh root@$HOST "systemctl disable --now NetworkManager"

echo "开启$HOST network"
ssh root@$HOST "systemctl start network && systemctl enable network"


echo "修改$HOST limits"
ssh root@$HOST "cat >> /etc/security/limits.conf <<EOF
* soft nofile 655360
* hard nofile 131072
* soft nproc 655350
* hard nproc 655350
* seft memlock unlimited
* hard memlock unlimitedd
EOF

ulimit -SHn 65535
" 

echo "升级$HOST 内核"

ssh root@$HOST "yum install https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm -y ; yum  --disablerepo="*"  --enablerepo="elrepo-kernel"  list  available -y ; yum  --enablerepo=elrepo-kernel  install  kernel-ml -y ; grubby --default-kernel"

echo "安装$HOST ipvs模块"

ssh root@$HOST "yum install ipvsadm ipset sysstat conntrack libseccomp -y"
ssh root@$HOST "cat >> /etc/modules-load.d/ipvs.conf <<EOF
cat 
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
EOF

systemctl restart systemd-modules-load.service"

ssh root@$HOST "lsmod | grep -e ip_vs -e nf_conntrack"

echo "配置$HOST 内核参数"

ssh root@$HOST "cat > /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720


net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
EOF"

ssh root@$HOST "sysctl --system"

}   >> $HOST.txt &
done
wait 

for HOST in $k8s;do
    echo "重启$HOST"
    ssh root@$HOST  "reboot"

done

while true; do
    sleep 10
    ping_res=$(ping_test)
    if [ -z "$ping_res" ]
    then
            echo "服务器重启完成"
            break
    else
            echo "未启动服务器：$ping_res ，等待30秒..."
    fi
    sleep 20
done

for HOST in $master01;do
echo "配置时钟同步"
ssh root@$HOST "cat > /etc/chrony.conf << EOF 
pool ntp.aliyun.com iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
allow $ip_segment
local stratum 10
keyfile /etc/chrony.keys
leapsectz right/UTC
logdir /var/log/chrony
EOF

systemctl restart chronyd
systemctl enable chronyd

" ;done

for HOST in $other;do
    echo "配置主机$HOST时钟同步"
    ssh root@$HOST "yum install chrony -y ; sed -i "s#2.centos.pool.ntp.org#10.0.0.21#g" /etc/chrony.conf ; systemctl restart chronyd ; systemctl enable chronyd" 
done

}

function Containerd() {

for HOST in $k8s;do
{
    echo "配置主机$HOST Containerd"
    ssh root@$HOST "systemctl  enable --now docker"
    ssh root@$HOST "mkdir -p /etc/cni/net.d"
    ssh root@$HOST "yum install containerd -y" 

    echo "启用主机$HOST Containerd"
    ssh root@$HOST "systemctl daemon-reload"
    ssh root@$HOST "systemctl enable --now docker"

    echo "配置主机$HOST 配置crictl客户端连接的运行时位置"
    ssh root@$HOST "cat > /etc/crictl.yaml << EOF 
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF"
} >> $HOST.txt &
done

}



function init_local(){

for HOST in $k8s;do
{
    echo "创建$HOST目录"
    ssh root@$HOST "mkdir -p /opt/cni/bin"
    ssh root@$HOST "mkdir -p /etc/kubernetes/pki"
    ssh root@$HOST "mkdir -p /etc/kubernetes/manifests/ /etc/systemd/system/kubelet.service.d /var/lib/kubelet /var/log/kubernetes"
    
} >> $HOST.txt
done





export filesize="ls -l Kubernetes.tar | awk '{ print \$5 }'"

if (( $filesize == 649707520 )); then
    echo "下载所需程序"
    rm -f Kubernetes.tar
    wget https://github.com/cby-chen/Kubernetes/releases/download/cby/Kubernetes.tar
else
    echo "所需程序已存在"
fi

if [ -d "Kubernetes" ]; then
    echo "directory \"Kubernetes\" exists"
    rm -rf Kubernetes
fi

if [ -d "Kubernetes" ]; then
    echo "directory \"Kubernetes\" exists"
else 

    echo "解压安装包"

    tar xf Kubernetes.tar
    scp -r Kubernetes  root@$master01:

    echo "配置证书工具"

    cd Kubernetes/cby/ || exit
    cp cfssl_1.6.1_linux_amd64  /usr/local/bin/cfssl
    cp cfssljson_1.6.1_linux_amd64 /usr/local/bin/cfssljson
    chmod +x  /usr/local/bin/cfssljson  /usr/local/bin/cfssl

    echo "拷贝所需程序包"
    
    tar -xf kubernetes-server-linux-amd64.tar.gz  --strip-components=3 -C /usr/local/bin kubernetes/server/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy}
    tar -xf etcd-v3.5.2-linux-amd64.tar.gz --strip-components=1 -C /usr/local/bin etcd-v3.5.2-linux-amd64/etcd{,ctl}

    echo "将所需组件发送到k8s节点"
    for NODE in $Master; do echo "$NODE"; scp /usr/local/bin/kube{let,ctl,-apiserver,-controller-manager,-scheduler,-proxy} "$NODE":/usr/local/bin/; scp /usr/local/bin/etcd* $NODE:/usr/local/bin/; done
    for NODE in $Work; do     scp /usr/local/bin/kube{let,-proxy} "$NODE":/usr/local/bin/ ; done

    mkdir -p /opt/cni/bin
    mkdir /etc/etcd/ssl -p

    echo "生成etcd证书"
    cd ../pki/ || exit
    cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare /etc/etcd/ssl/etcd-ca
    cfssl gencert -ca=/etc/etcd/ssl/etcd-ca.pem -ca-key=/etc/etcd/ssl/etcd-ca-key.pem -config=ca-config.json -hostname=127.0.0.1,k8s-master01,k8s-master02,k8s-master03,$k8s_master01,$k8s_master02,$k8s_master03  -profile=kubernetes etcd-csr.json | cfssljson -bare /etc/etcd/ssl/etcd

    echo "分发etcd证书"
    for NODE in $Master; do
        ssh "$NODE" "mkdir -p /etc/etcd/ssl"
        for FILE in etcd-ca-key.pem  etcd-ca.pem  etcd-key.pem  etcd.pem; do
        scp /etc/etcd/ssl/${FILE} "$NODE":/etc/etcd/ssl/${FILE}
        done
    done


    echo "生成k8s证书"
    mkdir -p /etc/kubernetes/pki
    cfssl gencert -initca ca-csr.json | cfssljson -bare /etc/kubernetes/pki/ca
    cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=ca-config.json -hostname=10.96.0.1,$lb_vip,127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster,kubernetes.default.svc.cluster.local,$domain,$k8s_master01,$k8s_master02,$k8s_master03 -profile=kubernetes   apiserver-csr.json | cfssljson -bare /etc/kubernetes/pki/apiserver

    echo "生成k8s-apiserver证书"
    cfssl gencert   -initca front-proxy-ca-csr.json | cfssljson -bare /etc/kubernetes/pki/front-proxy-ca 
    cfssl gencert   -ca=/etc/kubernetes/pki/front-proxy-ca.pem   -ca-key=/etc/kubernetes/pki/front-proxy-ca-key.pem   -config=ca-config.json   -profile=kubernetes   front-proxy-client-csr.json | cfssljson -bare /etc/kubernetes/pki/front-proxy-client

    echo "生成controller-manage证书"
    cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=ca-config.json -profile=kubernetes manager-csr.json | cfssljson -bare /etc/kubernetes/pki/controller-manager

    kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$lb_vip:8443 --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig

    kubectl config set-context system:kube-controller-manager@kubernetes --cluster=kubernetes --user=system:kube-controller-manager --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig


    kubectl config set-credentials system:kube-controller-manager --client-certificate=/etc/kubernetes/pki/controller-manager.pem --client-key=/etc/kubernetes/pki/controller-manager-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig

    kubectl config use-context system:kube-controller-manager@kubernetes --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig

    cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem -config=ca-config.json -profile=kubernetes scheduler-csr.json | cfssljson -bare /etc/kubernetes/pki/scheduler

    kubectl config set-cluster kubernetes --certificate-authority=/etc/kubernetes/pki/ca.pem --embed-certs=true --server=https://$lb_vip:8443 --kubeconfig=/etc/kubernetes/scheduler.kubeconfig

    kubectl config set-credentials system:kube-scheduler --client-certificate=/etc/kubernetes/pki/scheduler.pem --client-key=/etc/kubernetes/pki/scheduler-key.pem --embed-certs=true --kubeconfig=/etc/kubernetes/scheduler.kubeconfig

    kubectl config set-context system:kube-scheduler@kubernetes --cluster=kubernetes --user=system:kube-scheduler --kubeconfig=/etc/kubernetes/scheduler.kubeconfig

    kubectl config use-context system:kube-scheduler@kubernetes --kubeconfig=/etc/kubernetes/scheduler.kubeconfig

    cfssl gencert -ca=/etc/kubernetes/pki/ca.pem -ca-key=/etc/kubernetes/pki/ca-key.pem  -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare /etc/kubernetes/pki/admin

    kubectl config set-cluster kubernetes     --certificate-authority=/etc/kubernetes/pki/ca.pem     --embed-certs=true     --server=https://$lb_vip:8443     --kubeconfig=/etc/kubernetes/admin.kubeconfig

    kubectl config set-credentials kubernetes-admin     --client-certificate=/etc/kubernetes/pki/admin.pem     --client-key=/etc/kubernetes/pki/admin-key.pem     --embed-certs=true     --kubeconfig=/etc/kubernetes/admin.kubeconfig

    kubectl config set-context kubernetes-admin@kubernetes     --cluster=kubernetes     --user=kubernetes-admin     --kubeconfig=/etc/kubernetes/admin.kubeconfig

    kubectl config use-context kubernetes-admin@kubernetes     --kubeconfig=/etc/kubernetes/admin.kubeconfig

    echo "创建ServiceAccount Key"
    openssl genrsa -out /etc/kubernetes/pki/sa.key 2048
    openssl rsa -in /etc/kubernetes/pki/sa.key -pubout -out /etc/kubernetes/pki/sa.pub

    echo "分发证书到每个节点"
    for NODE in $Master; do 
        for FILE in $(ls /etc/kubernetes/pki | grep -v etcd); do 
        scp /etc/kubernetes/pki/"${FILE}" "$NODE":/etc/kubernetes/pki/"${FILE}";
        done; 
        for FILE in admin.kubeconfig controller-manager.kubeconfig scheduler.kubeconfig; do 
        scp /etc/kubernetes/${FILE} "$NODE":/etc/kubernetes/${FILE};
        done;
    done

fi

}


function init_etcd(){


for HOST in $master01;do
{
    echo "配置主机$HOST etcd"
    ssh root@$HOST "cat > /etc/etcd/etcd.config.yml << EOF 
name: 'k8s-master01'
data-dir: /var/lib/etcd
wal-dir: /var/lib/etcd/wal
snapshot-count: 5000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: 'https://$k8s_master01:2380'
listen-client-urls: 'https://$k8s_master01:2379,http://127.0.0.1:2379'
max-snapshots: 3
max-wals: 5
cors:
initial-advertise-peer-urls: 'https://$k8s_master01:2380'
advertise-client-urls: 'https://$k8s_master01:2379'
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:
initial-cluster: 'k8s-master01=https://$k8s_master01:2380,k8s-master02=https://$k8s_master02:2380,k8s-master03=https://$k8s_master03:2380'
initial-cluster-token: 'etcd-k8s-cluster'
initial-cluster-state: 'new'
strict-reconfig-check: false
enable-v2: true
enable-pprof: true
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0
client-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
peer-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  peer-client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
debug: false
log-package-levels:
log-outputs: [default]
force-new-cluster: false
EOF"
} >> $HOST.txt
done


for HOST in $master02;do
{
    echo "配置主机$HOST etcd"
    ssh root@$HOST "cat > /etc/etcd/etcd.config.yml << EOF 
name: 'k8s-master02'
data-dir: /var/lib/etcd
wal-dir: /var/lib/etcd/wal
snapshot-count: 5000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: 'https://$k8s_master02:2380'
listen-client-urls: 'https://$k8s_master02:2379,http://127.0.0.1:2379'
max-snapshots: 3
max-wals: 5
cors:
initial-advertise-peer-urls: 'https://$k8s_master02:2380'
advertise-client-urls: 'https://$k8s_master02:2379'
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:
initial-cluster: 'k8s-master01=https://$k8s_master01:2380,k8s-master02=https://$k8s_master02:2380,k8s-master03=https://$k8s_master03:2380'
initial-cluster-token: 'etcd-k8s-cluster'
initial-cluster-state: 'new'
strict-reconfig-check: false
enable-v2: true
enable-pprof: true
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0
client-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
peer-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  peer-client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
debug: false
log-package-levels:
log-outputs: [default]
force-new-cluster: false
EOF"
} >> $HOST.txt
done


for HOST in $master03;do
{
    echo "配置主机$HOST etcd"
    ssh root@$HOST "cat > /etc/etcd/etcd.config.yml << EOF 
name: 'k8s-master03'
data-dir: /var/lib/etcd
wal-dir: /var/lib/etcd/wal
snapshot-count: 5000
heartbeat-interval: 100
election-timeout: 1000
quota-backend-bytes: 0
listen-peer-urls: 'https://$k8s_master03:2380'
listen-client-urls: 'https://$k8s_master03:2379,http://127.0.0.1:2379'
max-snapshots: 3
max-wals: 5
cors:
initial-advertise-peer-urls: 'https://$k8s_master03:2380'
advertise-client-urls: 'https://$k8s_master03:2379'
discovery:
discovery-fallback: 'proxy'
discovery-proxy:
discovery-srv:
initial-cluster: 'k8s-master01=https://$k8s_master01:2380,k8s-master02=https://$k8s_master02:2380,k8s-master03=https://$k8s_master03:2380'
initial-cluster-token: 'etcd-k8s-cluster'
initial-cluster-state: 'new'
strict-reconfig-check: false
enable-v2: true
enable-pprof: true
proxy: 'off'
proxy-failure-wait: 5000
proxy-refresh-interval: 30000
proxy-dial-timeout: 1000
proxy-write-timeout: 5000
proxy-read-timeout: 0
client-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
peer-transport-security:
  cert-file: '/etc/kubernetes/pki/etcd/etcd.pem'
  key-file: '/etc/kubernetes/pki/etcd/etcd-key.pem'
  peer-client-cert-auth: true
  trusted-ca-file: '/etc/kubernetes/pki/etcd/etcd-ca.pem'
  auto-tls: true
debug: false
log-package-levels:
log-outputs: [default]
force-new-cluster: false
EOF"
} >> $HOST.txt
done



for HOST in $Master;do
{
    echo "配置主机$HOST etcd service文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/etcd.service << EOF 
[Unit]
Description=Etcd Service
Documentation=https://coreos.com/etcd/docs/latest/
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd --config-file=/etc/etcd/etcd.config.yml
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
Alias=etcd3.service
EOF"

    echo "测试$HOST etcd"
    ssh root@"$HOST" "mkdir /etc/kubernetes/pki/etcd ; ln -s /etc/etcd/ssl/* /etc/kubernetes/pki/etcd/ ; systemctl daemon-reload ; systemctl enable --now etcd"
    ssh root@"$HOST" "export ETCDCTL_API=3 ; etcdctl --endpoints="$k8s_master01:2379,$k8s_master02:2379,$k8s_master03:2379" --cacert=/etc/kubernetes/pki/etcd/etcd-ca.pem --cert=/etc/kubernetes/pki/etcd/etcd.pem --key=/etc/kubernetes/pki/etcd/etcd-key.pem  endpoint status --write-out=table"

} >> "$HOST".txt
done

}

function init_ha_keep() {


for HOST in $lb;do
{
    echo "配置主机$HOST yum源"
    ssh root@$HOST "sed -e 's|^mirrorlist=|#mirrorlist=|g' -e 's|^#baseurl=http://mirror.centos.org/\$contentdir|baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos|g' -i.bak /etc/yum.repos.d/CentOS-*.repo"
    
    echo "配置主机$HOST y防火墙"
    ssh root@"$HOST" "systemctl disable --now firewalld"

    echo "配置主机$HOST selinux"
    ssh root@"$HOST" "setenforce 0"
    ssh root@"$HOST" "sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/sysconfig/selinux"

    echo "配置主机$HOST 软件"
    ssh root@"$HOST" "yum -y install keepalived haproxy"

    echo "配置主机$HOST 配置文件"
    ssh root@"$HOST" "cat > /etc/haproxy/haproxy.cfg << EOF 
global
 maxconn 2000
 ulimit-n 16384
 log 127.0.0.1 local0 err
 stats timeout 30s

defaults
 log global
 mode http
 option httplog
 timeout connect 5000
 timeout client 50000
 timeout server 50000
 timeout http-request 15s
 timeout http-keep-alive 15s


frontend monitor-in
 bind *:33305
 mode http
 option httplog
 monitor-uri /monitor

frontend k8s-master
 bind 0.0.0.0:8443
 bind 127.0.0.1:8443
 mode tcp
 option tcplog
 tcp-request inspect-delay 5s
 default_backend k8s-master


backend k8s-master
 mode tcp
 option tcplog
 option tcp-check
 balance roundrobin
 default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
 server  master01  $k8s_master01:6443 check
 server  master02  $k8s_master02:6443 check
 server  master03  $k8s_master03:6443 check
EOF"

} >> "$HOST".txt
done


for HOST in $lb01;do
{

    echo "配置主机$HOST 配置文件"
    ssh root@"$HOST" "cat > /etc/keepalived/keepalived.conf << EOF 
! Configuration File for keepalived

global_defs {
    router_id LVS_DEVEL
}
vrrp_script chk_apiserver {
    script \"/etc/keepalived/check_apiserver.sh\"
    interval 5 
    weight -5
    fall 2
    rise 1
}
vrrp_instance VI_1 {
    state MASTER
    interface $eth
    mcast_src_ip $lb_01
    virtual_router_id 51
    priority 100
    nopreempt
    advert_int 2
    authentication {
        auth_type PASS
        auth_pass K8SHA_KA_AUTH
    }
    virtual_ipaddress {
        $lb_vip
    }
    track_script {
      chk_apiserver 
} }
EOF"

    echo "配置主机$HOST 检查脚本"
    ssh root@"$HOST" "cat > /etc/keepalived/check_apiserver.sh << EOF 
#!/bin/bash
err=0
for k in \$(seq 1 3)
do
    check_code=\$(pgrep haproxy)
    if [[ \$check_code == \"\" ]]; then
        err=\$(expr \$err + 1)
        sleep 1
        continue
    else
        err=0
        break
    fi
done

if [[ \$err != \"\0\" ]]; then
    echo \"systemctl stop keepalived\"
    /usr/bin/systemctl stop keepalived
    exit 1
else
    exit 0
fi
EOF"

} >> "$HOST".txt
done



for HOST in $lb02;do
{

    echo "配置主机$HOST 配置文件"
    ssh root@"$HOST" "cat > /etc/keepalived/keepalived.conf << EOF 
! Configuration File for keepalived

global_defs {
    router_id LVS_DEVEL
}
vrrp_script chk_apiserver {
    script \"/etc/keepalived/check_apiserver.sh\"
    interval 5 
    weight -5
    fall 2
    rise 1

}
vrrp_instance VI_1 {
    state BACKUP
    interface $eth
    mcast_src_ip $lb_02
    virtual_router_id 51
    priority 50
    nopreempt
    advert_int 2
    authentication {
        auth_type PASS
        auth_pass K8SHA_KA_AUTH
    }
    virtual_ipaddress {
        $lb_vip
    }
    track_script {
      chk_apiserver 
} }
EOF"

    echo "配置主机$HOST 检查脚本"
    ssh root@"$HOST" "cat > /etc/keepalived/check_apiserver.sh << EOF 
#!/bin/bash
err=0
for k in \$(seq 1 3)
do
    check_code=\$(pgrep haproxy)
    if [[ \$check_code == \"\" ]]; then
        err=\$(expr \$err + 1)
        sleep 1
        continue
    else
        err=0
        break
    fi
done

if [[ \$err != \"\0\" ]]; then
    echo \"systemctl stop keepalived\"
    /usr/bin/systemctl stop keepalived
    exit 1
else
    exit 0
fi
EOF"

} >> "$HOST".txt
done




for HOST in $lb;do
{
    echo "配置主机$HOST 检查脚本执行权限"
    ssh root@"$HOST" "chmod +x /etc/keepalived/check_apiserver.sh"

    echo "配置主机$HOST 开机自启"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now haproxy"
    ssh root@"$HOST" "systemctl enable --now keepalived"

} >> "$HOST".txt
done

}

function init_k8s_master() {

for HOST in $master01;do
{
    echo "配置主机$HOST api-server配置文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-apiserver.service << EOF 
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
      --v=2  \
      --logtostderr=true  \
      --allow-privileged=true  \
      --bind-address=0.0.0.0  \
      --secure-port=6443  \
      --insecure-port=0  \
      --advertise-address=$k8s_master01 \
      --service-cluster-ip-range=10.96.0.0/12  \
      --service-node-port-range=30000-32767  \
      --etcd-servers=https://$k8s_master01:2379,https://$k8s_master02:2379,https://$k8s_master03:2379 \
      --etcd-cafile=/etc/etcd/ssl/etcd-ca.pem  \
      --etcd-certfile=/etc/etcd/ssl/etcd.pem  \
      --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem  \
      --client-ca-file=/etc/kubernetes/pki/ca.pem  \
      --tls-cert-file=/etc/kubernetes/pki/apiserver.pem  \
      --tls-private-key-file=/etc/kubernetes/pki/apiserver-key.pem  \
      --kubelet-client-certificate=/etc/kubernetes/pki/apiserver.pem  \
      --kubelet-client-key=/etc/kubernetes/pki/apiserver-key.pem  \
      --service-account-key-file=/etc/kubernetes/pki/sa.pub  \
      --service-account-signing-key-file=/etc/kubernetes/pki/sa.key  \
      --service-account-issuer=https://kubernetes.default.svc.cluster.local \
      --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname  \
      --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota  \
      --authorization-mode=Node,RBAC  \
      --enable-bootstrap-token-auth=true  \
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.pem  \
      --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.pem  \
      --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client-key.pem  \
      --requestheader-allowed-names=aggregator  \
      --requestheader-group-headers=X-Remote-Group  \
      --requestheader-extra-headers-prefix=X-Remote-Extra-  \
      --requestheader-username-headers=X-Remote-User
      # --token-auth-file=/etc/kubernetes/token.csv

Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target

EOF"

} >> "$HOST".txt
done

for HOST in $master02;do
{
    echo "配置主机$HOST api-server配置文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-apiserver.service << EOF 
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
      --v=2  \
      --logtostderr=true  \
      --allow-privileged=true  \
      --bind-address=0.0.0.0  \
      --secure-port=6443  \
      --insecure-port=0  \
      --advertise-address=$k8s_master02 \
      --service-cluster-ip-range=10.96.0.0/12  \
      --service-node-port-range=30000-32767  \
      --etcd-servers=https://$k8s_master01:2379,https://$k8s_master02:2379,https://$k8s_master03:2379 \
      --etcd-cafile=/etc/etcd/ssl/etcd-ca.pem  \
      --etcd-certfile=/etc/etcd/ssl/etcd.pem  \
      --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem  \
      --client-ca-file=/etc/kubernetes/pki/ca.pem  \
      --tls-cert-file=/etc/kubernetes/pki/apiserver.pem  \
      --tls-private-key-file=/etc/kubernetes/pki/apiserver-key.pem  \
      --kubelet-client-certificate=/etc/kubernetes/pki/apiserver.pem  \
      --kubelet-client-key=/etc/kubernetes/pki/apiserver-key.pem  \
      --service-account-key-file=/etc/kubernetes/pki/sa.pub  \
      --service-account-signing-key-file=/etc/kubernetes/pki/sa.key  \
      --service-account-issuer=https://kubernetes.default.svc.cluster.local \
      --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname  \
      --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota  \
      --authorization-mode=Node,RBAC  \
      --enable-bootstrap-token-auth=true  \
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.pem  \
      --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.pem  \
      --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client-key.pem  \
      --requestheader-allowed-names=aggregator  \
      --requestheader-group-headers=X-Remote-Group  \
      --requestheader-extra-headers-prefix=X-Remote-Extra-  \
      --requestheader-username-headers=X-Remote-User 
      # --token-auth-file=/etc/kubernetes/token.csv

Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target

EOF"

} >> "$HOST".txt
done

for HOST in $master03;do
{
    echo "配置主机$HOST api-server配置文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-apiserver.service << EOF 
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
      --v=2  \
      --logtostderr=true  \
      --allow-privileged=true  \
      --bind-address=0.0.0.0  \
      --secure-port=6443  \
      --insecure-port=0  \
      --advertise-address=$k8s_master03 \
      --service-cluster-ip-range=10.96.0.0/12  \
      --service-node-port-range=30000-32767  \
      --etcd-servers=https://$k8s_master01:2379,https://$k8s_master02:2379,https://$k8s_master03:2379 \
      --etcd-cafile=/etc/etcd/ssl/etcd-ca.pem  \
      --etcd-certfile=/etc/etcd/ssl/etcd.pem  \
      --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem  \
      --client-ca-file=/etc/kubernetes/pki/ca.pem  \
      --tls-cert-file=/etc/kubernetes/pki/apiserver.pem  \
      --tls-private-key-file=/etc/kubernetes/pki/apiserver-key.pem  \
      --kubelet-client-certificate=/etc/kubernetes/pki/apiserver.pem  \
      --kubelet-client-key=/etc/kubernetes/pki/apiserver-key.pem  \
      --service-account-key-file=/etc/kubernetes/pki/sa.pub  \
      --service-account-signing-key-file=/etc/kubernetes/pki/sa.key  \
      --service-account-issuer=https://kubernetes.default.svc.cluster.local \
      --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname  \
      --enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota  \
      --authorization-mode=Node,RBAC  \
      --enable-bootstrap-token-auth=true  \
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.pem  \
      --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.pem  \
      --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client-key.pem  \
      --requestheader-allowed-names=aggregator  \
      --requestheader-group-headers=X-Remote-Group  \
      --requestheader-extra-headers-prefix=X-Remote-Extra-  \
      --requestheader-username-headers=X-Remote-User
      # --token-auth-file=/etc/kubernetes/token.csv

Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target

EOF"

} >> "$HOST".txt
done


for HOST in $Master;do
{
    echo "配置主机$HOST api-server开机自启"
    ssh root@"$HOST" "systemctl daemon-reload && systemctl enable --now kube-apiserver"

    echo "配置主机$HOST kube-controller-manager配置文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-controller-manager.service << EOF 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
      --v=2 \
      --logtostderr=true \
      --address=127.0.0.1 \
      --root-ca-file=/etc/kubernetes/pki/ca.pem \
      --cluster-signing-cert-file=/etc/kubernetes/pki/ca.pem \
      --cluster-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
      --service-account-private-key-file=/etc/kubernetes/pki/sa.key \
      --kubeconfig=/etc/kubernetes/controller-manager.kubeconfig \
      --leader-elect=true \
      --use-service-account-credentials=true \
      --node-monitor-grace-period=40s \
      --node-monitor-period=5s \
      --pod-eviction-timeout=2m0s \
      --controllers=*,bootstrapsigner,tokencleaner \
      --allocate-node-cidrs=true \
      --cluster-cidr=172.16.0.0/12 \
      --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.pem \
      --node-cidr-mask-size=24

Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target

EOF"

    echo "配置主机$HOST kube-controller-manager开机自启"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now kube-controller-manager"


    echo "配置主机$HOST kube-scheduler配置文件"
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-scheduler.service << EOF 
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
      --v=2 \
      --logtostderr=true \
      --address=127.0.0.1 \
      --leader-elect=true \
      --kubeconfig=/etc/kubernetes/scheduler.kubeconfig

Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target

EOF"

    echo "配置主机$HOST kube-scheduler开机自启"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl enable --now kube-scheduler"

} >> "$HOST".txt
done



for HOST in $master01;do
{
    echo "配置主机$HOST 免密"
    scp /root/.ssh/id_rsa root@$HOST:/root/.ssh/id_rsa
    scp /root/.ssh/id_rsa.pub  root@$HOST:/root/.ssh/id_rsa.pub

    echo "配置主机$HOST kubelet"
    ssh root@"$HOST" "cd /root/Kubernetes/bootstrap ; kubectl config set-cluster kubernetes     --certificate-authority=/etc/kubernetes/pki/ca.pem     --embed-certs=true     --server=https://$lb_vip:8443     --kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig ; kubectl config set-credentials tls-bootstrap-token-user     --token=c8ad9c.2e4d610cf3e7426e --kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig ; kubectl config set-context tls-bootstrap-token-user@kubernetes     --cluster=kubernetes     --user=tls-bootstrap-token-user     --kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig ;kubectl config use-context tls-bootstrap-token-user@kubernetes     --kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig ;mkdir -p /root/.kube ; cp /etc/kubernetes/admin.kubeconfig /root/.kube/config "

cat > 1.sh << EOF 
cd /etc/kubernetes/
for NODE in $k8s_other; do
    ssh -o StrictHostKeyChecking=no \$NODE mkdir -p /etc/kubernetes/pki
    for FILE in pki/ca.pem pki/ca-key.pem pki/front-proxy-ca.pem bootstrap-kubelet.kubeconfig; do
       scp -o StrictHostKeyChecking=no -r /etc/kubernetes/\$FILE \$NODE:/etc/kubernetes/\${FILE}
    done
done
EOF

scp 1.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/1.sh" 

echo "kubectl get 测试"
ssh root@"$HOST" "kubectl get cs ; kubectl create -f /root/Kubernetes/bootstrap/bootstrap.secret.yaml"

} >> "$HOST".txt
done


for HOST in $lb;do
{
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl restart haproxy"
    ssh root@"$HOST" "systemctl restart keepalived"

} >> "$HOST".txt
done


}

function init_k8s_all() {

for HOST in $k8s;do
{
    echo "配置主机$HOST kubelet"
    ssh root@"$HOST" "mkdir -p /var/lib/kubelet /var/log/kubernetes /etc/systemd/system/kubelet.service.d /etc/kubernetes/manifests/"

cat > 4.sh << EOF 
containerd  config default > /etc/containerd/config.toml
sed -i "s#k8s.gcr.io/pause:3.2#registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6#g" /etc/containerd/config.toml
systemctl  restart containerd
EOF

scp 4.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/4.sh" 

    echo "配置主机$HOST docker"
    ssh root@"$HOST" "cat > /etc/docker/daemon.json << EOF 
{
  \"exec-opts\": [\"native.cgroupdriver=systemd\"],
  \"registry-mirrors\": [
    \"https://docker.mirrors.ustc.edu.cn\",
    \"http://hub-mirror.c.163.com\"
  ],
  \"max-concurrent-downloads\": 10,
  \"log-driver\": \"json-file\",
  \"log-level\": \"warn\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
    },
  \"data-root\": \"/var/lib/docker\"
}
EOF" 

    ssh root@"$HOST" "systemctl  daemon-reload"
    ssh root@"$HOST" "systemctl  restart docker"




    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kubelet.service << EOF 
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.kubeconfig --kubeconfig=/etc/kubernetes/kubelet.kubeconfig --config=/etc/kubernetes/kubelet-conf.yml  --network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin --container-runtime=remote --runtime-request-timeout=15m --container-runtime-endpoint=unix:///run/containerd/containerd.sock --cgroup-driver=systemd --node-labels=node.kubernetes.io/node=''

Restart=always
StartLimitInterval=0
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF" 


    ssh root@"$HOST" "cat > /etc/kubernetes/kubelet-conf.yml << EOF 
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.pem
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
cgroupDriver: systemd
cgroupsPerQOS: true
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
containerLogMaxFiles: 5
containerLogMaxSize: 10Mi
contentType: application/vnd.kubernetes.protobuf
cpuCFSQuota: true
cpuManagerPolicy: none
cpuManagerReconcilePeriod: 10s
enableControllerAttachDetach: true
enableDebuggingHandlers: true
enforceNodeAllocatable:
- pods
eventBurst: 10
eventRecordQPS: 5
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
evictionPressureTransitionPeriod: 5m0s
failSwapOn: true
fileCheckFrequency: 20s
hairpinMode: promiscuous-bridge
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 20s
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m0s
iptablesDropBit: 15
iptablesMasqueradeBit: 14
kubeAPIBurst: 10
kubeAPIQPS: 5
makeIPTablesUtilChains: true
maxOpenFiles: 1000000
maxPods: 110
nodeStatusUpdateFrequency: 10s
oomScoreAdj: -999
podPidsLimit: -1
registryBurst: 10
registryPullQPS: 5
resolvConf: /etc/resolv.conf
rotateCertificates: true
runtimeRequestTimeout: 2m0s
serializeImagePulls: true
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 4h0m0s
syncFrequency: 1m0s
volumeStatsAggPeriod: 1m0s
EOF" 

    echo "启用主机$HOST kubelet"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" "systemctl restart kubelet"
    ssh root@"$HOST" "systemctl enable --now kubelet"

} >> "$HOST".txt
done



for HOST in $master01;do
{
echo "配置主机$HOST kube-proxy"
cat > 2.sh << EOF 
cd /root/Kubernetes/
kubectl -n kube-system create serviceaccount kube-proxy

kubectl create clusterrolebinding system:kube-proxy         --clusterrole system:node-proxier         --serviceaccount kube-system:kube-proxy

SECRET=\$(kubectl -n kube-system get sa/kube-proxy --output=jsonpath='{.secrets[0].name}')

JWT_TOKEN=\$(kubectl -n kube-system get secret/\$SECRET --output=jsonpath='{.data.token}' | base64 -d)

PKI_DIR=/etc/kubernetes/pki
K8S_DIR=/etc/kubernetes

kubectl config set-cluster kubernetes     --certificate-authority=/etc/kubernetes/pki/ca.pem     --embed-certs=true     --server=https://$lb_vip:8443     --kubeconfig=\${K8S_DIR}/kube-proxy.kubeconfig

kubectl config set-credentials kubernetes     --token=\${JWT_TOKEN}     --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig

kubectl config set-context kubernetes     --cluster=kubernetes     --user=kubernetes     --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig

kubectl config use-context kubernetes     --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig

for NODE in $k8s_other; do
     scp /etc/kubernetes/kube-proxy.kubeconfig  \$NODE:/etc/kubernetes/kube-proxy.kubeconfig
done



EOF

scp 2.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/2.sh" 


} >> "$HOST".txt
done




for HOST in $k8s;do
{
    ssh root@"$HOST" "cat > /usr/lib/systemd/system/kube-proxy.service << EOF 
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy --config=/etc/kubernetes/kube-proxy.yaml --v=2

Restart=always
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF" 

    ssh root@"$HOST" "cat > /etc/kubernetes/kube-proxy.yaml << EOF 
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
clientConnection:
  acceptContentTypes: \"\"
  burst: 10
  contentType: application/vnd.kubernetes.protobuf
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
  qps: 5
clusterCIDR: 172.16.0.0/12 
configSyncPeriod: 15m0s
conntrack:
  max: null
  maxPerCore: 32768
  min: 131072
  tcpCloseWaitTimeout: 1h0m0s
  tcpEstablishedTimeout: 24h0m0s
enableProfiling: false
healthzBindAddress: 0.0.0.0:10256
hostnameOverride: \"\"
iptables:
  masqueradeAll: false
  masqueradeBit: 14
  minSyncPeriod: 0s
  syncPeriod: 30s
ipvs:
  masqueradeAll: true
  minSyncPeriod: 5s
  scheduler: \"rr\"
  syncPeriod: 30s
kind: KubeProxyConfiguration
metricsBindAddress: 127.0.0.1:10249
mode: \"ipvs\"
nodePortAddresses: null
oomScoreAdj: -999
portRange: \"\"
udpIdleTimeout: 250ms
EOF" 

    echo "启用主机$HOST kube-proxy"
    ssh root@"$HOST" "systemctl daemon-reload"
    ssh root@"$HOST" " systemctl enable --now kube-proxy"

} >> "$HOST".txt
done



for HOST in $master01;do
{

echo "配置$HOST calico"
cat > 3.sh << EOF 
cd /root/Kubernetes/calico/
sed -i "s#POD_CIDR#172.16.0.0/12#g" calico.yaml
kubectl apply -f calico.yaml
EOF

scp 3.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/3.sh" 

} >> "$HOST".txt
done

for HOST in $master01;do
{

echo "配置$HOST CoreDNS"
cat > 5.sh << EOF 
cd /root/Kubernetes/CoreDNS/
sed -i "s#KUBEDNS_SERVICE_IP#10.96.0.10#g" coredns.yaml
kubectl  apply -f coredns.yaml
EOF

scp 5.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/5.sh" 


} >> "$HOST".txt
done


for HOST in $master01;do
{

echo "配置$HOST metrics-server"
cat > 6.sh << EOF 
cd /root/Kubernetes/metrics-server/
kubectl  apply -f .
EOF

scp 6.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/6.sh" 


} >> "$HOST".txt
done


for HOST in $master01;do
{

echo "配置$HOST dashboard"
cat > 7.sh << EOF 
cd /root/Kubernetes/dashboard/
kubectl  apply -f dashboard-user.yaml
kubectl  apply -f dashboard.yaml
kubectl apply -f admin.yaml -n kube-system
kubectl get svc kubernetes-dashboard -n kubernetes-dashboard
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')
EOF

scp 7.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/7.sh" 


} >> "$HOST".txt
done


for HOST in $master01;do
{

echo "配置$HOST 自动补全"
cat > 8.sh << EOF 
yum install bash-completion -y
source /usr/share/bash-completion/bash_completion
source <(kubectl completion bash)
echo "source <(kubectl completion bash)" >> ~/.bashrc
EOF

scp 8.sh root@$HOST:

ssh root@"$HOST" "bash -x /root/8.sh" 


} >> "$HOST".txt
done


}


set_local
init_all
Containerd
init_local
init_etcd
init_ha_keep
init_k8s_master
init_k8s_all