#!/bin/bash

# Determine root access
if [ $EUID = 0 ]; then 
  #Ask for optional e-mail
  EMAIL=''
  echo -e '\nYou may optionally provide your e-mail to manage your node'
  echo -e 'via https://IPFSPodcasting.net/Manage to favorite feeds.\n'
  while true; do
    read -p 'Enter your e-mail (or enter for none): ' OMAIL
    if [ "${OMAIL}" = "" ]; then break
    else
      # E-mail REGEX
      REGEX="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
      if [[ "${OMAIL}" =~ $REGEX ]]; then
        EMAIL="${OMAIL}"
        break
      else 
        echo '*** Invalid E-Mail (try again) ***'
      fi
    fi
  done  

  # Install wget, python3, pip, requests (if required)
  if [ $(which crontab &> /dev/null; echo $?) != 0 ]; then 
    # Ugh, cron is not installed on a minimal Ubuntu server
    echo 'Installing cron...'
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install cron
  fi
  if [ $(wget -V &> /dev/null; echo $?) != 0 ]; then 
    echo 'Installing wget...'
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install wget
  fi
  if [ $(python3 -V &> /dev/null; echo $?) != 0 ]; then 
    echo 'Installing python3...'
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install python3
  fi
  if [ $(pip -V &> /dev/null; echo $?) != 0 ]; then 
    echo 'Installing python3-pip...'
    apt-get -y -qq update
    DEBIAN_FRONTEND=noninteractive apt-get -y -qq install python3-pip
  fi
  if [ $(pip list|grep requests &> /dev/null; echo $?) != 0 ]; then 
    echo 'Installing PIP Requests Module...'
    pip -q install requests
  fi
  #Install IPFS-Update (if required)
  if [ $(ipfs-update --version &> /dev/null; echo $?) != 0 ]; then 
    echo 'Installing IPFS...'
    # Determine OS Architecture
    ARCH=$(uname -i)
    if [ $ARCH = 'unknown' ]; then ARCH=$(uname -m); fi
    if [ $ARCH = 'x86_64' ]; then ARCH='amd64'
    elif [ $ARCH = 'aarch64*' ]; then ARCH='arm64'
    elif [ $ARCH = 'x86_32' ]; then ARCH='386'
    elif [ $ARCH = 'aarch32*' ]; then ARCH='arm'
    fi
    # Link for ipfs-update installer
    IPFS_UPDATE_LINK="https://dist.ipfs.io/ipfs-update/v1.8.0/ipfs-update_v1.8.0_linux-$ARCH.tar.gz"
    IPFS_UPDATE_FILE=${IPFS_UPDATE_LINK##*/}
    #Download, extract, install, and initialize
    runuser -l $SUDO_USER -c "wget -O /home/${SUDO_USER}/${IPFS_UPDATE_FILE} ${IPFS_UPDATE_LINK}"
    runuser -l $SUDO_USER -c "tar -xzf /home/${SUDO_USER}/${IPFS_UPDATE_FILE}"
    mv /home/${SUDO_USER}/ipfs-update/ipfs-update /usr/local/bin/
    rm -rf /home/${SUDO_USER}/ipfs-update*
  fi

  #Update/Install IPFS
  ipfs-update install latest
  if [[ ! -f "/home/$SUDO_USER/.ipfs/config" ]]; then runuser -l $SUDO_USER -c "ipfs init"; fi

  # Grab latest IPFS Podcasting script and make executable
  runuser -l $SUDO_USER -c "wget -O /home/${SUDO_USER}/ipfspodcastnode.py https://ipfspodcasting.net/modules/mjc/src/ipfspodcast/ipfspodcastnode.py"
  runuser -l $SUDO_USER -c "chmod +x /home/${SUDO_USER}/ipfspodcastnode.py"

  # Create/edit crontab to run IPFS Podcasting script every 10 minutes
  if [[ -f "/var/spool/cron/crontabs/$SUDO_USER" ]]; then
    #Save current crontab (and try to exclude any existing IPFS Podcasting task)
    sudo -u $SUDO_USER crontab -l | grep -v ipfspodcastnode.lockfile > mycron
    #Add new task
    echo -e "*/10 * * * * cd ~/ && /usr/bin/flock -n /tmp/ipfspodcastnode.lockfile ~/ipfspodcastnode.py ${EMAIL}\n" >> mycron
    #Install cron file
    sudo -u $SUDO_USER crontab mycron
    rm mycron
  else
    sudo -u $SUDO_USER crontab -l > mycron
    #Create new cron file w/IPFS Podcasting task
    echo -e "# Edit this file to introduce tasks to be run by cron.
# 
# Each task to run has to be defined through a single line
# indicating with different fields when the task will be run
# and what command to run for the task
# 
# To define the time you can provide concrete values for
# minute (m), hour (h), day of month (dom), month (mon),
# and day of week (dow) or use '*' in these fields (for 'any').
# 
# Notice that tasks will be started based on the cron's system
# daemon's notion of time and timezones.
# 
# Output of the crontab jobs (including errors) is sent through
# email to the user the crontab file belongs to (unless redirected).
# 
# For example, you can run a backup of all your user accounts
# at 5 a.m every week with:
# 0 5 * * 1 tar -zcf /var/backups/home.tgz /home/
# 
# For more information see the manual pages of crontab(5) and cron(8)
# 
# m h  dom mon dow   command
*/10 * * * * cd ~/ && /usr/bin/flock -n /tmp/ipfspodcastnode.lockfile ~/ipfspodcastnode.py ${EMAIL}" >> mycron
    #Install new cron file
    sudo -u $SUDO_USER crontab mycron
    rm mycron
  fi

  #Start IPFS
  runuser -l $SUDO_USER -c "ipfs daemon &"
  sleep 5

  echo -e '\nInstallation Finished\n'
  echo 'Thanks for supporting podcasting over IPFS.'
  echo 'You can "tail -f ipfspodcastnode.log" to view activity,'
  if [ "${EMAIL}" != "" ]; then echo 'Or manage your node at https://IPFSPodcasting.net/Manage'; fi
  echo

else 
  echo -e '\nAdministrator access is required to install IPFS, wget, and python.\n'
  echo -e 'Please run with "sudo bash ipfspodcasting-install.sh"\n'
  exit 1
fi
