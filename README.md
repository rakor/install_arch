# About
A little script to install Arch-Linux on zfs with zfsbootmanager.

* prepare the partiotions needed for EFI-boot
* create an encrypted zpool and zfs-datasets
* install zfsbootmenu as bootmanager
* install Gnome as Desktop
* create an useraccount

This is a personal script for my own needs.

Some things to do....
* more comments
* include microcode-updates

# How to use
* Just boot an installation-media
* download this script using curl `curl -s https://raw.githubusercontent.com/rakor/install_arch/main/archinstall.sh -o archinstall.sh`
* open it in your favorite editor and configure the variables -
  otherwise it will not do what you expected!
* make it executable `chmod 777 archinstall.sh`
* run the script `./archinstall`
* follow the instructions of the script. The script is run three times.
* ... you have your running arch on zfs using zbm.

Many thanks to @Soulsuke. Many details were inspired by his
installation-instructions.
