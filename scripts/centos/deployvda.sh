#!/bin/bash

fname=$(basename $0)
scriptName=${fname%.*}  # Script name without extension
logFile="/var/log/$scriptName.log"

pkgListRhel=("postgresql-server"\
             "postgresql-jdbc"\
             "redhat-lsb-core"\
             "foomatic"\
             "nautilus"\
             "nautilus-open-terminal"\
             "totem-nautilus"\
             "brasero-nautilus"\
             "authconfig-gtk"\
             "pulseaudio"\
             "pulseaudio-module-x11"\
             "pulseaudio-gdm-hooks"\
             "pulseaudio-module-bluetooth"\
             "alsa-plugins-pulseaudio"\
             "pciutils"\
             "util-linux"\
             "openssh"\
             "openssh-clients"\
             "chrony"\
             "firewalld"\
             "foomatic-filters"\
             "java-1.8.0-openjdk"\
             "samba-winbind"\
             "samba-winbind-clients"\
             "krb5-workstation"\
             "authconfig"\
             "oddjob-mkhomedir")

pkgListRhelNum=${#pkgListRhel[@]}


pkg_mcs=("epel-release"\
	     "tdb-tools"\
	     "ntfs-3g")	     
pkg_mcs_num=${#pkg_mcs[@]}


lvda_pkg_url="https://github.com/jiz-citrix/LVDASoftware/releases/download/v0.1.0/XenDesktopVDA-7.12.0.375-1.el7_2.x86_64.rpm"
lvda_pkg_name=$(echo $lvda_pkg_url | sed -e "s#.*/\(.*\)\s*#\1#")

xdping_pkg_url="https://github.com/jiz-citrix/LVDASoftware/releases/download/v0.1.0/linux-xdping.gz"
xdping_pkg_name=$(echo $xdping_pkg_url | sed -e "s#.*/\(.*\)\s*#\1#")

mcs_sysd_unit_file_url="https://raw.githubusercontent.com/jiz-citrix/XDLinuxVDA/master/scripts/centos/ad_join.service"
mcs_sysd_unit_file=$(echo $mcs_sysd_unit_file_url | sed -e "s#.*/\(.*\)\s*#\1#")

mcs_boot_script_url="https://raw.githubusercontent.com/jiz-citrix/XDLinuxVDA/master/scripts/centos/winbind_ad_join.sh"
mcs_boot_script=$(echo $mcs_boot_script_url | sed -e "s#.*/\(.*\)\s*#\1#")

vhci_hcd_version=1.15
vhci_hcd_url="https://github.com/jiz-citrix/LVDASoftware/releases/download/v0.1.0/vhci-hcd-${vhci_hcd_version}.tar.bz2"
build_dir="/tmp"


function check_user()
{
    if [ "$(id -u)" != 0 ]; then        
	    echo "this script must be run with root permission."
        exit 1
    fi
}


function createLogFile()
{
    if [[ ! -f "$logFile" ]]; then
        touch "$logFile"
        if [[ "$?" -ne "0" ]]; then
           get_str CTXINSTALL_CREAT_LOG_FAIL "$logFile"
        fi
    fi

    echo "#### Begin $scriptName ####">>$logFile
    str="`date "+%Y-%m-%d %H:%M:%S"`"
    echo $str>>$logFile
}

function my_print()
{
    echo -e "$1" | tee -a "$logFile"
}

#
# Output the message to log file only
#
function myLog()
{
    echo -e "$1">>"$logFile"
}

function disable_kernel_update()
{
    my_print "enter disable_kernel_update"
    yum_conf="/etc/yum.conf"
    sed -i '/^exclude=.*$/ d' $yum_conf
    echo "exclude=kernel" >> $yum_conf
    my_print "leave disable_kernel_update"
}

function install_desktop_environemnt()
{
    #yum -y group install "GNOME Desktop"
    my_print "enter install_desktop_environemnt"
    yum -y group install "GNOME Desktop"
    my_print "leave install_desktop_environemnt"
}

function install_lvda_package()
{
    my_print "enter install_lvda_package"
    cur_pwd=$(pwd)
    cd /tmp
    my_print "Downloading LVDA package from $lvda_pkg_url ..."
    wget $lvda_pkg_url

    my_print "Installing LVDA package ..."
    yum -y install $lvda_pkg_name
    cd $cur_pwd

    #cp -f ctxinstall.sh /opt/Citrix/VDA/sbin
    my_print "leave install_lvda_package"
}

function get_dns_hostname()
{
    my_print "enter get_dns_hostname"
    myhostname=$(hostname)
    mydns=$(cat /etc/resolv.conf | head -n 1 | sed -e "s/nameserver\s\s*\(\S*\).*/\1/")

    my_print "leave get_dns_hostname"
}



function install_lvda_dependency_pkgs()
{
    # Install the common packages
    info="Installing Linux VDA dependency packages ..."
    my_print "$info"
    for((i=0;i<pkgListRhelNum;i++)); do
         info="Installing package ${pkgListRhel[$i]}"
         my_print "$info"
         yum -y install ${pkgListRhel[$i]} 2>&1 >> "$logFile"
         if [[ "$?" -ne "0" ]]; then
              info="Failed to install ${pkgListRhel[$i]}"
              yum info ${pkgListRhel[$i]} 2>&1 >> "$logFile"
              [[ "$?" -ne "0" ]] && my_print "$info"
         fi
    done

    # Init db
    info="Initalize Database"
    my_print "$info"
    postgresql-setup initdb 2>&1 >> "$logFile"

    # set JAVA_HOME environment
    info="Setting JAVA_HOME environment"
    my_print "$info"
    `sed -i '/JAVA_HOME=.*$/d' ~/.bashrc`
    echo "export JAVA_HOME=/usr/lib/jvm/java">>~/.bashrc

    # start PostgreSQL
    info="Starting PostgreSQL database ..."
    my_print "$info"

    /usr/bin/systemctl enable postgresql.service  2>&1 >> "$logFile"
    /usr/bin/systemctl start postgresql  2>&1 >> "$logFile"

    sudo -u postgres psql -c 'show data_directory' 2>&1 >> "$logFile"

    # enable winbind service
    /usr/bin/systemctl enable winbind.service 2>&1 >> "$logFile"
}


function compile_usb_modules()
{
    my_print "enter compile_usb_modules"

    my_print "install kernel module building tools ..."
    
    yum -y install gcc
    yum -y install make

    # install the kernel-devel package

    # find the kernel-devel package in the vault first

    local kernel_version=$(uname -r)
    local kernel_pkg_name="kernel-devel-${kernel_version}.rpm"
    local kernel_pkg_url="http://vault.centos.org/7.2.1511/updates/x86_64/Packages/${kernel_pkg_name}"

    # enter to the build dir
    pushd $build_dir
    if [[ -f "$kernel_pkg_name" ]]; then
	rm $kernel_pkg_name
    fi

    my_print "Downloading $kernel_pkg_name from $kernel_pkg_url ..."
    wget $kernel_pkg_url -O $kernel_pkg_name
    if [[ "$?" -eq "0" ]]; then
	yum -y install "$kernel_pkg_name"
    else
	yum -y install kernel-devel
    fi
    

    my_print "Downloading vhci_hcd package from $vhci_hcd_url ..."
    wget $vhci_hcd_url -O vhci-hcd-${vhci_hcd_version}.tar.bz2
    
    if [[ "$?" != 0 ]]; then
	my_print "failed to download vhci-hcd-${vhci_hcd_version}, skip building USB kernel modules!!!"
	popd
        return
    fi

    if [ -d "vhci-hcd-${vhci_hcd_version}" ]; then
	echo "vhci-hcd-${vhci_hcd_version} exist, deleting ..."
	rm -rf vhci-hcd-${version}
    fi

    if [ -f "vhci-hcd-${vhci_hcd_version}.tar.bz2" ]; then
        tar jvxf vhci-hcd-${vhci_hcd_version}.tar.bz2
    fi

    if [ ! -d "vhci-hcd-${vhci_hcd_version}" ]; then
        my_print "failed to extract vhci-hcd-${vhci_hcd_version}, skip building USB kernel modules!!!"
        popd
        return
    fi

    my_print "start building USB kernel modules ... "
    
    local kernel_headers="/usr/src/kernels/$(uname -r)"
    local linux_vda_libdir="/opt/Citrix/VDA/lib64/"

    if [ ! -d "$kernel_headers" ]; then
	my_print "can not find the matching kernel headers, exit..."
	exit 1
    fi

    cd vhci-hcd-${vhci_hcd_version}
    sed -ie "s:^KDIR.*:KDIR = /usr/src/kernels/$(uname -r):" Makefile
    make

    if [ -f "usb-vhci-hcd.ko" -a -f "usb-vhci-iocifc.ko" ]; then
	my_print "build usb kernel modules succeed."
    else
	my_print "build usb kernel modules failed."
    fi

    if [ -d "$linux_vda_libdir" ]; then
	my_print "Copying the usb kernel modules to linux vda lib folder... "
	cp -f usb-vhci-hcd.ko usb-vhci-iocifc.ko $linux_vda_libdir
    else
	my_print "$linux_vda_libdir not found. Please install Linux VDA!" 
    fi
    
    popd
    my_print "leave compile_usb_modules"
}


function install_mcs_scripts()
{
    my_print "enter install_mcs_scripts"
    local mcs_script_folder=/usr/lib/mcs

    pushd $build_dir

    # download systemd unit file for MCS boot script
    wget $mcs_sysd_unit_file_url -O $mcs_sysd_unit_file
    if [[ "$?" -ne "0" ]]; then
        my_print "Failed to download $mcs_sysd_unit_file from $mcs_sysd_unit_file_url, exiting!!!"
        exit 1
    fi

    # download MCS boot script
    wget $mcs_boot_script_url -O $mcs_boot_script
    if [[ "$?" -ne "0" ]]; then
        my_print "Failed to download $mcs_boot_script from $mcs_boot_script_url, exiting!!!"
        exit 1
    fi

    my_print "installing mcs systemd unit file: ${mcs_sysd_unit_file} ... "
    install -o root -m 0555 ${mcs_sysd_unit_file} /etc/systemd/system/

    my_print "reloading systemd daemon..."
    systemctl daemon-reload

    my_print "setting ${mcs_sysd_unit_file} to start on boot"
    systemctl enable ${mcs_sysd_unit_file}

    my_print "installing MCS boot script ${mcs_boot_script}"
    install -o root -m 0755 -d ${mcs_script_folder}
    install -o root -m 0555 ${mcs_boot_script} ${mcs_script_folder}
    
    popd

    my_print "leave install_mcs_scripts"
    
}

function install_mcs_pkgs()
{
    my_print "enter install_mcs_pkgs"
    for ((i=0;i<pkg_mcs_num;i++)); do
        info="install pkg: ${pkg_mcs[$i]}"
        my_print "$info"
        yum -y install ${pkg_mcs[$i]}

        if [[ "$?" -ne "0" ]]; then
            my_print "install ${pkg_mcs[$i]} failed."
        fi
    done

    my_print "leave call_usb_modules_compile"
}

function install_xdping()
{
    my_print "enter install_xdping"
    
    pushd /tmp
    wget $xdping_pkg_url -O $xdping_pkg_name
    if [[ "$?" -ne "0" ]]; then
        my_print "failed to download $xdping_pkg_name"
        popd
        return
    fi

    tar zvxf $xdping_pkg_name
    if [[ "$?" -ne "0" ]]; then
        my_print "failed to extract $xdping_pkg_name"
        popd
        return
    fi

    yum install -y linux-xdping/RHEL/xdping*.rpm
    if [[ "$?" -ne "0" ]]; then
        my_print "failed to install $xdping_pkg_name"
        popd
        return
    fi

    popd
    my_print "leave install_xdping"
}


function main()
{
    my_print "enter main"
    check_user
    createLogFile
    disable_kernel_update
    install_desktop_environemnt
    install_lvda_dependency_pkgs
    install_lvda_package
    compile_usb_modules
    install_mcs_pkgs
    install_mcs_scripts
    install_xdping
    my_print "leave main"

}

main "$@"
