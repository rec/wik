Last login: Mon Dec  9 21:25:28 on ttys005
tom@bantam:~$
tom@bantam:~$ Black       0;30     Dark Gray     1;30
-bash: Black: command not found
-bash: 30: command not found
-bash: 30: command not found
tom@bantam:~$ Blue        0;34     Light Blue    1;34
-bash: Blue: command not found
-bash: 34: command not found
-bash: 34: command not found
tom@bantam:~$ Green       0;32     Light Green   1;32
-bash: Green: command not found
-bash: 32: command not found
-bash: 32: command not found
tom@bantam:~$ Cyan        0;36     Light Cyan    1;36
-bash: Cyan: command not found
-bash: 36: command not found
-bash: 36: command not found
tom@bantam:~$ Red         0;31     Light Red     1;31
-bash: Red: command not found
-bash: 31: command not found
-bash: 31: command not found
tom@bantam:~$ Purple      0;35     Light Purple  1;35
-bash: Purple: command not found
-bash: 35: command not found
-bash: 35: command not found
tom@bantam:~$ Brown       0;33     Yellow        1;33
-bash: Brown: command not found
-bash: 33: command not found
-bash: 33: command not found
tom@bantam:~$
tom@bantam:~$  export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
tom@bantam:~$ cd /code/gitz
tom@bantam:/code/gitz$ ping xr.ax.to
PING xr.ax.to (64.225.75.136): 56 data bytes
64 bytes from 64.225.75.136: icmp_seq=0 ttl=56 time=18.536 ms
64 bytes from 64.225.75.136: icmp_seq=1 ttl=56 time=19.131 ms
64 bytes from 64.225.75.136: icmp_seq=2 ttl=56 time=15.471 ms
^C
--- xr.ax.to ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 15.471/17.713/19.131/1.604 ms
tom@bantam:/code/gitz$ ^C
tom@bantam:/code/gitz$ ping 1.1.1.1
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: icmp_seq=0 ttl=56 time=13.074 ms
64 bytes from 1.1.1.1: icmp_seq=1 ttl=56 time=13.399 ms
^C
--- 1.1.1.1 ping statistics ---
2 packets transmitted, 2 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 13.074/13.236/13.399/0.163 ms
tom@bantam:/code/gitz$ sudo $SHELL
Password:
root@bantam:/code/gitz$ diskutil list
/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.3 GB   disk0
   1:                        EFI EFI                     209.7 MB   disk0s1
   2:          Apple_CoreStorage bantam                  499.4 GB   disk0s2
   3:                 Apple_Boot Recovery HD             650.0 MB   disk0s3

/dev/disk1 (internal, virtual):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                  Apple_HFS bantam                 +499.0 GB   disk1
                                 Logical Volume on disk0s2
                                 DAB04387-14A1-4090-A061-1E7F7E40205F
                                 Unencrypted

/dev/disk2 (disk image):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     Apple_partition_scheme                        +16.5 MB    disk2
   1:        Apple_partition_map                         32.3 KB    disk2s1
   2:                  Apple_HFS Flash Player            16.4 MB    disk2s2

/dev/disk5 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *4.0 TB     disk5
   1:                        EFI EFI                     209.7 MB   disk5s1
   2:                  Apple_HFS Handel                  4.0 TB     disk5s2

root@bantam:/code/gitz$
  [Restored 14 Dec 2019, 20:13:36]
Last login: Sat Dec 14 20:13:36 on ttys005
Restored session: Sat 14 Dec 2019 20:12:20 CET
tom@bantam:/code/gitz$
  [Restored 16 Dec 2019, 21:44:33]
Last login: Mon Dec 16 21:44:32 on ttys005
tom@bantam:/code/gitz$
  [Restored 16 Dec 2019, 21:48:38]
Last login: Mon Dec 16 21:48:38 on ttys005
Restored session: Mon 16 Dec 2019 21:47:42 CET
tom@bantam:/code/gitz$ sudo $SHELL
Password:
root@bantam:/code/gitz$ diskutil list
/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.3 GB   disk0
   1:                        EFI EFI                     209.7 MB   disk0s1
   2:          Apple_CoreStorage bantam                  499.4 GB   disk0s2
   3:                 Apple_Boot Recovery HD             650.0 MB   disk0s3

/dev/disk1 (internal, virtual):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                  Apple_HFS bantam                 +499.0 GB   disk1
                                 Logical Volume on disk0s2
                                 DAB04387-14A1-4090-A061-1E7F7E40205F
                                 Unencrypted

/dev/disk2 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *4.0 TB     disk2
   1:                        EFI EFI                     209.7 MB   disk2s1
   2:                  Apple_HFS Handel                  4.0 TB     disk2s2

/dev/disk3 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *31.2 GB    disk3
   1:               Windows_NTFS Big Movies              31.2 GB    disk3s1

root@bantam:/code/gitz$ diskutil mount /dev/disk2
diskutil: interrupted
root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ diskutil list
/dev/disk0 (internal, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.3 GB   disk0
   1:                        EFI EFI                     209.7 MB   disk0s1
   2:          Apple_CoreStorage bantam                  499.4 GB   disk0s2
   3:                 Apple_Boot Recovery HD             650.0 MB   disk0s3

/dev/disk1 (internal, virtual):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:                  Apple_HFS bantam                 +499.0 GB   disk1
                                 Logical Volume on disk0s2
                                 DAB04387-14A1-4090-A061-1E7F7E40205F
                                 Unencrypted

/dev/disk2 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *4.0 TB     disk2
   1:                        EFI EFI                     209.7 MB   disk2s1
   2:                  Apple_HFS Handel                  4.0 TB     disk2s2

/dev/disk3 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *62.5 GB    disk3
   1:               Windows_NTFS Videaux                 62.5 GB    disk3s1

root@bantam:/code/gitz$ diskutil mount /dev/disk2
Volume on disk2 timed out waiting to mount
root@bantam:/code/gitz$ history | grep ssh
11321  ssh -l root ax.to
11322  ssh -l tom ax.to
11323  ssh -l root ax.to
13986  ssh -l root ax.to
13990  history | grep ssh
13991  ssh -l tom 192.168.178.143
14598  history | grep ssh
14599  ssh -l tom 192.168.178.143
14644  history | grep ssh
14646  ssh -l tom 192.168.178.143
14647  ssh -l root 192.168.178.143
19158  ssh -l root ax.to
19425  ssh-keygen -t rsa -b 4096 -C savoryred@protonmail.com
19426  rm /Users/tom/.ssh/id_rsa.2*
19427  ssh-keygen -t rsa -b 4096 -C savoryred@protonmail.com
19428  cd .ssh
19432  ssh-keygen -t rsa -b 4096 -C savoryred@protonmail.com
19563  ssh -l root 64.225.75.136
19575  ssh ax.to -l root
19640  ssh -l root ax.to
19972  history | grep ssh
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
The authenticity of host '64.225.75.136 (64.225.75.136)' can't be established.
ECDSA key fingerprint is SHA256:LwChpXMolRK9nj6tkJggapfp9T1t9CHMA2uyscFw5eA.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added '64.225.75.136' (ECDSA) to the list of known hosts.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied (publickey,password).
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied (publickey,password).
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied (publickey,password).
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-58-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Tue Dec 17 16:06:14 UTC 2019

  System load:  0.0                Processes:              105
  Usage of /:   15.2% of 24.06GB   Users logged in:        0
  Memory usage: 47%                IP address for eth0:    64.225.75.136
  Swap usage:   0%                 IP address for docker0: 172.17.0.1

 * Canonical Livepatch is available for installation.
   - Reduce system reboots and improve kernel security. Activate at:
     https://ubuntu.com/livepatch

8 packages can be updated.
0 updates are security updates.


*** System restart required ***
********************************************************************************

Welcome to DigitalOcean's One-Click Docker Droplet.
To keep this Droplet secure, the UFW firewall is enabled.
All ports are BLOCKED except 22 (SSH), 2375 (Docker) and 2376 (Docker).

* The Docker One-Click Quickstart guide is available at:
  https://do.co/docker1804#start

* You can SSH to this Droplet in a terminal as root: ssh root@64.225.75.136

* Docker is installed and configured per Docker's recommendations:
  https://docs.docker.com/install/linux/docker-ce/ubuntu/

* Docker Compose is installed and configured per Docker's recommendations:
  https://docs.docker.com/compose/install/#install-compose

For help and more information, visit http://do.co/docker1804

********************************************************************************

To delete this message of the day: rm -rf /etc/update-motd.d/99-one-click
Last login: Mon Dec  9 12:13:54 2019 from 213.127.99.113
root@docker-wiki-experiment:~# apt update && apt upgrade -y
Hit:1 http://archive.ubuntu.com/ubuntu bionic InRelease
Hit:2 http://ppa.launchpad.net/certbot/certbot/ubuntu bionic InRelease
Get:3 http://mirrors.digitalocean.com/ubuntu bionic InRelease [242 kB]
Get:4 http://mirrors.digitalocean.com/ubuntu bionic-updates InRelease [88.7 kB]
Get:5 http://security.ubuntu.com/ubuntu bionic-security InRelease [88.7 kB]
Get:6 http://mirrors.digitalocean.com/ubuntu bionic-backports InRelease [74.6 kB]
Hit:7 https://download.docker.com/linux/ubuntu bionic InRelease
Get:8 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 Packages [817 kB]
Get:9 http://mirrors.digitalocean.com/ubuntu bionic-updates/universe amd64 Packages [1033 kB]
Fetched 2343 kB in 1s (1729 kB/s)
Reading package lists... Done
Building dependency tree
Reading state information... Done
9 packages can be upgraded. Run 'apt list --upgradable' to see them.
Reading package lists... Done
Building dependency tree
Reading state information... Done
Calculating upgrade... Done
The following packages will be upgraded:
  cloud-init dmeventd dmsetup libdevmapper-event1.02.1
  libdevmapper1.02.1 liblvm2app2.2 liblvm2cmd2.02 linux-firmware lvm2
9 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.
Need to get 77.7 MB of archives.
After this operation, 8446 kB of additional disk space will be used.
Get:1 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 libdevmapper1.02.1 amd64 2:1.02.145-4.1ubuntu3.18.04.2 [127 kB]
Get:2 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 dmsetup amd64 2:1.02.145-4.1ubuntu3.18.04.2 [74.5 kB]
Get:3 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 libdevmapper-event1.02.1 amd64 2:1.02.145-4.1ubuntu3.18.04.2 [10.9 kB]
Get:4 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 liblvm2cmd2.02 amd64 2.02.176-4.1ubuntu3.18.04.2 [586 kB]
Get:5 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 dmeventd amd64 2:1.02.145-4.1ubuntu3.18.04.2 [30.4 kB]
Get:6 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 liblvm2app2.2 amd64 2.02.176-4.1ubuntu3.18.04.2 [432 kB]
Get:7 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 linux-firmware all 1.173.13 [75.1 MB]
Get:8 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 lvm2 amd64 2.02.176-4.1ubuntu3.18.04.2 [930 kB]
Get:9 http://mirrors.digitalocean.com/ubuntu bionic-updates/main amd64 cloud-init all 19.3-41-gc4735dd3-0ubuntu1~18.04.1 [411 kB]
Fetched 77.7 MB in 1s (52.2 MB/s)
Preconfiguring packages ...
(Reading database ... 126211 files and directories currently installed.)
Preparing to unpack .../0-libdevmapper1.02.1_2%3a1.02.145-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking libdevmapper1.02.1:amd64 (2:1.02.145-4.1ubuntu3.18.04.2) over (2:1.02.145-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../1-dmsetup_2%3a1.02.145-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking dmsetup (2:1.02.145-4.1ubuntu3.18.04.2) over (2:1.02.145-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../2-libdevmapper-event1.02.1_2%3a1.02.145-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking libdevmapper-event1.02.1:amd64 (2:1.02.145-4.1ubuntu3.18.04.2) over (2:1.02.145-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../3-liblvm2cmd2.02_2.02.176-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking liblvm2cmd2.02:amd64 (2.02.176-4.1ubuntu3.18.04.2) over (2.02.176-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../4-dmeventd_2%3a1.02.145-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking dmeventd (2:1.02.145-4.1ubuntu3.18.04.2) over (2:1.02.145-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../5-liblvm2app2.2_2.02.176-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking liblvm2app2.2:amd64 (2.02.176-4.1ubuntu3.18.04.2) over (2.02.176-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../6-linux-firmware_1.173.13_all.deb ...
Unpacking linux-firmware (1.173.13) over (1.173.12) ...
Preparing to unpack .../7-lvm2_2.02.176-4.1ubuntu3.18.04.2_amd64.deb ...
Unpacking lvm2 (2.02.176-4.1ubuntu3.18.04.2) over (2.02.176-4.1ubuntu3.18.04.1) ...
Preparing to unpack .../8-cloud-init_19.3-41-gc4735dd3-0ubuntu1~18.04.1_all.deb ...
Unpacking cloud-init (19.3-41-gc4735dd3-0ubuntu1~18.04.1) over (19.2-36-g059d049c-0ubuntu2~18.04.1) ...
Setting up libdevmapper1.02.1:amd64 (2:1.02.145-4.1ubuntu3.18.04.2) ...
Setting up libdevmapper-event1.02.1:amd64 (2:1.02.145-4.1ubuntu3.18.04.2) ...
Setting up dmsetup (2:1.02.145-4.1ubuntu3.18.04.2) ...
update-initramfs: deferring update (trigger activated)
Setting up liblvm2app2.2:amd64 (2.02.176-4.1ubuntu3.18.04.2) ...
Setting up linux-firmware (1.173.13) ...
update-initramfs: Generating /boot/initrd.img-4.15.0-72-generic
update-initramfs: Generating /boot/initrd.img-4.15.0-58-generic
Setting up cloud-init (19.3-41-gc4735dd3-0ubuntu1~18.04.1) ...
Setting up liblvm2cmd2.02:amd64 (2.02.176-4.1ubuntu3.18.04.2) ...
Setting up dmeventd (2:1.02.145-4.1ubuntu3.18.04.2) ...
dm-event.service is a disabled or a static unit not running, not starting it.
Setting up lvm2 (2.02.176-4.1ubuntu3.18.04.2) ...
update-initramfs: deferring update (trigger activated)
Processing triggers for libc-bin (2.27-3ubuntu1) ...
Processing triggers for systemd (237-3ubuntu10.33) ...
Processing triggers for man-db (2.8.3-2ubuntu0.1) ...
Processing triggers for rsyslog (8.32.0-1ubuntu4) ...
Processing triggers for ureadahead (0.100.0-21) ...
Processing triggers for initramfs-tools (0.130ubuntu3.9) ...
update-initramfs: Generating /boot/initrd.img-4.15.0-72-generic
root@docker-wiki-experiment:~# emacs /etc/bind


root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied (publickey,password).
root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ^?
bash: $'\177': command not found
root@bantam:/code/gitz$
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh -l root 64.225.75.136
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh root@64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh root@64.225.75.136
root@64.225.75.136's password:
Permission denied, please try again.
root@64.225.75.136's password:

root@bantam:/code/gitz$ ^C
root@bantam:/code/gitz$ ssh -l root ax.to
The authenticity of host 'ax.to (162.209.6.164)' can't be established.
ECDSA key fingerprint is SHA256:T6VzGEzeZ7LiVZ2Iaz2cqBmHTbGKVKwdqB1O/r3iL7M.
Are you sure you want to continue connecting (yes/no)? yes
Warning: Permanently added 'ax.to,162.209.6.164' (ECDSA) to the list of known hosts.
root@ax.to's password:
Permission denied, please try again.
root@ax.to's password:
Permission denied, please try again.
root@ax.to's password:

root@bantam:/code/gitz$ ssh -l root ax.to
root@ax.to's password:
Permission denied, please try again.
root@ax.to's password:
Permission denied, please try again.
root@ax.to's password:
Permission denied (publickey,password).
root@bantam:/code/gitz$
  [Restored 18 Dec 2019, 18:40:40]
Last login: Wed Dec 18 18:40:37 on ttys005
Restored session: Wed 18 Dec 2019 18:39:59 CET
tom@bantam:/code/gitz$ ssh -l root ax.to
root@ax.to's password:
Welcome to Ubuntu 14.04.6 LTS (GNU/Linux 3.13.0-170-generic x86_64)

 * Documentation:  https://help.ubuntu.com/

  System information as of Wed Dec 18 00:23:02 EST 2019

  System load:  0.13                Processes:           198
  Usage of /:   84.1% of 157.36GB   Users logged in:     0
  Memory usage: 49%                 IP address for eth0: 162.209.6.164
  Swap usage:   0%                  IP address for eth1: 10.178.18.9

  Graph this data and manage this system at:
    https://landscape.canonical.com/

UA Infrastructure Extended Security Maintenance (ESM) is not enabled.

0 updates can be installed immediately.
0 of these updates are security updates.

Enable UA Infrastructure ESM to receive 118 additional security updates.
See https://ubuntu.com/advantage or run: sudo ua status

New release '16.04.6 LTS' available.
Run 'do-release-upgrade' to upgrade to it.

Hello, visitor to my server!

This is a small non-profit server for artists, musicians, actors and weirdos.  I
charge nothing for this service, and over a hundred people rely on it for their
day-to-day lives.

Since you're logging in as root, there's a pretty good chance you are an
"intruder".  On the last box we had, this happened twice and they caused a lot
of damage.  Both times it was a disaster for me - I spend dozens of hours fixing
everything up and all sorts of people lost work.

Please - don't do this!  Feel free to look all you like - there are no secrets
here! - but please, don't break anything.  We aren't "them" - you'd be affecting
a lot of people just trying to do their art and have some fun.


Thanks in advance - and happy hacking!

Tom Swirly (tom@swirly.com)
No mail.
Last login: Tue Dec 17 12:13:30 2019 from ip-213-127-99-113.ip.prioritytelecom.net
root@safe:~# logout
Connection to ax.to closed.
tom@bantam:/code/gitz$ ssh root@64.225.75.136
Welcome to Ubuntu 18.04.3 LTS (GNU/Linux 4.15.0-72-generic x86_64)

 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/advantage

  System information as of Wed Dec 18 17:45:40 UTC 2019

  System load:  0.0                Processes:              95
  Usage of /:   15.3% of 24.06GB   Users logged in:        0
  Memory usage: 37%                IP address for eth0:    64.225.75.136
  Swap usage:   0%                 IP address for docker0: 172.17.0.1

 * Canonical Livepatch is available for installation.
   - Reduce system reboots and improve kernel security. Activate at:
     https://ubuntu.com/livepatch

0 packages can be updated.
0 updates are security updates.


********************************************************************************

Welcome to DigitalOcean's One-Click Docker Droplet.
To keep this Droplet secure, the UFW firewall is enabled.
All ports are BLOCKED except 22 (SSH), 2375 (Docker) and 2376 (Docker).

* The Docker One-Click Quickstart guide is available at:
  https://do.co/docker1804#start

* You can SSH to this Droplet in a terminal as root: ssh root@64.225.75.136

* Docker is installed and configured per Docker's recommendations:
  https://docs.docker.com/install/linux/docker-ce/ubuntu/

* Docker Compose is installed and configured per Docker's recommendations:
  https://docs.docker.com/compose/install/#install-compose

For help and more information, visit http://do.co/docker1804

********************************************************************************

To delete this message of the day: rm -rf /etc/update-motd.d/99-one-click
Last login: Wed Dec 18 17:31:48 2019 from 80.101.85.32
root@docker-wiki-experiment:~#
root@docker-wiki-experiment:~#
root@docker-wiki-experiment:~# emacs
root@docker-wiki-experiment:~# certbot apache
usage:
  certbot [SUBCOMMAND] [options] [-d DOMAIN] [-d DOMAIN] ...

Certbot can obtain and install HTTPS/TLS/SSL certificates.  By default,
it will attempt to use a webserver both for obtaining and installing the
certificate.
certbot: error: unrecognized arguments: apache
root@docker-wiki-experiment:~# certbot --apache
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Plugins selected: Authenticator apache, Installer apache

Which names would you like to activate HTTPS for?
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: xr.ax.to
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate numbers separated by commas and/or spaces, or leave input
blank to select all options shown (Enter 'c' to cancel): c
Please specify --domains, or --installer that will help in domain names autodiscovery, or --cert-name for an existing certificate name.
root@docker-wiki-experiment:~# certbot -h

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  certbot [SUBCOMMAND] [options] [-d DOMAIN] [-d DOMAIN] ...

Certbot can obtain and install HTTPS/TLS/SSL certificates.  By default,
it will attempt to use a webserver both for obtaining and installing the
certificate. The most common SUBCOMMANDS and flags are:

obtain, install, and renew certificates:
    (default) run   Obtain & install a certificate in your current webserver
    certonly        Obtain or renew a certificate, but do not install it
    renew           Renew all previously obtained certificates that are near
expiry
    enhance         Add security enhancements to your existing configuration
   -d DOMAINS       Comma-separated list of domains to obtain a certificate for

  --apache          Use the Apache plugin for authentication & installation
  --standalone      Run a standalone webserver for authentication
  (the certbot nginx plugin is not installed)
  --webroot         Place files in a server's webroot folder for authentication
  --manual          Obtain certificates interactively, or using shell script
hooks

   -n               Run non-interactively
  --test-cert       Obtain a test certificate from a staging server
  --dry-run         Test "renew" or "certonly" without saving any certificates
to disk

manage certificates:
    certificates    Display information about certificates you have from Certbot
    revoke          Revoke a certificate (supply --cert-path or --cert-name)
    delete          Delete a certificate

manage your account with Let's Encrypt:
    register        Create a Let's Encrypt ACME account
    update_account  Update a Let's Encrypt ACME account
  --agree-tos       Agree to the ACME server's Subscriber Agreement
   -m EMAIL         Email address for important account notifications

More detailed help:

  -h, --help [TOPIC]    print this message, or detailed help on a topic;
                        the available TOPICS are:

   all, automation, commands, paths, security, testing, or any of the
   subcommands or plugins (certonly, renew, install, register, nginx,
   apache, standalone, webroot, etc.)
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
root@docker-wiki-experiment:~# history
    1  source composer-install.sh
    2  ls
    3  chmod +x composer-install.sh
    4  ./composer-install.sh
    5  ls
    6  ./composer-install.sh
    7  cd BookStack/
    8  composer install
    9  apt install composer
   10  composer install
   11  uname -a
   12  lsb_release -a
   13  cd ..
   14  wget https://raw.githubusercontent.com/BookStackApp/devops/master/scripts/installation-ubuntu-18.04.sh
   15  chmod a+x installation-ubuntu-18.04.sh
   16  ./installation-ubuntu-18.04.sh
   17  systemctl reload apache2
   18  systemctl start apache2
   19  apt-get install curl
   20  curl -O http://64.225.75.136/index.php
   21  iptables-save
   22  uname -a
   23  man iptables-save
   24  ufw allow 80
   25  ufw allow https
   26  netstat -ln | grep 443
   27  history
   28  uname -a
   29  apt-get install emacs
   30  apt-get update
   31  apt-get upgrade
   32  apt-get install emacs
   33  emacs
   34  php --version
   35  apt install php
   36  apt install -y mysql git
   37  apt install -y git
   38  apt install -y mysql-server
   39  history
   40  emacs
   41  history
   42  apt update
   43  apt upgrade
   44  apt --list upgradable
   45  apt list --upgradable
   46  apt install letsencrypt
   47  apsudo apt-get update
   48  sudo apt-get install software-properties-common
   49  sudo add-apt-repository universe
   50  sudo add-apt-repository ppa:certbot/certbot
   51  sudo apt-get update
   52  sudo apt-get install software-properties-common
   53  sudo add-apt-repository universe
   54  sudo add-apt-repository ppa:certbot/certbot
   55  apt install software-properties-common
   56  add-apt-repository universe
   57  add-apt-repository ppa:certbot/certbot
   58  apt update
   59  apt upgrade
   60  apt install -y certbot python-certbot-apache
   61  apt update && apt upgrade -y
   62  apt autoremove
   63  https://certbot.eff.org/lets-encrypt/ubuntubionic-apache
   64  certbot --apache
   65  ping xr.ax.to
   66  nslookup ax.to
   67  nslookup xr.ax.to
   68  nslookup --help
   69  man nslookup
   70  nslookup xr.ax.to - editeverything.com
   71  whois editeverything.com
   72  apt install whois
   73  whois editeverything.com
   74  ping editeverything.com
   75  nslookup xr.ax.to - ns1.editeverything.com
   76  whois ax.to
   77  nslookup xr.ax.to
   78  ping xr.ax.to
   79  certbot --apache
   80  nslookup xr.ax.to
   81  ufw
   82  ufw --help
   83  last reboot
   84  apt update && apt upgrade -y
   85  emacs /etc/bind
   86  vi .ssh/authorized_keys
   87  emacs
   88  certbot apache
   89  certbot --apache
   90  certbot -h
   91  history
root@docker-wiki-experiment:~# history | grep certbot
   50  sudo add-apt-repository ppa:certbot/certbot
   54  sudo add-apt-repository ppa:certbot/certbot
   57  add-apt-repository ppa:certbot/certbot
   60  apt install -y certbot python-certbot-apache
   63  https://certbot.eff.org/lets-encrypt/ubuntubionic-apache
   64  certbot --apache
   79  certbot --apache
   88  certbot apache
   89  certbot --apache
   90  certbot -h
   92  history | grep certbot
root@docker-wiki-experiment:~# certbot -h

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  certbot [SUBCOMMAND] [options] [-d DOMAIN] [-d DOMAIN] ...

Certbot can obtain and install HTTPS/TLS/SSL certificates.  By default,
it will attempt to use a webserver both for obtaining and installing the
certificate. The most common SUBCOMMANDS and flags are:

obtain, install, and renew certificates:
    (default) run   Obtain & install a certificate in your current webserver
    certonly        Obtain or renew a certificate, but do not install it
    renew           Renew all previously obtained certificates that are near
expiry
    enhance         Add security enhancements to your existing configuration
   -d DOMAINS       Comma-separated list of domains to obtain a certificate for

  --apache          Use the Apache plugin for authentication & installation
  --standalone      Run a standalone webserver for authentication
  (the certbot nginx plugin is not installed)
  --webroot         Place files in a server's webroot folder for authentication
  --manual          Obtain certificates interactively, or using shell script
hooks

   -n               Run non-interactively
  --test-cert       Obtain a test certificate from a staging server
  --dry-run         Test "renew" or "certonly" without saving any certificates
to disk

manage certificates:
    certificates    Display information about certificates you have from Certbot
    revoke          Revoke a certificate (supply --cert-path or --cert-name)
    delete          Delete a certificate

manage your account with Let's Encrypt:
    register        Create a Let's Encrypt ACME account
    update_account  Update a Let's Encrypt ACME account
  --agree-tos       Agree to the ACME server's Subscriber Agreement
   -m EMAIL         Email address for important account notifications

More detailed help:

  -h, --help [TOPIC]    print this message, or detailed help on a topic;
                        the available TOPICS are:

   all, automation, commands, paths, security, testing, or any of the
   subcommands or plugins (certonly, renew, install, register, nginx,
   apache, standalone, webroot, etc.)
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
root@docker-wiki-experiment:~# certbot --apache xr.swirly.com
usage:
  certbot [SUBCOMMAND] [options] [-d DOMAIN] [-d DOMAIN] ...

Certbot can obtain and install HTTPS/TLS/SSL certificates.  By default,
it will attempt to use a webserver both for obtaining and installing the
certificate.
certbot: error: unrecognized arguments: xr.swirly.com
root@docker-wiki-experiment:~# certbot --apache -d xr.swirly.com
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Plugins selected: Authenticator apache, Installer apache
Obtaining a new certificate
Performing the following challenges:
http-01 challenge for xr.swirly.com
Waiting for verification...
Cleaning up challenges
Created an SSL vhost at /etc/apache2/sites-available/bookstack-le-ssl.conf
Enabled Apache socache_shmcb module
Enabled Apache ssl module
Deploying Certificate to VirtualHost /etc/apache2/sites-available/bookstack-le-ssl.conf
Enabling available site: /etc/apache2/sites-available/bookstack-le-ssl.conf

Please choose whether or not to redirect HTTP traffic to HTTPS, removing HTTP access.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
1: No redirect - Make no further changes to the webserver configuration.
2: Redirect - Make all requests redirect to secure HTTPS access. Choose this for
new sites, or if you're confident your site works on HTTPS. You can undo this
change by editing your web server's configuration.
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Select the appropriate number [1-2] then [enter] (press 'c' to cancel): 1

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Congratulations! You have successfully enabled https://xr.swirly.com

You should test your configuration at:
https://www.ssllabs.com/ssltest/analyze.html?d=xr.swirly.com
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

IMPORTANT NOTES:
 - Congratulations! Your certificate and chain have been saved at:
   /etc/letsencrypt/live/xr.swirly.com/fullchain.pem
   Your key file has been saved at:
   /etc/letsencrypt/live/xr.swirly.com/privkey.pem
   Your cert will expire on 2020-03-17. To obtain a new or tweaked
   version of this certificate in the future, simply run certbot again
   with the "certonly" option. To non-interactively renew *all* of
   your certificates, run "certbot renew"
 - If you like Certbot, please consider supporting our work by:

   Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
   Donating to EFF:                    https://eff.org/donate-le

root@docker-wiki-experiment:~#
