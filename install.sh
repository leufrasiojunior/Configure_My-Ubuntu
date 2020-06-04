#!/bin/bash
clear
##Variaveis##
PKG_MANAGER="apt-get"
PKG_CACHE="/var/lib/apt/lists/"

spinner(){
	local pid=$1
	local delay=0.50
	local spinstr='/-\|'
	while ps a | awk '{print $1}' | grep -q "$pid"; do
		local temp=${spinstr#?}
		printf " [%c]  " "${spinstr}"
		local spinstr=${temp}${spinstr%"$temp"}
		sleep ${delay}
		printf "\\b\\b\\b\\b\\b\\b"
	done
	printf "    \\b\\b\\b\\b"
	
#&> /dev/null & spinner $!
}

main() {

    ######## FIRST CHECK ########
    # Must be root to install
	echo ":::"
	if [[ $EUID -eq 0 ]];then
		echo "::: You are root."
	else
		echo "::: Please, run this script as root/sudo"
		exit 1
	fi
	
#Verify Updates
updatePackageCache

#Notify Update, if exist.
notifyPackageUpdatesAvailable

#Verify user do install PRIVATE KEY to SSH access
chooseUser

#Install private key in user
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAkTFwAUfHR6Rqkal6vs2yJLNRqiIcyeGQGdk669ktMy1XRd9OsGLRKli2J0/lKEGJXwTmYGgy0p+7bEYUJ3XpVIecbcsVOGm+RRC9r1vy2g8m0TfbcNIt18HxKKxYfD51A60X6xWoAVde1MzW3LWqKyNyXkcz4MVzAnUu8SKpD8mQSOluQBcS05mhadN+UQCJxuQE+iywxIIxIriQPNRk5DLQysHkkVKyq4WlJ8Tt/hQqDvuuPZvgnn9rWB7OOjHIkplDhhtNTT9AwFDRx3fzj0UTZP9B17zaV6R3eDT04jxzjN+0jNFe9n4sQ+9yoIAgwONan+kstrrwePfEjmKIbQ== rsa-key-20200203' >> "${install_home}/.ssh/authorized_keys"

#Install qbittorrent-nox
qbittorrent

#Generate SSL auto-assingned certificate to enable HTTPS in qbittorrent.
sslqbt
sleep 1
mv server.crt server.key /home/qbtuser/.config/qBittorrent/ssl

#copy .conf file and backup original.
systemctl stop qbittorrent-nox
mv /home/qbtuser/.config/qBittorrent/qBittorrent.conf /home/qbtuser/.config/qBittorrent/qBittorrent.conf.ori
curl -sSL https://raw.githubusercontent.com/leufrasiojunior/Configure_My-Ubuntu/master/qBittorrent.conf > /home/qbtuser/.config/qBittorrent/qBittorrent.conf
chmod o=rx /home/qbtuser/.config/qBittorrent/ssl/server.crt
chmod o=rx /home/qbtuser/.config/qBittorrent/ssl/server.key
systemctl start qbittorrent-nox

#Download smb.conf
mv /etc/samba/smb.conf /etc/samba/smb.conf.ori
curl -sSL https://raw.githubusercontent.com/leufrasiojunior/Configure_My-Ubuntu/master/smb.conf > /etc/samba/smb.conf
}

updatePackageCache(){
	#Running apt-get update/upgrade with minimal output can cause some issues with
	#requiring user input

	#Check to see if apt-get update has already been run today
	#it needs to have been run at least once on new installs!
	timestamp=$(stat -c %Y ${PKG_CACHE})
	timestampAsDate=$(date -d @"${timestamp}" "+%b %e")
	today=$(date "+%b %e")


	 if [ ! "${today}" == "${timestampAsDate}" ]; then
		#update package lists
		echo ":::"
		echo -ne "::: ${PKG_MANAGER} update has not been run today. Running now...\\n" 
        # shellcheck disable=SC2086
		$SUDO ${UPDATE_PKG_CACHE} &> /var/log/install.log & spinner $!
		echo " done!"
	fi
}

notifyPackageUpdatesAvailable(){
	# Let user know if they have outdated packages on their system and
	# advise them to run a package update at soonest possible.
	echo ":::"
	echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
	updatesToInstall=$(eval "${PKG_COUNT}")
	echo " done!"
	echo ":::"
	if [[ ${updatesToInstall} -eq "0" ]]; then
		echo "::: Your system is up to date! Continuing with installation..."
	else
		echo "::: There are ${updatesToInstall} updates available for your system!"
		echo "::: We recommend you update your OS after installing. "
		echo "::: Execute 'sudo apt upgrade', and run this script again. Exiting..."
		echo ":::"
		exit 1
	fi
}

chooseUser(){
if [ -z "$install_user" ]; then
	if [ "$(awk -F':' 'BEGIN {count=0} $3>=1000 && $3<=60000 { count++ } END{ print count }' /etc/passwd)" -eq 1 ]; then
		install_user="$(awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd)"
		echo ":::  No user specified, but only ${install_user} is available, using it"
	else
		echo "::: No user specified"
		exit 1
	fi
else
	if awk -F':' '$3>=1000 && $3<=60000 {print $1}' /etc/passwd | grep -qw "${install_user}"; then
	#else
		echo "::: User ${install_user} does not exist, creating..."
		$SUDO useradd -m -s /bin/bash "${install_user}"
		echo "::: User created without a password, please do sudo passwd $install_user to create one"
	fi
fi
install_home=$(grep -m1 "^${install_user}:" /etc/passwd | cut -d: -f6)
install_home=${install_home%/}

sudo -u ${install_user} mkdir "${install_home}/.ssh"
}

qbittorrent(){
adduser --system --group qbtuser &> /var/log/install.log & spinner $!
adduser ${install_user} qbtuser &> /var/log/install.log & spinner $!

add-apt-repository -y ppa:qbittorrent-team/qbittorrent-stable &> /var/log/install.log & spinner $!
apt install -y qbittorrent-nox &> /var/log/install.log & spinner $!

echo -e '[Unit]\nDescription=qBittorrent Command Line Client\nAfter=network.target\n \n[Service]\n#Do not change to "simple"\nType=forking\nUser=qbtuser\nGroup=qbtuser\nUMask=007\nExecStart=/usr/bin/qbittorrent-nox -d\nRestart=on-failure\n \n[Install]\nWantedBy=multi-user.target' > /etc/systemd/system/qbittorrent-nox.service

#Reload systemctl daemons
systemctl daemon-reload &> /var/log/install.log & spinner $!

#Start on system
systemctl enable qbittorrent-nox &> /var/log/install.log & spinner $!

#start service
systemctl start qbittorrent-nox &> /var/log/install.log & spinner $!

#show status
systemctl status qbittorrent-nox &> /var/log/install.log & spinner $!
}

sslqbt(){
mkdir /home/qbtuser/.config/qBittorrent/ssl
openssl req -new -x509 -nodes -out server.crt -keyout server.key
}

main
