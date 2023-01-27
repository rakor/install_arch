#!/bin/sh

USERNAME=rakor
HDD=/dev/vda
MYHOSTNAME=archlinux
ADDITIONALPACKETS="man-pages-de man-db syncthing ufw restic git fish unzip gnome gnome-extra"
ENABLESERVICES="NetworkManager ufw gdm"
SWAPGB=1
EFIGB=1

# Put in additional commands to run as root after the installation has
# finished inside the new environment
additionalCommands(){
    ufw enable
    ufw allow syncthing
    chsh -s /usr/bin/fish $USERNAME	
    
    curl https://github.com/rakor/resticbackupscript/archive/master.zip -o /root/backupscript.zip
    unzip backupscript.zip
    rm backupscript.zip
    sh resticbackupscript-master/install.sh
    sed -e "s[^\s*RESTIC=.*\$[RESTIC=/usr/bin/restic[" resticbackupscript-master/resticrc_debian > /root/.resticrc
    rm -rf resticbackupscript-master
    echo "#!/bin/sh\n/usr/local/bin/resticbackup cron" > /etc/cron.hourly/backup
    chmod 755 /etc/cron.hourly/backup

    ####
    # vimrc
    curl -s
    https://raw.githubusercontent.com/rakor/config/master/home/.vimrc -o /root/.vimrc
    chown root:root /root/.vimrc
    chmod 644 /root/.vimrc
    https://raw.githubusercontent.com/rakor/config/master/home/.vimrc -o /home/$USERNAME/.vimrc
    chown $USERNAME:$USERNAME /home/$USERNAME/.vimrc
    chmod 644 /home/$USERNAME/.vimrc
    mkdir -p /root/.vim/colors
    mkdir -p /home/$USERNAME/.vim/colors
    curl https://raw.githubusercontent.com/tomasr/molokai/master/colors/molokai.vim -o /home/$USERNAME/.vim/colors/molokai.vim
    cp /home/$USERNAME/.vim/colors/molokai.vim /root/.vim/colors/molokai.vim
    chown $USERNAME:$USERNAME -R /home/$USERNAME/.vim

    echo "RESTIC"
    echo "======"
    echo "Please don't forget to set repository and password for the restic-backups in /root/.resticrc."
    echo "Then you have to 'resticcmd init' the repository if it is a new one."	
    
    echo "Syncthing"
    echo "========="
    echo "If you want to start syncthing automatically at logon of your"
    echo "user run as user $USERNAME:"
    echo "  systemctl --user enable syncthing.service"
    echo "  systemctl --user start syncthing.service"
    echo "Syncthing will be listening on Port 8384 for the Webinterface"
    echo "If you also want to allow external access to the Syncthing web GUI, run:"
    echo "  ufw allow syncthing-gui"
    echo "Allowing external access is not necessary for a typical installation."
}

# Datei die den Installationsstatus haelt
STATUSFILE=~/archinstallservice.txt

if [ -e $STATUSFILE ]; then
  . $STATUSFILE
else
    STEP=1
fi

nextstep(){
    STEP=$(($STEP+1))
    echo "STEP=$STEP" > $STATUSFILE
}

step1(){
	#German keyboardlayout
    loadkeys de-latin1

	# Test network
    timedatectl status

	# Partitioning
	# Create a GPT-layout and inside an efs-partition, swap, and root-pool
    parted $HDD mklabel gpt
    parted $HDD mkpart efi-part fat32 1MiB ${EFIGB}GiB
    parted $HDD set 1 esp on
	# create a 2GB swap partition (Important: the last value is the
	# endpoint, not the size!
    parted $HDD mkpart swap linux-swap 1GiB $(($EFIGB+$SWAPGB))GiB
	# rest for the pool
    parted $HDD mkpart zpool 3GiB 100%

    mkswap /dev/disk/by-partlabel/swap

    mkfs.fat -F 32 /dev/disk/by-partlabel/efi-part

	# Install zfs into the install-environment
    curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash
    modprobe zfs

    echo "Creating the ZFS-pool. Give your encryption-key"
	# create the zpool
    zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O relatime=on \
    -O xattr=sa \
    -O normalization=formD \
    -O devices=off \
    -O mountpoint=none \
    -O canmount=off \
    -O compression=lz4 \
    -O dnodesize=auto \
    -O encryption=on \
    -O keyformat=passphrase \
    -O keylocation=prompt \
    -R /mnt \
    zroot /dev/disk/by-partlabel/zpool

	# create the datasets
    zfs create -o mountpoint=none zroot/data
    zfs create -o mountpoint=none zroot/ROOT
    zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
    zfs create -o mountpoint=/home zroot/data/home
    zfs create -o mountpoint=/root zroot/data/home/root
    zfs create -o mountpoint=/var -o canmount=off zroot/var
    zfs create zroot/var/log
    zfs create -o mountpoint=/var/lib -o canmount=off zroot/var/lib
    zfs create -o com.sun:auto-snapshot=false zroot/var/lib/libvirt
    zfs create -o com.sun:auto-snapshot=false zroot/var/lib/docker
    zfs create zroot/var/games
    zfs create -o com.sun:auto-snapshot=false  zroot/tmp
    zfs create zroot/data/home/$USERNAME
    zfs create -o com.sun:auto-snapshot=false zroot/data/home/${USERNAME}/Downloads
    zfs create -o com.sun:auto-snapshot=false zroot/data/home/$USERNAME/${USERNAME}-home

	# export the pool
    zpool export zroot
	# reimport the pool
    zpool import -d /dev/disk/by-partlabel -R /mnt zroot -N
	# load the encryption-key
    echo;echo
    echo "Type your ZFS-encryption-key to unlock the pool"
    zfs load-key zroot

	# mount the datasets
    zfs mount zroot/ROOT/default
    zfs mount -a

	# prepare the pool to boot
    zpool set bootfs=zroot/ROOT/default zroot
    zpool set cachefile=/etc/zfs/zpool.cache zroot
    mkdir -p /mnt/etc/zfs
    cp -p /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache


	# installation of arch-linux
    mkdir -p /mnt/boot/efi
    mount /dev/disk/by-partlabel/efi-part /mnt/boot/efi
    swapon /dev/disk/by-partlabel/swap
    pacstrap -K /mnt base linux linux-firmware vim networkmanager
    genfstab -U /mnt >> /mnt/etc/fstab

	# remove the zfs-datasets vom fstab
    sed -i -e 's|^\(\S*\s\+\S*\s\+zfs\)|#\1|' /mnt/etc/fstab
    
    nextstep
    cp $0 /mnt/root/
    cp $STATUSFILE /mnt/root
    chmod 777 /mnt/root/$0

    echo;echo
    echo "Type 'arch-chroot /mnt' to switch into the new installation"
    echo "Then change directory to /root and start the script another time"

    nextstep
    exit
}

step2(){
	# basesettings
    ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    hwclock --systohc

	# prepare locale.gen to get german an us and set language-settings
    sed -i -e 's%^#s*\(\(en_US\|de_DE\)\.UTF-8\)%\1%' /etc/locale.gen
    locale-gen
    echo LANG=de_DE.UTF-8 >> /etc/locale.conf
    echo KEYMAP=de-latin1 >> /etc/vconsole.conf
    echo $MYHOSTNAME >> /etc/hostname

	# prepare mkinitcpio
    sed -i -e 's|^\s*\(HOOKS=.*\)\(filesystems.*\)|\1 zfs \2|' /etc/mkinitcpio.conf
    sed -i -e 's|^\s*\(HOOKS=.*\)fsck\(.*\)|\1 \2|' /etc/mkinitcpio.conf

	# install zfs into the new installation
    echo [archzfs] >> /etc/pacman.conf
    echo 'Server = http://archzfs.com/$repo/x86_64' >> /etc/pacman.conf
    echo 'Server = http://mirror.sum7.eu/archlinux/archzfs/$repo/x86_64' >> /etc/pacman.conf
    echo 'Server = http://mirror.biocrafting.net/archlinux/archzfs/$repo/x86_64' >> /etc/pacman.conf
    pacman-key --recv-keys DDF7DB817396A49B2A2723F7403BD972F75D9D76
    pacman-key --finger DDF7DB817396A49B2A2723F7403BD972F75D9D76
    pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76
    pacman -S --noconfirm zfs-dkms linux-headers

	#create the initrd
	#    mkinitcpio -P


	# install bootmanager zbm
    pacman -S --noconfirm efibootmgr
    mkdir -p /boot/efi/EFI/zbm
    curl -L https://get.zfsbootmenu.org/efi/release -o /boot/efi/EFI/zbm/zfsbootmenu.EFI
    efibootmgr -c -d $HDD -p 1 -L "ZFSBootMenu" -l '\EFI\zbm\zfsbootmenu.EFI' -u "zbm.prefer=zroot rd.vconsole.keymap=de-latin1 quiet"
    zfs set org.zfsbootmenu:commandline="rw" zroot/ROOT

    zpool set cachefile=/etc/zfs/zpool.cache zroot

	# start and mount zfs
    systemctl enable zfs.target
    systemctl enable zfs-import-cache.service
    systemctl enable zfs-mount.service
    systemctl enable zfs-import.target
    zgenhostid $(hostid)
    mkinitcpio -P

	# Set password for root
    echo;echo
    echo "Please set password for 'root'"
    passwd
    mv /root/.bashrc /root/.bashrc_old
    curl -s  https://raw.githubusercontent.com/rakor/config/master/root/.bashrc -o /root/.bashrc

	# last steps to prepare the installation

	# Create user and its datasets
    echo;echo
    echo "Creating user $USERNAME"
    useradd -m -G wheel $USERNAME
    echo "Please give the password to set for user $USERNAME"
    passwd $USERNAME

	# set permissions
    cp -r /etc/skel/.[^.]* /home/$USERNAME
    cp -r /etc/skel/* /home/$USERNAME
    chown -R $USERNAME:$USERNAME /home/$USERNAME
    chmod 700 /root
    chmod 1777 /tmp
    chmod 700 /home/$USERNAME


	#install additional packages
    pacman -S --noconfirm $ADDITIONALPACKETS

	#enable services
    for i in $ENABLESERVICES; do 
        systemctl enable $i.service

    done
    
	#run additional commands that were defined at the top
    echo "Running additional commands"
    additionalCommands

    rm /root/$STATUSFILE

    echo;echo
    echo "You can now leave the chroot. Please do the following:"
    echo "umount /boot/efi"
    echo "exit"
    echo "zfs umount -a"
    echo "zpool export zroot"
    echo "reboot"

    nextstep
	# We should somehow install the microcode-updates...
        exit
}


if [ $STEP = 1 ]; then
    step1
elif [ $STEP = 2 ]; then
    step2
fi

