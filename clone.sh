#!/usr/bin/env bash
# -------------------------------------------------------
DISKS=0
DOM=example.com
NUMBER=0
if [[ "$1" = "undercloud" || "$1" = "standalone" ]]; then
    if [[ $2 =~ ^[0-9]+$ ]]; then
	  NUMBER=$2
    else
	  NUMBER=1
    fi
    echo "cloning one $1"
    IP=192.168.122.252
    RAM=11718750
    CPU=4
fi
if [[ "$1" = "ceph" ]]; then
    NUMBER=1
    DISKS=3
    echo "cloning one $1"
    IP=192.168.122.253
    RAM=7812500
    CPU=2
fi
if [[ "$1" = "overcloud" || "$1" = "node" ]]; then
    if [[ $2 =~ ^[0-9]+$ ]]; then
	NUMBER=$2
    else
	NUMBER=1
    fi
    if [[ $3 =~ ^[0-9]+$ ]]; then
	CPU=$3
    else
	CPU=2
    fi
    echo "Cloning $NUMBER $1 VM(s) w/ $CPU CPUs"
    IP=192.168.122.251
    RAM=11718750
    CPU=4
    #RAM=7812500
    #CPU=2
fi
if [[ "$4" = "fedora28" ]]; then
    SRC="fedora28"
else
    SRC="centos"
fi
if [[ ! $NUMBER -gt 0 ]]; then
    echo "Usage: $0 <undercloud|standalone|overcloud|node> [<number of overcloud nodes (default 1)>]"
    echo "[<number of CPUs (default 2)>] [<centos|fedora28> (default centos)>]"
    exit 1
fi
# -------------------------------------------------------
SSH_OPT="-o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null"
KEY=$(cat ~/.ssh/id_rsa.pub)
cat /dev/null > /tmp/hosts
for i in $(seq 0 $(( $NUMBER - 1 )) ); do
    if [[ "$1" = "undercloud" || "$1" = "standalone" || "$1" = "ceph" ]]; then
	NAME=$1
    else
	NAME=$1$i
    fi
    IPDEC="IPADDR=$IP"
    if [[ -e /var/lib/libvirt/images/$NAME.qcow2 ]]; then
	echo "Destroying old $NAME"
	if [[ $(sudo virsh list | grep $NAME) ]]; then
	    sudo virsh destroy $NAME
	fi
	sudo virsh undefine $NAME
	sudo rm -f -v /var/lib/libvirt/images/$NAME.qcow2
        for D in $(sudo ls /var/lib/libvirt/images/ | grep $NAME-disk); do
            sudo rm -f -v /var/lib/libvirt/images/$D
        done
	sudo sed -i "/$IP.*/d" /etc/hosts
    fi
    sudo virt-clone --original=$SRC --name=$NAME --file /var/lib/libvirt/images/$NAME.qcow2

    sudo virsh setmaxmem $NAME --size $RAM --config
    sudo virsh setmem $NAME --size $RAM --config
    sudo virsh setvcpus $NAME --count $CPU --maximum --config
    sudo virsh setvcpus $NAME --count $CPU --config

    sudo virt-customize -a /var/lib/libvirt/images/$NAME.qcow2 --run-command "SRC_IP=\$(grep IPADDR /etc/sysconfig/network-scripts/ifcfg-eth1) ; sed -i s/\$SRC_IP/$IPDEC/g /etc/sysconfig/network-scripts/ifcfg-eth1"

    if [[ $DISKS -gt 0 ]]; then
        echo "Adding $DISKS disks"
        for J in $(seq 1 $(( $DISKS )) ); do
            L=$(echo $J | tr 0123456789 abcdefghij)
            sudo qemu-img create -f raw /var/lib/libvirt/images/$NAME-disk-$L.img 10G
            sudo virsh attach-disk $NAME --config /var/lib/libvirt/images/$NAME-disk-$L.img vd$L
        done
    fi

    if [[ ! $(sudo virsh list | grep $NAME) ]]; then
	sudo virsh start $NAME
    fi
    echo "Waiting for $NAME to boot and allow to SSH at $IP"
    while [[ ! $(ssh $SSH_OPT root@$IP "uname") ]]
    do
	echo "No route to host yet; sleeping 30 seconds"
	sleep 30
    done

    if [[ "$1" = "node" ]]; then
        ssh $SSH_OPT root@$IP "hostname $NAME ; echo HOSTNAME=$NAME >> /etc/sysconfig/network"
        # add the IP to the hypervisor /etc/hosts but not the VM /etc/hosts
        sudo sh -c "echo $IP    $NAME >> /etc/hosts"
        ssh $SSH_OPT root@$IP "hostnamectl set-hostname $NAME"
        ssh $SSH_OPT root@$IP "echo nameserver 8.8.8.8 >> /etc/resolv.conf"
        ssh $SSH_OPT root@$IP "echo nameserver 8.8.4.4 >> /etc/resolv.conf"
        sudo sh -c "echo $IP    $NAME >> /tmp/hosts"
    else
        ssh $SSH_OPT root@$IP "hostname $NAME.$DOM ; echo HOSTNAME=$NAME.$DOM >> /etc/sysconfig/network"
        ssh $SSH_OPT root@$IP "echo \"$IP    $NAME.$DOM        $NAME\" >> /etc/hosts "
        sudo sh -c "echo $IP    $NAME.$DOM        $NAME >> /etc/hosts"
    fi
    echo "$NAME is ready"
    ssh stack@$NAME "uname -a"
    echo ""
    echo "ssh stack@$NAME"
    echo ""

    # decrement the IP by one for the next loop
    TAIL=$(echo $IP | awk -F  "." '/1/ {print $4}')
    HEAD=$(echo $IP | sed s/$TAIL//g)
    TAIL=$(( TAIL - 1))
    IP=$HEAD$TAIL
done

if [[ "$1" = "node" ]]; then
    NAME=node0
fi


if [[ $NAME == "undercloud" || $NAME == "standalone" || $NAME == "overcloud0" || $NAME == "ceph" ]]; then
    # install repos for centos9
    scp $SSH_OPT repos/* stack@$NAME:/tmp/
    ssh $SSH_OPT root@$NAME "mv /tmp/*.repo /etc/yum.repos.d/"

    echo "" > git.sh
    echo "sudo yum install -y tmux vim git" >> git.sh
    echo "ssh-keyscan github.com >> ~/.ssh/known_hosts" >> git.sh
    #echo "git clone git@github.com:averdagu/tripleo-laptop.git" >> git.sh
    echo "git clone git@github.com:averdagu/zed.git --config core.sshCommand='ssh -i ~/.ssh/upstream_gerrit'" >> git.sh

    scp $SSH_OPT git.sh stack@$NAME:/home/stack/
    ssh $SSH_OPT stack@$NAME "chmod 755 git.sh"
    rm git.sh
    if [[ $NAME == "node0" ]]; then
        scp $SSH_OPT /tmp/hosts stack@$NAME:/home/stack/hosts
        rm -f /tmp/hosts
    fi
fi
