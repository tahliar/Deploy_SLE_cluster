#!/bin/sh
#########################################################
#
#
#########################################################
## INIT nodes / SOME CHECKS
#########################################################
# all is done from the Host


if [ -f `pwd`/functions ] ; then
    . `pwd`/functions
else
    echo "! need functions in current path; Exiting"; exit 1
fi
check_load_config_file


fix_hostname() {
    echo "############ START fix_hostname"
    for i in `seq 1 $NBNODE`
    do
	exec_on_node ${NODENAME}${i} "hostname > /etc/hostname"
    done
}


# Check cluster Active

# Init the cluster on node ${NODENAME}1
init_cluster() {
    echo "############ START init the cluster"
}

copy_ssh_key_on_nodes() {
    echo "############ START copy_ssh_key_on_nodes"
    echo "- Generate ssh ssh root key on node ${NODENAME}1"
    exec_on_node ${NODENAME}1 "ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa"
    echo "- Copy ssh root key from node ${NODENAME}1 to all nodes"
    scp -o StrictHostKeyChecking=no root@${NODENAME}1:~/.ssh/id_rsa.pub /tmp/
    scp -o StrictHostKeyChecking=no root@${NODENAME}1:~/.ssh/id_rsa /tmp/
    for i in `seq 2 $NBNODE`
    do
	scp_on_node "/tmp/id_rsa*" "${NODENAME}${i}:/root/.ssh/"
    done
    rm -vf /tmp/id_rsa*
    for i in `seq 2 $NBNODE`
    do
	exec_on_node ${NODENAME}${i} "grep 'Cluster Internal' /root/.ssh/authorized_keys || cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys"
    done
}

ganglia_web() {
    echo "############ START ganglia_web"
    echo "- Enable php7 and restart apache2"
    exec_on_node  ${NODENAME}1 "a2enmod php7"
    exec_on_node  ${NODENAME}1 "systemctl enable apache2"
    exec_on_node  ${NODENAME}1 "systemctl restart apache2"
    exec_on_node  ${NODENAME}1 "systemctl restart gmetad"
    for i in `seq 1 $NBNODE`
    do
	echo "- Enable gmond and restart it"
	exec_on_node ${NODENAME}${i} "systemctl enable gmond"
	exec_on_node ${NODENAME}${i} "systemctl restart gmond"
    done
    echo "- You can access Ganglia Web page at:"
    echo "http://${NODENAME}1/ganglia-web/"

}

slurm_configuration() {

    echo "############ START create a slurm_configuration"

    echo "- Get /etc/slurm/slurm.conf from ${NODENAME}1"
    scp root@${NODENAME}1:/etc/slurm/slurm.conf .

    for i in `seq 1 $NBNODE`
    do
	NODE_LIST="$NODE_LIST,${NODENAME}${i}"
    done
    echo $NODE_LIST

    echo "- Prepare slurm.con file"
    perl -pi -e "s/ClusterName.*/ClusterName=linuxsuse/g" slurm.conf
    perl -pi -e "s/ControlMachine.*/ControlMachine=${NODENAME}1/" slurm.conf

    echo "- Copy slurm.conf on all nodes" 
    for i in `seq 1 $NBNODE`
    do
	scp_on_node slurm.conf "${NODENAME}${i}:/etc/slurm/"
    done

    echo "- Enable and start slurmctld/munge on all nodes"
    for i in `seq 1 $NBNODE`
    do
# slurmd -C
# NodeName=sle15hpc1 CPUs=2 Boards=1 SocketsPerBoard=2 CoresPerSocket=1 ThreadsPerCore=1 RealMemory=1985
	exec_on_node ${NODENAME}${i} "perl -pi -e 's/NodeName.*/NodeName=${NODENAME}[1-${NBNODE}] State=UNKNOWN CoresPerSocket=2 Sockets=2/' /etc/slurm/slurm.conf"
	exec_on_node ${NODENAME}${i} "perl -pi -e 's/PartitionName.*/PartitionName=normal Nodes=${NODENAME}[1-${NBNODE}] Default=YES MaxTime=24:00:00 State=UP/' /etc/slurm/slurm.conf"
	exec_on_node ${NODENAME}${i} "rm /var/lib/slurm/clustername"
	exec_on_node ${NODENAME}${i} "systemctl stop slurmd"
	exec_on_node ${NODENAME}${i} "systemctl stop slurmctld"
	exec_on_node ${NODENAME}${i} "systemctl enable slurmd"
	exec_on_node ${NODENAME}${i} "systemctl start slurmd"
	exec_on_node ${NODENAME}${i} "systemctl enable slurmctld"
	exec_on_node ${NODENAME}${i} "systemctl start slurmctld"
    done

    echo "- Check with sinfo on node ${NODENAME}1"
    exec_on_node ${NODENAME}1 "sinfo"
    exec_on_node ${NODENAME}1 "scontrol update NodeName=sle15hpc[1-${NBNODE}] State=UNDRAIN"
#scontrol show job
#scontrol show node sle15hpc4
#scontrol show partition
}

munge_key() {
echo "############ START munge_key"
    scp ${NODENAME}1:/etc/munge/munge.key .
    for i in `seq 2 $NBNODE`
    do
        scp_on_node munge.key "${NODENAME}${i}:/etc/munge/munge.key"
	exec_on_node ${NODENAME}${i} "chown munge.munge /etc/munge/munge.key && sync"
	exec_on_node ${NODENAME}${i} "systemctl enable munge"
	exec_on_node ${NODENAME}${i} "systemctl restart munge"
    done
    rm -vf munge.key
}

scp_nodes_list() {
    echo "############ START scp_nodes_list"
    echo "- Create nodes file"
    NODESF=/tmp/nodes
    touch ${NODESF}
    for i in `seq 1 $NBNODE`
    do
        echo ${NODENAME}${i} >> ${NODESF}
    done
    echo "- scp nodes file on all nodes"
    for i in `seq 1 $NBNODE`
    do
        scp_on_node ${NODESF} "${NODENAME}${i}:/etc/nodes"
    done
    rm -v ${NODESF}
}
 

##########################
##########################
### MAIN
##########################
##########################


case "$1" in
    hostname)
	fix_hostname
	;;
    sshkeynode)
	copy_ssh_key_on_nodes
	;;
    munge)
	munge_key
	;;
    slurm)
	slurm_configuration
	;;
    ganglia)
	ganglia_web
	;;
    nodeslist)
    scp_nodes_list
    ;;
    all)
    fix_hostname
    scp_nodes_list
    munge_key
    slurm_configuration
    ganglia_web
	;;
    *)
        echo "
     Usage: $0 {hostname|nodeslist|ganglia|sshkeynode|slurm|munge|all}

 hostname
    fix /etc/hostname on all nodes

 slurm
    configure slurm on all nodes (and enable and start the service)

 munge
    copy munger.key from ${NODENAME}1 to all other nodes

 ganglia
    configure apache and get ganglia up

 nodeslist
    copy the full nodes list to all nodes in /etc/nodes file

 sshkeynode
    Copy Cluster Internal key (from ${NODENAME}1) to all other HA nodes

 all 
    run all in this order
"
        exit 1
esac


