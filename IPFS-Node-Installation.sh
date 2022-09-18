# Copyright (C) 2022  CaffeinatedDNB (github)

# The programs generated and documentation provided are 
# distributed in the hope that it will be useful, but 
# WITHOUT ANY WARRANTY; without even the implied warranty 
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 

# See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public 
# License along with this program. If not, 
# see <https://www.gnu.org/licenses/gpl-3.0.html>.

# -- End of Licensing Information ---

# To be done via Hosted VPS Web console or whatever
# console you're using; VM or dedicated computer. 


# Tested on new VPS instances of Debian 11 and Ubuntu Server 20.04.5 LTS
# It creates a user called "ipfs" with sudo privileges so the IPFS daemon doesn't run as root.
# When IPFS node is up and running, always switch to "ipfs" user when you SSH in to work with the IPFS install.
# Use: "su - ipfs" (For clarification: that's "su [space] - [space] ipfs" and then press ENTER key)


# CHANGE default SSH port and restart SSHd service

# For the non-initiated, which we all are at one point or
# another in life, here's a breakdown of the sed command below

# sed -i (for in-file replace)
# s/ is to search and replace
# #Port 22 is what to search for
# Port 2222 is what to replace it with
# /I tells sed to a case-insensitive search which is helpful
# and ensures replacement happens

# -- Copy and paste the following into your terminal session
# It's all in one line!

# NOTE: Many web-based terminal consoles are horrible when it comes to copy
# and paste operations which is why it's all in one line. Depending on the
# platform you're working with, you may not be able to right-click to paste.
# Instead, you may have to press Ctrl V after clicking into ther 

# sed -i "s/#Port 22/Port 2222/I" /etc/ssh/sshd_config && sudo service sshd reload && sleep 3 && sudo service sshd restart

# Change to systemctl in place of service was submitted by "suorcd"

sed -i "s/#Port 22/Port 2222/I" /etc/ssh/sshd_config && systemctl sshd restart

# -- End of copy and paste section

# NOTE: Before proceeding, please ensure you have your INBOUND firewall
# rules are setup to better protect your server and IPFS instance
# ahead of time.  In particular, the various IPFS API services that run that
# don't need to be exposed to the internet nor should they.
#
# Generally, many will be running their IPFS nodes from a VPS provider
# so read up on their documentation on configuring the firewall 
#
# Create custom rule for SSH as you should change default port
# SSHD - TCP Port [whatever port you chose]
#
# Swarm_Port - TCP Port 4001 (needed for the IPFS Swarm Port)
#
# Suggested INBOUND settings for a more secure instance:
#
# Default Inbound Policy - Set to DENY
#
# SKIP READING this UFW section if you have a web-based firewall console
#
# -- Begin UFW firewall section --
# If using ufw to configure the firewall, you can use the following
# commands to set the policies mentioned above.
# 
# To check if it's running or not (usually disabled by default)
#
# sudo ufw status
#
# sudo ufw allow [ssh port number of choice]/tcp
# example: sudo ufw allow 2222/tcp 
#
# sudo ufw allow 4001/tcp
#
# sudo ufw default deny incoming
#
# The following will enable the firewall and warn you that it may
# disrupt existing ssh connections.
#
# FYI: Although a Hosted VPS helps by having a web shell, it's 
# important to keep in mind, from an administrative stand point, 
# to add your inbound rules FIRST before the setting default to 
# deny or you will lose connectivity.
#
# sudo ufw enable
#
# -- End UFW firewall section --

#--- Once you connect via SSH using PuTTY or other client, create script in /tmp folder ---

# Using a text editor of choice and call it whatever you want.  

# Example:
# nano /tmp/onramp.sh
#
# NOTE: If you're not too familiar with the various text editors, use nano.
#
# Once you copy and paste the text into the editor, press Ctrl O (as in letter o) and then
# press ENTER key to save file then press Ctrl X to exit.

# --- IMPORTANT ---
# NOTE: MODIFY SSHD_PORT_NUM variable below with the SSH port you decided on BEFORE proceeding!
# --- IMPORTANT ---
#
# -- COPY AND PASTE EVERYTHING BELOW INTO SCRIPT

#!/bin/bash

SSHD_PORT_NUM=2222

# Work to do under root first

clear

# Set text color the light green
echo -e "\033[1;92mChecking for available system updates..."

# Set text color to bright white
echo -e '\033[0;97m'

# Note: the -qq option is to reduce terminal output of what's 
# going on when the apt command runs

# Adding Universe repository in the event it's not active
# so fail2ban and related packages don't fail

add-apt-repository -y universe

apt update -qq && apt -y -qq upgrade

# Install the following tools to help with system administration
#
# net-tools - has commands like ifconfig, netstat to view port bindings 
# (e.g. like SSH on the port you changed it to)
#
# fail2ban - For *nix admins, this is a given. For the rest, this is a must to secure your system against brute force attacks, etc
#
# tmux - provides the ability to run multiple sessions from one ssh connection (invaluable in my opinion)
# as you can run a process via an ssh connection that will keep running in the background even when you
# disconnect.  
#
# I kindly suggest learning about what each of these tools do and how to use them to further your admin skills

apt -y -qq install net-tools fail2ban tmux

# Setting color the light green
echo
echo -e "\033[1;92mYou'll be asked to assign a password.  Afterwards, no need to fill out"
echo -e "\033[1;92many of the other fields.  Just press ENTER key to skip through them."
echo -e "\033[1;92mThe last step is a Y/n prompt.  Press ENTER again as the default answer"
echo -e "\033[1;92m(That being Y)"
echo
echo -e "\033[1;92mNOTE: This user will be DENIED access via SSH later in the script so you"
echo -e "\033[1;92mdon't have to create a complex password unnecessarily.  "
echo -e "\033[1;92mThat being said, WRITE IT DOWN!"
echo

# Setting color to bright white
echo -e '\033[0;97m'

# Take a wild guess what this next step does.  :-)  

adduser ipfs

# This adds the newly created user to the sudo group to allow admin related functions if needed 
# Which it will be when the script triggers the installation of IPFS

usermod -aG sudo ipfs

# CREATE Systemd Service file for IPFS
# ------
# This is critical as I ran into an issue where the IPFS daemon wasn't starting up after reboot
#
# Note: This system service is only used to start up ipfs daemon.
#
# To stop it, use the following command under the ipfs user.
# if under the "root" user, switch to the ipfs user:
# su - ipfs 
# ipfs shutdown
#
# Source of ipfs.service file documentation and credit to:
# https://www.maxlaumeister.com/u/run-ipfs-on-boot-ubuntu-debian/
#

# ---

cat > /etc/systemd/system/ipfs.service<< EOF
[Unit]
Description=IPFS daemon
After=network.target

[Service]
### Uncomment the following line for custom ipfs datastore location
# Environment=IPFS_PATH=/path/to/your/ipfs/datastore
User=ipfs
ExecStart=/usr/local/bin/ipfs daemon
Restart=on-failure

[Install]
WantedBy=default.target

EOF

# ---


# APPEND the following line to DENY new ipfs user SSH access
# Very important so you don't have to worry about setting a complex password
# for the IPFS user

cat >> /etc/ssh/sshd_config<< EOF

#Added during IPFS installation
DenyUsers ipfs

EOF

# CREATE Fail2Ban Jail.local file with config for SSHd
# NOTE: Feel free to adjust "maxretry"
# ------

# NOTE: Please adjust bantime below as desired.
# It's being set to 5 minutes in the event you inadvertently
# lock yourself out after rebooting the server.  
# I advise setting it much higher than that afterwards by
# editing the filename shown below with your favorite editor.
#

cat > /etc/fail2ban/jail.local<< EOF

# DEFAULT

[DEFAULT]

bantime  = 5m

maxretry = 2

#
# SSH servers
#

[sshd]

# To use more aggressive sshd modes set filter parameter "mode" in jail.local:
# normal (default), ddos, extra or aggressive (combines all).
# See "tests/files/logs/sshd" or "filter.d/sshd.conf" for usage example and details.
# Port is set to the variable set above
#
#mode   = normal
enabled = true
port    = $SSHD_PORT_NUM
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 2

EOF

# The following should be self-explanatory. :-)

# service fail2ban stop && sleep 5 && service fail2ban start

# Change to systemctl in place of service was submitted by "suorcd"

systemctl restart fail2ban

# Enable IPFS Service file created earlier to run at startup but not starting it now
# as it's not installed yet

# Setting color the light green
echo
echo -e "\033[1;92mEnabling IPFS daemon service..."

# Setting text color to bright white
echo -e '\033[0;97m'

systemctl enable ipfs

# Raises UDP buffer memory so IPFS daemon doesn't complain.  I looked

echo
echo -e "\033[1;92mRaising UDP buffer memory so IPFS daemon doesn't complain"
echo 

# Set textcolor to bright white
echo -e '\033[0;97m'

# Line below was submitted by "suorcd"

echo "net.core.rmem_max = 1200000" > /etc/sysctl.d/98-ipfs.conf

sysctl -w net.core.rmem_max=1200000

echo
echo -e "\033[1;92mAdjusting size of system journal to 10MB and 3 day retention.."
echo 

# This is will limit growth of the system journal to 10MB and 3 day retention.
# It was done default system settings had consumed almost 1GB after a few days
# and that's just not necessary for running an IPFS node and you can feel free
# to modify the settings as needed or desired.

# Set textcolor to bright white

echo -e '\033[0;97m'

sed -i 's/#SystemMaxUse=/SystemMaxUse=10M/gi' /etc/systemd/journald.conf
sed -i 's/#MaxRetentionSec=/MaxRetentionSec=3D/gi' /etc/systemd/journald.conf

# service systemd-journald restart

# Change to systemctl in place of service was submitted by "suorcd"
systemctl restart systemd-journald

# Some quick house keeping with apt package manager

apt -qq autoremove
apt -qq clean

cat > /home/ipfs/ipfsinit.sh<< EOF

#!/bin/bash

# cd ~ returns to IPFS user home folder in the event you were elsewhere

cd ~

# The following github link was found at the IPFS Podcasting site below.
# Part of the steps
# In the "Install Script" Section under the "Advanced" (Tux the Penguin Icon) + (IPFS logo)
# https://ipfspodcasting.com/RunNode

# Setting text color to bright white

echo -e '\033[0;97m'

wget https://raw.githubusercontent.com/Cameron-IPFSPodcasting/podcastnode-Python/main/ipfspodcasting-install.sh

# Makes the script executable

chmod +x ipfspodcasting-install.sh
echo
echo -e "\033[1;92mDownloaded IPFS script will now run and then return to continue next steps.."
echo -e "\033[1;92m----------"
echo -e "\033[1;92mDNOTE: You will be asked for password you entered to create the IPFS user."
echo -e "\033[1;92mI hope you remember it or wrote it down.  :-D"
echo

# Setting text color to bright white

echo -e "\033[0;97m"

sudo bash ipfspodcasting-install.sh

echo
echo -e "\033[1;92mAnd we're back from the ipfspodcasting-install script!"
echo
echo -e "\033[1;92mIf successful, the "PeerID" should be shown below."
echo
ipfs config show | grep "PeerID"

echo
echo Waiting 10 seconds so you can see if PeerID is present.  
echo
sleep 10

# Setting text color to yellow

echo -e "\033[0;33m"

echo "NOTE: If it didn't, simply re-run the script you saved. Tap the up"
echo "arrow (e.g. for those not familiar of doing that of course) until you"
echo "see the install script and press ENTER key.  Reboot your node after."
echo

# Switch color the light green

echo -e "\033[1;92m"

echo "Once system is up and running again, go into the IPFS Podcasting Management Page"
echo "at https://ipfspodcasting.com/Manage and you should see the PeerID you recorded"
echo "earler on there."
echo 
echo "Thank you for doing your part to expand the IPFS Podcasting Ecosystem!"
echo
echo "Please feel free to comment on this installation experience and share it"
echo "with others that are interested in running their own nodes but have had"
echo "issues settings things up properly and in a more secure manner"
echo "by not running the services as root."
echo
echo "A big thanks to @Cameron on Mastodon @podcastindex.social for all the work"
echo "involving IPFSPodcasting.net and everyone involved in the evolution of IPFS!"
echo
echo "If all went well, please proceed to reboot system by entering:"
echo
echo "sudo reboot (enter user password if requested)"
echo
 
# Setting text color to bright white

echo -e "\033[0;97m"

EOF

# Makes newly created file executable.  But you probably already knew that huh!?  B-)

chmod +x /home/ipfs/ipfsinit.sh

# Sets ownership of script to ipfs user 

chown ipfs:ipfs /home/ipfs/ipfsinit.sh

# Next step is to run the script so type in:
# ./ipfsinit.sh  (and press ENTER key)
#
# switches to new user at end of script

echo -e "\033[1;92m"
echo
echo Switching to IPFS user..
echo
echo "NOTE: To proceed, type in:"
echo
echo "./ipfsinit.sh  (then press ENTER key)"
echo

# Setting text color to bright white

echo -e "\033[0;97m"

# Addition of "-s /bin/bash" was submitted by "suorcd"
# su - ipfs

su - ipfs -s /bin/bash
