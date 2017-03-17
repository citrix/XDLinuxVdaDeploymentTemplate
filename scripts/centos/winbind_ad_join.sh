#!/usr/bin/bash

fname=$(basename $0)
scriptName=${fname%.*}  # Script name without extension

logFile="/var/log/$scriptName.log"

id_disk_mnt_point=/mnt/iddisk

NEW_HOSTNAME=""
FQDN=""
DDCS=""
domain=""
realm=""
PASSWORD=""
DNSDISID=""

DDC=""

BACKUP_EXT=".bak"
REALM=""
WORKGROUP=""

function log()
{
    PREFIX=$(date +"%b %d %T")
    echo "${PREFIX} ${1}" >> $logFile
}

function log_echo()
{
    log "$1"
    echo "$1"
}

#
# Check user, only root user has the permission to run this script
#
function check_user()
{
    if [ "$(id -u)" != 0 ]; then
        log_echo "The script must be run by root user"
        exit 1
    fi
}

function check_string_empty()
{
    if [ -z "$2" ]; then
	log_echo "$1 is empty, existing ..."
	exit 1
    fi
}

function read_id_disk()
{
    log_echo "enter read_id_disk"   
    
    # check whether ntfs-3g is installed
    FOUND_NTFS_3G=$(yum list installed | grep -i "ntfs-3g" > /dev/null 2>&1; echo $?)
    if [ ! $FOUND_NTFS_3G ]; then
        log_echo "NTFS-3G not installed, exit"
        exit 1
    else
        log_echo "NTFS-3G is installed."
    fi

    # test whether id disk is attached
    iddisk_dev_name=$(lsblk | grep 13M | sed 's/^[^[:alnum:]]*\([[:alnum:]]\+\).*$/\1/')
    if [ -z "$iddisk_dev_name" ]; then
        log_echo "No id disk is attached to the machine. Exit!"
        exit 1
    else
        log_echo "identity disk is attach to /dev/$iddisk_dev_name"
    fi

    # create the mount point folder if it does not exist
    [ ! -d ${id_disk_mnt_point} ] && mkdir -p ${id_disk_mnt_point}

    # check whether the id disk is already mounted, if so, umount it
    if mount | grep "/dev/$iddisk_dev_name" ; then
        echo "/dev/$iddisk_dev_name already mounted, umount it"
        umount /dev/$iddisk_dev_name
    fi

    # mount the id disk to ${id_disk_mnt_point}
    echo "mounting /dev/$iddisk_dev_name to ${iddisk_dev_name}"
    mount -t ntfs-3g -o umask=077 /dev/$iddisk_dev_name ${id_disk_mnt_point}
    

    # check whether the id disk is an image preparation disk or id disk
    img_prep_signature=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep '\[ImagePreparation\]' | sed 's/\s//g'`
    if [ "$img_prep_signature" == "[ImagePreparation]" ]; then
        # extract the STATUS file name
        status_filename=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'StatusFile' | cut -d'=' -f2 | sed 's/\s//g'`

        # write status file to the root of ${id_disk_mnt_point}
        cat <<-EOF > ${id_disk_mnt_point}/${status_filename}
<?xml version="1.0"?>
<PreparationResults>
  <PreparationResults>
    <Status>Complete</Status>
    <CycleCount>1</CycleCount>
    <StepStatus>
      <OfficeRearm>Success</OfficeRearm>
      <EnableDHCP>Success</EnableDHCP>
      <PrepareMSMQ>Success</PrepareMSMQ>
      <OsRearm>Success</OsRearm>
      <PrepJoinDomain>Success</PrepJoinDomain>
    </StepStatus>
    <ThirdPartyStatus />
    <Log>
</Log>
  </PreparationResults>
</PreparationResults>
EOF
        # flush the image preparation status file to disk
        log_echo "flushing the status file to id disk..."
        sync ${id_disk_mnt_point}/${status_filename}
        #shutdown image prep machine
        sleep 5
        log_echo "shutting down the machine..."
        shutdown -h now

        log_echo "exiting ..."
        exit 0
    fi

#[Identity]
#ShortHostName=testlinux1
#LongHostName=testlinux1
#MachinePassword=AAAAAWVBVcfl3rum3Bry/ZZdcX8DAAAAAAAAADU1jv+N0hJ6Uxe80yWPo6itxVCWAdXT/h7M9rdboPg9kvJ6qFeAkhkwHXliXm0pwxAL6vFOJJAbDRQQUxPRFt3cfLjV1HQZQZRK4QEdY7KFbEH4mqcdw5lOO0Lr4ByRF07KEi12BPhcWi197gNSs73kMWpu4+uLzMKH7ae6Kl+BXrFeTHhCnN080JejeIRvZ/WcHg01MeoBN4AsomPz1BXIc46qIdmGVywB1zU7ZwNRF6l/spi4jwKoUATNTPwIxWzQf5lxLm/iTKwmID5Tx/FSxmiYiNOp/qksPwUNu481ao5oBtG8iFK1Ynpbh2Ky5Mdn4Sh419H3+2ay3AQi5QiFcperVaf2f9NjAFTL4FZBBfXpYYo7KSntVdX2dLiYBAAAAAAAAAAAAAAAAAAAAAA=
#Dhcpv6DUID=00,01,00,01,1f,a2,b5,20,00,0d,3a,30,d6,85,
#OldMachinePassword=KgAjADIAMQBwAEUANABQAGUASwBPADUA
#[VdaData]
#ListOfDDCs=jiz-DDC.test.local
#[Configuration]
#CleanOnBoot=True
#RandomizeAdminPassword=False
#[WriteBackCache]
#CacheMemory=0
#[DomainJoin]
#ClientSiteName=Default-First-Site-Name
#DCAddress=\\10.0.0.8
#DCName=\\jiz-DC.test.local
#DCSiteName=Default-First-Site-Name
#DNSDIDomName=test.local
#DNSDIForestName=test.local
#DNSDIGuid={625644B5-3919-4B49-A3A4-E301A2D3BBC6}
#DNSDIName=TEST
#DNSDISid=S-1-5-21-413870291-1820683683-4127413227
#DomainGuid={625644B5-3919-4B49-A3A4-E301A2D3BBC6}
#DomainName=test.local
#DomainAdminsSid=S-1-5-21-413870291-1820683683-4127413227-512
#DomainUsersSid=S-1-5-21-413870291-1820683683-4127413227-513

    # extract information from id disk
    NEW_HOSTNAME=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'LongHostName' | cut -d'=' -f2 | sed 's/\s//g'`
    FQDN=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'DCName' | cut -d'=' -f2 | sed 's/\\\\//g' | sed 's/\s//g'`
    DDCS=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'ListOfDDCs' | cut -d'=' -f2 | sed 's/\s//g'`
    realm=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'DomainName' | cut -d'=' -f2 | sed 's/\s//g'`

    # password is base64 encoded, so it need to be decoded here
    PASSWORD=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'MachinePassword' | cut -d'=' -f2 | sed 's/\s//g' | base64 -d`

    # DOMAIN SID
    DNSDISID=`cat ${id_disk_mnt_point}/PvsVm/CTXSOSID.INI | grep 'DNSDISid' | cut -d'=' -f2 | sed 's/\s//g'`

    check_string_empty "NEW_HOSTNAME" $NEW_HOSTNAME
    check_string_empty "FQDN" $FQDN
    check_string_empty "DDCS" $DDCS
    check_string_empty "realm" $realm
    check_string_empty "PASSWORD" $PASSWORD
    check_string_empty "DNSDISID" $DNSDISID

    log_echo "NEW_HOSTNAME = $NEW_HOSTNAME"
    log_echo "FQDN = $FQDN"
    log_echo "DDCS = $DDCS"
    log_echo "realm = $realm"
    log_echo "PASSWORD = $PASSWORD"
    log_echo "DNSDISID = $DNSDISID"


    DDC=${DDCS}
    REALM=`echo $realm | tr 'a-z' 'A-Z'`
    domain=`echo ${realm} | cut -d'.' -f1`
    DOMAIN=`echo ${domain} | tr 'a-z' 'A-Z'`

    log_echo "domain = $domain"

    log_echo "leave read_id_disk"
}

function conf_hostname()
{
    log_echo "enter conf_hostname"
    
    content_file="/etc/hosts"
    content="127.0.0.1 ${NEW_HOSTNAME}.${realm} $NEW_HOSTNAME localhost localhost.localdomain localhost4 localhost4.localdomain4"

    echo "$content" > "$content_file"

    hostname "$NEW_HOSTNAME"

    sysctl -w kernel.hostname="$NEW_HOSTNAME"  2>&1 >> "$logFile"
    log_echo "leave conf_hostname"
}

function conf_ntp()
{
    log_echo "enter conf_ntp"
    
    ntp_file="/etc/chrony.conf"
    sed -i -e '/^server.*iburst$/ d' "$ntp_file"
    echo "server $FQDN iburst" >> "$ntp_file"

    log_echo "leave conf_ntp"
}

function conf_winbind()
{
    log_echo "enter conf_winbind"
    
    # enable winbind daemon
    #/usr/bin/systemctl enable winbind.service 2>&1 >> "$logFile"
    # stop winbind daemon
    log_echo "Stopping winbind service"
    /usr/bin/systemctl stop winbind 2>&1 >> "$logFile"

    # configure winbind authentication
    args="--disablecache --disablesssd --disablesssdauth --enablewinbind --enablewinbindauth --disablewinbindoffline --smbsecurity=ads --smbworkgroup=$domain --smbrealm=$REALM --krb5realm=$REALM --krb5kdc=$FQDN --winbindtemplateshell=/bin/bash --enablemkhomedir --updateall --enablekrb5kdcdns --enablekrb5realmdns"

    log_echo "Execute command: authconfig $args"

    authconfig $args 2>&1 | tee -a "$logFile"
    [[ "$?" -ne "0" ]] && log_echo "failed to execute command: authconfig $args [Error]"

    smbFile="/etc/samba/smb.conf"
    krbFile="/etc/krb5.conf"
    pamFile="/etc/security/pam_winbind.conf"

    # Customize /etc/samba/smb.conf
    `sed -i '/kerberos method =.*$/d' "$smbFile"`
    `sed -i '/winbind refresh tickets =.*$/d' "$smbFile"`      # del line in case user execute the script multi times
    `sed -i '/\[global\]/a winbind refresh tickets = true' "$smbFile"`
    `sed -i '/\[global\]/a kerberos method = secrets and keytab' "$smbFile"`

     # Customize /etc/krb5.conf
    #`sed -i 's#default_ccache_name.*$#default_ccache_name = FILE:/tmp/krb5cc_%{uid}#g' "$krbFile"`
    `sed -i '/default_ccache_name.*$/d' "$krbFile"`
    `sed -i '/\[libdefaults\]/a default_ccache_name = FILE:/tmp/krb5cc_%{uid}' "$krbFile"`

    #default_tkt_enctypes = rc4-hmac des-cbc-crc des-cbc-md5
    #          default_tgs_enctypes = rc4-hmac des-cbc-crc des-cbc-md5
              
    `sed -i -e '/default_tkt_enctypes.*$/d' -e '/default_tgs_enctypes.*$/d' "$krbFile"`
    `sed -i '/\[libdefaults\]/a default_tkt_enctypes = rc4-hmac des-cbc-crc des-cbc-md5' "$krbFile"`
    `sed -i '/\[libdefaults\]/a default_tgs_enctypes = rc4-hmac des-cbc-crc des-cbc-md5' "$krbFile"`


    # under certain case, some lines are not commented out, we need to remove them

    # Customize /etc/security/pam_winbind.conf
    `sed -i 's/.*krb5_auth =.*$/krb5_auth = yes/g' "$pamFile"`
    `sed -i 's/.*krb5_ccache_type =.*$/krb5_ccache_type = FILE/g' "$pamFile"`
    `sed -i 's/.*mkhomedir =.*$/mkhomedir = yes/g' "$pamFile"`

    log_echo "leave conf_winbind"
}

function join_domain()
{
    SAMBA_SECRETS=/var/lib/samba/private/secrets.tdb
    KEYTAB=/etc/krb5.keytab
    
    log_echo "enter join_domain"
#    {
#key(42) = "SECRETS/SALTING_PRINCIPAL/DES/XENAPP.LOCAL"
#data(40) = "host/c72cat04.xenapp.local@XENAPP.LOCAL\00"
#}
#{
#key(36) = "SECRETS/MACHINE_PASSWORD.PREV/XENAPP"
#data(15) = "DI@m(wCj!x+0Ww\00"
#}
#{
#key(39) = "SECRETS/MACHINE_SEC_CHANNEL_TYPE/XENAPP"
#data(4) = "\02\00\00\00"
#}
#{
#key(31) = "SECRETS/MACHINE_PASSWORD/XENAPP"
#data(13) = "YY3IWxV(MGc4\00"
#}
#{
#key(39) = "SECRETS/MACHINE_LAST_CHANGE_TIME/XENAPP"
#data(4) = "\8A)\91X"
#}
#{
#key(20) = "SECRETS/SID/CENTOS72"
#data(68) = "\01\04\00\00\00\00\00\05\15\00\00\00\09\B5\B6\1D\C2\E6\EB\F3\E1]\1A\82\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
#}
#{
#key(18) = "SECRETS/SID/XENAPP"
#data(68) = "\01\04\00\00\00\00\00\05\15\00\00\00\DEm9\88\96\85x\0BR\EE\E1\E9\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
#}
#{
#key(20) = "SECRETS/SID/C72CAT04"
#data(68) = "\01\04\00\00\00\00\00\05\15\00\00\00\A5\93\B6u\B0\C6WA\A8\1E\C2\99\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
#}

    log_echo "updating tdb database ..."
    
    log_echo "Changing SECRETS/SALTING_PRINCIPAL/DES/${REALM} to host/${NEW_HOSTNAME}.${domain}@${DOMAIN}"
    tdbtool ${SAMBA_SECRETS} store SECRETS/SALTING_PRINCIPAL/DES/${REALM} "host/${NEW_HOSTNAME}.${DOMAIN}@${REALM}\0"

    # update domain sid
    log_echo "Updating SECRET/SID/${DOMAIN} to ${DNSDISID}"
    net setdomainsid ${DNSDISID}

    # update machine password
    log_echo "Changing SECRETS/MACHINE_PASSWORD/${DOMAIN} to '${PASSWORD}'"
    echo "${PASSWORD}" | net -f -i changesecretpw

    net cache flush

    # update keytab file
    log "Updating $KEYTAB" 
    #if [ -f $KEYTAB ]; then
      #rm -f $KEYTAB
    #fi
    log_echo "sleeping for 10 seconds before creating keytab file..."
    sleep 10
    net ads keytab create -P
    if [[ "$?" -ne "0" ]]; then
        log_echo "Kerboros keytab creation failed!"
    else
        log_echo "Kerboros keytab creation succeed!"
    fi

    sleep 3

    # update dns record
    log_echo "updating DNS record ..."
    net ads dns register -P

    sleep 3

    STATUS=$(net ads testjoin > /dev/null; echo $?)
    if [ $STATUS -eq 0 ]; then
        log_echo "Machine join passed testing"
    else
        log_echo "Machine join failed testing"
    fi

    # start winbind service
    log_echo "starting winbind service ..."
    /usr/bin/systemctl start winbind 2>&1 >> "$logFile"

    log_echo "leave join_domain"
}

function setup_vda()
{
    log_echo "enter setup_vda"
    log_echo "updating VDA configurations ..."
    export CTX_XDL_SUPPORT_DDC_AS_CNAME=N
    export CTX_XDL_DDC_LIST=${DDCS}
    export CTX_XDL_VDA_PORT=80
    export CTX_XDL_REGISTER_SERVICE=Y
    export CTX_XDL_ADD_FIREWALL_RULES=Y
    export CTX_XDL_AD_INTEGRATION=1
    export CTX_XDL_HDX_3D_PRO=N
    export CTX_XDL_VDI_MODE=N
    export CTX_XDL_SITE_NAME='<none>'
    export CTX_XDL_LDAP_LIST=${FQDN}
    export CTX_XDL_SEARCH_BASE='<none>'
    export CTX_XDL_START_SERVICE=Y

    log_echo "CTX_XDL_SUPPORT_DDC_AS_CNAME=${CTX_XDL_SUPPORT_DDC_AS_CNAME}"
    log_echo "CTX_XDL_DDC_LIST=${CTX_XDL_DDC_LIST}"
    log_echo "CTX_XDL_VDA_PORT=${CTX_XDL_VDA_PORT}"
    log_echo "CTX_XDL_REGISTER_SERVICE=${CTX_XDL_REGISTER_SERVICE}"
    log_echo "CTX_XDL_ADD_FIREWALL_RULES=${CTX_XDL_ADD_FIREWALL_RULES}"
    log_echo "CTX_XDL_AD_INTEGRATION=${CTX_XDL_AD_INTEGRATION}"
    log_echo "CTX_XDL_HDX_3D_PRO=${CTX_XDL_HDX_3D_PRO}"
    log_echo "CTX_XDL_VDI_MODE=${CTX_XDL_VDI_MODE}"
    log_echo "CTX_XDL_SITE_NAME=${CTX_XDL_SITE_NAME}"
    log_echo "CTX_XDL_LDAP_LIST=${CTX_XDL_LDAP_LIST}"
    log_echo "CTX_XDL_SEARCH_BASE=${CTX_XDL_SEARCH_BASE}"
    log_echo "CTX_XDL_START_SERVICE=${CTX_XDL_START_SERVICE}"

    /opt/Citrix/VDA/sbin/ctxsetup.sh

    # sleep for 10 seconds
    #log_echo "Sleep for 10 seconds before starting VDA service"
    #sleep 10

    #log_echo "starting ctxhdx and ctxvda service"
    #systemctl start ctxhdx.service
    #systemctl start ctxvda.service

    log_echo "Enable seamless application"
    /opt/Citrix/VDA/bin/ctxreg create -k "HKLM\System\CurrentControlSet\Control\Citrix" -t  "REG_DWORD"  -v "SeamlessEnabled"  -d  "0x00000001"  --force


    log_echo "leave setup_vda"

}

function check_skip_file()
{
    skip_file="/usr/lib/mcs/.skip"
    if [ -f "$skip_file" ]; then
        rm $skip_file
        log_echo "Skip file found! Skip running the rest of MCS script!"
        exit 0
    fi
}

function create_skipfile_and_reboot()
{
    log_echo "Creating skip file..."
    if [ ! -d "/usr/lib/mcs" ]; then
        log_echo "folder /usr/lib/mcs not found! Exit"
        exit 1
    fi

    touch /usr/lib/mcs/.skip

    log_echo "rebooting the machine..."
    shutdown -r now
}

function main()
{
    log_echo "enter main"
    check_user
    check_skip_file
    read_id_disk
    conf_hostname
    conf_ntp
    conf_winbind
    join_domain
    setup_vda
    create_skipfile_and_reboot
    log_echo "leave main"
}

main "$@"
