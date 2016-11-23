#!/bin/sh

yum -y install wget tar sudo which

mkdir -p /var/spool/joboutputs

# Set the hostname if available; display otherwise
date --utc +"%Y-%m-%d %H:%M:%S %Z user_data_script Start user_data on `hostname`"

# Record MJFJO if substituted here by VM lifecycle manager
export MACHINEFEATURES='/tmp/machinefeatures'
export JOBFEATURES='/tmp/jobfeatures'
export JOBOUTPUTS='/tmp/joboutputs'
mkdir -p $MACHINEFEATURES $JOBFEATURES $JOBOUTPUTS

# Save whatever we use by other scripts
cat /input/lhcbhost.pem > /root/hostkey.pem

export CE_NAME='y.yandex.ru'
export VM_UUID=`date +'%s'`


mkdir -p /scratch
chmod ugo+rwxt /scratch

mkdir -p /scratch/tmp
chmod ugo+rwxt /scratch/tmp

# Get CA certs from cvmfs
rm -Rf /etc/grid-security
ln -sf /cvmfs/grid.cern.ch/etc/grid-security /etc/grid-security


# We swap on the logical partition (cannot on CernVM 3 aufs filesystem)
# Since ext4 we can use fallocate:
# fallocate -l 4g /scratch/swapfile
# chmod 0600 /scratch/swapfile
# mkswap /scratch/swapfile
# swapon /scratch/swapfile

# Swap as little as possible
# sysctl vm.swappiness=1

# Log proxies used for cvmfs
# attr -g proxy /cvmfs/lhcb.cern.ch/

# Avoid age-old sudo problem
echo 'Defaults !requiretty' >>/etc/sudoers
echo 'Defaults visiblepw'   >>/etc/sudoers
echo 'Defaults    env_keep += "X509_CERT_DIR"' >>/etc/sudoers # SLC6 image workaround

# The pilot user account plt
/usr/sbin/useradd -b /scratch plt

chown plt.plt /var/spool/joboutputs
chmod 0755 /var/spool/joboutputs

mkdir -p /scratch/plt/etc/grid-security
cp /root/hostkey.pem /scratch/plt/etc/grid-security/hostkey.pem
cp /root/hostkey.pem /scratch/plt/etc/grid-security/hostcert.pem
chmod 0600 /scratch/plt/etc/grid-security/host*.pem

# Add plt0102 etc accounts for the payloads that plt can sudo to
# At most one jobagent per logical processor
processors=`grep '^processor[[:space:]]' /proc/cpuinfo | wc --lines`
for ((m=0; m < processors; m++))
do
  # Up to 100 successive payloads per jobagent
  for ((n=0; n < 100; n++))
  do
    payloaduser=`printf 'plt%02dp%02d' $m $n`
    payloaduserid=`printf '1%02d%02d' $m $n`

    # Payload user home directory and dot files
    mkdir /scratch/$payloaduser
    cp -n /etc/skel/.*shrc /scratch/$payloaduser
    cp -n /etc/skel/.bash* /scratch/$payloaduser

    # Add to /etc/passwd and /etc/group
    echo "$payloaduser:x:$payloaduserid:$payloaduserid::/scratch/$payloaduser:/bin/bash" >>/etc/passwd
    echo "$payloaduser:x:$payloaduserid:plt" >>/etc/group

    # Add the plt group as a secondary group
    if [ "$payloaduser" = "plt00p00" ] ; then
      sed -i "s/^plt:.*/&$payloaduser/" /etc/group
    else
      sed -i "s/^plt:.*/&,$payloaduser/" /etc/group
    fi

    # Ownership and permissions of payload home directory
    chown -R $payloaduser.$payloaduser /scratch/$payloaduser
    chmod 0775 /scratch/$payloaduser

    # plt user can sudo to any payload user
    echo "Defaults>$payloaduser !requiretty"           >>/etc/sudoers
    echo "Defaults>$payloaduser visiblepw"             >>/etc/sudoers
    echo "Defaults>$payloaduser !env_reset"            >>/etc/sudoers
    echo "plt ALL = ($payloaduser) NOPASSWD: ALL"      >>/etc/sudoers
  done
done

cd /scratch/plt
# Fetch the DIRAC pilot scripts
wget --no-directories --recursive --no-parent --execute robots=off --reject 'index.html*' --ca-directory=/etc/grid-security/certificates https://lhcb-portal-dirac.cern.ch/pilot/


# So payload accounts can create directories here, but not interfere
chown -R plt.plt /scratch/plt
chmod 1775 /scratch/plt

# Now run the pilot script
/usr/bin/sudo -n -u plt \
 X509_USER_PROXY=/scratch/plt/etc/grid-security/hostkey.pem \
 JOB_ID="y.yandex.ru:$VM_UUID:docker" \
 MACHINEFEATURES="$MACHINEFEATURES" JOBFEATURES="$JOBFEATURES" \
 python /scratch/plt/dirac-pilot.py \
 --debug \
 -o '/LocalSite/SubmitPool=Test' \
 --Name 'y.yandex.ru' \
 --Queue default \
 --MaxCycles 1 \
 --CEType Sudo \
 --cert \
 --certLocation=/scratch/plt/etc/grid-security \
 >/output/dirac-pilot.log 2>&1

# Save JobAgent and System logs
cp -f /scratch/plt/jobagent.*.log /scratch/plt/shutdown_message* /var/log/boot.log /var/log/dmesg /var/log/secure /var/log/messages* /etc/cvmfs/default.* \
  /output
