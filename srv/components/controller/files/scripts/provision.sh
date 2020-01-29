#!/bin/bash
script_dir=$(dirname $0)

# run_cli_cmd()
# Arg1: cli command to run on enclosure, e.g. 'show version'
# Arg2: The element to be searched from the xml output of arg1 command.
# e.g. run_cli_cmd 'show version' 
cmd_run()
{
   _cmd=$1
    echo "cmd_run(): running: '$remote_cmd $_cmd'" >> $logfile
   $remote_cmd $_cmd | tail -n +2 | head -n -1 > $xml_doc
   validate_xml
   # Check if command was successful or not
   cli_status_get
}

license_check()
{
    tmp_file="$tmpdir/license"
    [ -f $tmp_file ] && rm -rf $tmp_file
    # objects name in the xml
    object_basetype="license"
    # list of properties of the object basetype to get their values from the
    # xml e.g. license for virtualization & vds
    property_list=("virtualization" "vds")
    echo "license_check(): Checking licenses "${property_list[@]}"" >> $logfile

    # run command to get the available ports
    echo "Checking licenses.."
    echo "license_check(): Running command: 'show license'" >> $logfile
    cmd_run 'show license'
    # parse xml to get required values of properties
    parse_xml $xml_doc $object_basetype "${property_list[@]}" > $tmp_file

    echo "------licenses---------" >> $logfile
    cat $tmp_file >> $logfile
    echo "-----------------------" >> $logfile
    # Get the status of virtualization license
    virtualization_license=`cat $tmp_file | awk '{ print $1 }'`
    [ "$virtualization_license" = "Disabled" -a "$pool_type" = "virtual" ] && {
        echo "Error: Can not create virtual pool, the virtualization"\
            "license is not installed."
        echo "Please install the virtualization license and try again"
        rm -rf $tmp_file
        exit 1
    }
    # Get the status of vds license
    # Not needed as of now
    # vds_license=`cat $tmp_file | awk '{ print $2 }'`
    #[[ "$vds_license" = "Enabled" ]] || {
    #    echo "license_check(): VDS license is not installed." >> $logfile
    #}
    echo "Virtualization license is enabled" >> $logfile
}

active_ports_get()
{
    _tmpfile=$tmpdir/ports
    # objects name in the xml
    object_basetype="port"
    # list of properties of the object basetype to get
    # their values from the xml e.g. port with status
    property_list=("port" "status")
    echo "active_ports_get(): Entry" >> $logfile
    echo "active_ports_get(): property_list=${property_list[@]}" >> $logfile

    echo "active_ports_get(): running command: 'show ports'" >> $logfile
    # run command to get the available ports
    cmd_run 'show ports'
    # parse xml to get required values of properties
    parse_xml $xml_doc $object_basetype "${property_list[@]}" > $_tmpfile

    # Get the ports with the status 'Up'
    # Convert the ports (with status UP) listed on individual
    # lines in to comma separated values
    # sed is to get rid of trailing comma
    port_list=`grep Up $_tmpfile | awk -vORS=, '{ print $1 }' | sed 's/,$/\n/'`
    echo "---port list---" >> $logfile
    echo $port_list >> $logfile
    echo "---------------" >> $logfile
    rm -rf $_tmpfile
    echo $port_list
}

cleanup_provisioning()
{
    _pools="$tmpdir/cleanup_pools"
    _prv_info="$tmpdir/prov_info"
    _xml_obj_base="pools"
    _xml_obj_plist=("name" "health")

    echo "cleanup_provisioning(): entry" >> $logfile
    pools_info_get $_xml_obj_base "${_xml_obj_plist[@]}" > $_pools
    [ ! -s $_pools ] && {
        echo "No pools in the system, nothing to cleanup."
        rm -rf $_pools
        return 0
    }
    echo "cleanup_provisioning(): deleting pools:" >> $logfile
    echo "cleanup_provisioning(): -----pools----------" >> $logfile
    cat $_pools >> $logfile
    echo "cleanup_provisioning():--------------------" >> $logfile
    for pool in `cat $_pools | tail -n+3 | awk '{ print $1 }'`
    do
        echo "Deleting pool $pool"
        echo "cleanup_provisioning(): running command:"\
            "'delete pools prompt yes $pool'" >> $logfile
        cmd_run "delete pools prompt yes $pool"
        echo "Pool $pool deleted successfully"
    done

    echo "Checking the provisioning again.."
    provisioning_info_get > $_prv_info
    [ -s $_prv_info ] || {
        echo "Cleanup done successfully"
        rm -rf $_pools $_prv_info
        return 0
    }
    echo "Error: Cleanup is incomplete, checking what did not get cleaned up"
    echo "getting pool details..."
    pools_info_get $_xml_obj_base "${_xml_obj_plist[@]}" > $_pools
    [ -s $_pools ] && {
        pools=`cat $_pools | tail -n+3 | awk '{ print $1 }'`
        [ -z "$pools" ] || {
            echo "Error: Following pool(s)/disk-group(s) could not be deleted."
            cat $_prv_info
        }
    } || echo "no pools found"
    echo "getting disk group details..."
    _xml_obj_base="disk-groups"
    _xml_dg_plist=("name" "pool" "status" "health")
    disk_groups_get $_xml_dg_obj_base "${_xml_dg_obj_plist[@]}" > $_pools
    [ -s $_pools ] && {
        dgs=`cat $_pools | tail -n+3 | awk '{ print $1 }'`
        [ -z "$dgs" ] || {
            echo "Error: Following pool(s)/disk-group(s) could not be deleted."
            cat $_prv_info
        }
    }
    rm -rf $_pools $_prv_info
}

is_system_clean()
{
    echo "is_system_clean(): Entry" >> $logfile
    _prv_info="$tmpdir/provisioning_info"
    [ -f $_prv_info ] && rm -rf $_prv_info
    provisioning_info_get > $_prv_info
    [ -s $_prv_info ] && {
        echo -e "Error: The storage controller is not in clean state\n"
        echo "Following pool(s)/disk-group(s) are currently provisioned"
        cat $_prv_info
        echo -e "\nPlease remove the above provisioning mannually and try again"
        echo "Or Rerun the command with -c|--cleanup option"
        rm -rf $_prv_info
        return 1
    } || echo "is_system_clean(): System is in clean state" >> $logfile
    rm -rf $_prv_info
    return 0
}

disk_group_add()
{
    _type=$1
    _level=$2
    _drange=$3
    _pool_name=$4

    echo "disk_group_add(): Entry" >> $logfile
    [ $_type = "virtual" ] && {
        [ "$_pool_name" != "a" -a "$_pool_name" != "b" ] && {
            echo "Error: Invalid virtual pool name provided- $_pool_name,"\
                 " virtual pool can either be a or b"
            exit 1
        }
        _pool_opts="pool $_pool_name"
    } || {
        _pool_opts="$_pool_name"
        [ "$_pool_opts" = "" ] && {
            echo "Error: Invalid linear disk-group name provided"
            exit 1
        }
    }

    _cmd_opts="type $_type disks $_drange level $_level $_pool_opts"
    _cmd="add disk-group $_cmd_opts"
    echo "disk_group_add(): running command: '$_cmd'" >> $logfile
    echo "Creating $_type pool '$_pool_name' with $_level level"\
         "over $_drange disks"
    cmd_run "$_cmd"
}

pools_info_get()
{
    _bt=$1
    shift
    _pl=("$@")
    _tmp_file="$tmpdir/sps"
    _pools="$tmpdir/pools_info"
    [ -f $_tmp_file ] && rm -rf $_tmp_file
    [ -f $_pools ] && rm -rf $_pools

    echo "pools_info_get(): Entry" >> $logfile
    echo "pools_info_get(): running command: show pools" >> $logfile
    cmd_run 'show pools'
    parse_xml $xml_doc $_bt "${_pl[@]}" > $_tmp_file
    [ -s $_tmp_file ] || {
        echo "pools_info_get(): No pools found on the controller" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    echo "pools_info_get(): --------- pools -------" >> $logfile
    cat $_tmp_file >> $logfile
    echo "pools_info_get(): ---------------------" >> $logfile
    printf '%s'"--------------------- Pools -----------------------\n" > $_pools
    printf '%-15s' "${_pl[@]}" >> $_pools
    printf '\n' >> $_pools
    while IFS=' ' read -r line
    do
       arr=($line)
       printf '%-15s' "${arr[@]}" >> $_pools
       printf '\n' >> $_pools
    done < $_tmp_file
    cat $_pools
}

disk_groups_get()
{
   _bt=$1
    shift
    _pl=("$@")
    _tmp_file="$tmpdir/tdgs"
    _dgs="$tmpdir/dg_info"
    [ -f $_tmp_file ] && rm -rf $_tmp_file
    [ -f $_dgs ] && rm -rf $_dgs

    echo "disk_groups_get(): Entry" >> $logfile
    echo "disk_groups_get(): running command: show disk-groups" >> $logfile
    # run command to get the pools
    cmd_run 'show disk-groups'
    # parse xml to get required values of properties
    parse_xml $xml_doc $_bt "${_pl[@]}" > $_tmp_file
    echo "disks_group_get(): Checking and printing the $_tmp_file" >> $logfile
    [ -s $_tmp_file ] || {
        echo "disks_group_get(): No disk-groups found on the"\
            "controller" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    echo "disks_group_get(): --------- dgs -------" >> $logfile
    cat $_tmp_file >> $logfile
    echo "disks_group_get(): ---------------------" >> $logfile
    printf '%s'"------------------- Disk-groups -------------------\n" > $_dgs
    printf '%-15s' "${_pl[@]}" >> $_dgs
    printf '\n' >> $_dgs
    while IFS=' ' read -r line
    do
       arr=($line)
       printf '%-15s' "${arr[@]}" >> $_dgs
       printf '\n' >> $_dgs
    done < $_tmp_file
    cat $_dgs
}

volumes_get()
{
   _bt=$1
    shift
    _pl=("$@")
    _tmp_file="$tmpdir/tmpvols"
    _vols="$tmpdir/vols_info"
    [ -f $_tmp_file ] && rm -rf $_tmp_file
    [ -f $_dgs ] && rm -rf $_dgs

    echo "volumes_get(): Entry" >> $logfile
    echo "volumes_get(): running command: show volumes" >> $logfile
    # run command to get the pools
    cmd_run 'show volumes'
    # parse xml to get required values of properties
    parse_xml $xml_doc $_bt "${_pl[@]}" > $_tmp_file
    echo "volumes_get(): Checking parsed output" >> $logfile
    [ -s $_tmp_file ] || {
        echo "volumes_get(): No volumes found on the controller" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    echo "volumes_get(): Getting vols details" >> $logfile
    echo "volumes_get(): --------- volumes -------" >> $logfile
    cat $_tmp_file >> $logfile
    echo "volumes_get(): ---------------------" >> $logfile
    printf '%s'"------------------- Volumes -----------------------\n" > $_vols
    printf '%-20s' "${_pl[@]}" >> $_vols
    printf '\n' >> $_vols
    while IFS=' ' read -r line
    do
       arr=($line)
       printf '%-20s' "${arr[@]}" >> $_vols
       printf '\n' >> $_vols
    done < $_tmp_file
    cat $_vols
}

disks_info_get()
{
    _bt=$1
    shift
    _pl=("$@")
    _tmp_file="$tmpdir/tmpdisks"
    _disks="$tmpdir/disks_info"
    [ -f $_tmp_file ] && rm -rf $_tmp_file
    [ -f $_disks ] && rm -rf $_disks

    echo "disks_get(): Entry" >> $logfile
    echo "disks_get(): running command: show disks" >> $logfile
    # run command to get the disks
    cmd_run 'show disks'
    # parse xml to get required values of properties
    parse_xml $xml_doc $_bt "${_pl[@]}" > $_tmp_file
    echo "disks_get(): Checking parsed output" >> $logfile
    [ -s $_tmp_file ] || {
        echo "disks_get(): No disks found on the controller" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    echo "disks_get(): Getting disks details" >> $logfile
    echo "disks_get(): --------- disks -------" >> $logfile
    cat $_tmp_file >> $logfile
    echo "disks_get(): ---------------------" >> $logfile
    printf '%s'"------------------- Disks -----------------------\n" > $_disks
    printf '%-15s' "${_pl[@]}" >> $_disks
    printf '\n' >> $_disks
    while IFS=' ' read -r line
    do
       arr=($line)
       echo "disks_info_get(): arr:$arr" >> $logfile
       printf '%-15s' "${arr[@]}" >> $_disks
       printf '\n' >> $_disks
    done < $_tmp_file
    cat $_disks 
}

disks_show_all()
{
    echo "disks_show_all(): Entry" >> $logfile
    _dsk="$tmpdir/disks"
    _xml_dsk_obj_base="drives"
    _xml_dsk_obj_plist=("slot" "location" "disk-group" "status" "health")
    [ -f "$_dsk" ] && rm -rf "$_dsk"
    disks_info_get $_xml_dsk_obj_base "${_xml_dsk_obj_plist[@]}" >> $_dsk
    [ -s $_dsk ] || {
        echo "disks_show_all(): No disks data found" >> $logfile
        return 0
    }
    cat $_dsk
}

disks_range_get()
{
    _dsk="$tmpdir/disks"
    _range1="$tmpdir/r1"
    _range2="$tmpdir/r2"
    _xml_dsk_obj_base="drives"
    _xml_dsk_obj_plist=("slot" "location" "disk-group" "status" "health")
    [ -f "$_dsk" ] && rm -rf "$_dsk"
    echo "disks_range_get(): Getting disks ranges" >> $logfile
    disks_info_get $_xml_dsk_obj_base "${_xml_dsk_obj_plist[@]}" > $_dsk
    [ -s $_dsk ] || {
        echo "disks_range_get(): No disks data found" >> $logfile
        return 0
    }
    
    echo "disks_range_get(): Checking free/available disks" >> $logfile
    ndisks=`cat $_dsk | grep "N/A"| grep "Up" | grep "OK" | wc -l`
    ndisks1=$(( ndisks/2 ))
    ndisks2=$(( ndisks1 + 1 ))
    echo "disks_range_get(): ndisks:$ndisks, ndisks1:$ndisks1,"\
        "ndisks2:$ndisks2" >> $logfile
    cat $_dsk | grep "N/A"| grep "Up" | grep "OK" | awk '{ print $1 }'\
        | head -n +$ndisks1 > $_range1
    cat $_dsk | grep "N/A"| grep "Up" | grep "OK" | awk '{ print $1 }'\
        | tail -n +$ndisks2 > $_range2
    #convert the ranges in to csv 
    echo "disks_range_get(): Converting the disk no to csv" >> $logfile
    ndisks=`cat $_dsk | grep "N/A"| grep "Up" | grep "OK" | wc -l`
    r1csv=`paste -d, -s $_range1`
    r2csv=`paste -d, -s $_range2`
    echo "disks_range_get(): r1cvs:$r1csv, r2csv:$r2csv">> $logfile
    __range1=`awk -F',' '{
        x = nxt = 0;
        for (i=1; i<=NF; i++)
        if ($i+1 == $(i+1)) { if (!x) x = $i"-"; nxt = $(i+1) }
        else { printf "%s%s", (x)? x nxt : $i, (i == NF)? ORS : FS; x = 0 }
        }'<<< "$r1csv"`
    __range2=`awk -F',' '{
        x = nxt = 0;
        for (i=1; i<=NF; i++)
        if ($i+1 == $(i+1)) { if (!x) x = $i"-"; nxt = $(i+1) }
        else { printf "%s%s", (x)? x nxt : $i, (i == NF)? ORS : FS; x = 0 }
        }'<<< "$r2csv"`
    range1=`echo $__range1 | sed 's/[^,]* */0.&/g'`
    range2=`echo $__range2 | sed 's/[^,]* */0.&/g'`
    echo "__range_1:$__range1, __range_2:$__range2" >> $logfile
    echo "range_1:$range1, range_2:$range2" >> $logfile
}

provisioning_info_get()
{
    _prv_all="$tmpdir/provisioning"
    _xml_dg_obj_base="disk-groups"
    _xml_dg_obj_plist=("name" "pool" "status" "health")
    _xml_obj_base="pools"
    _xml_obj_plist=("name" "health")
    _xml_vol_obj_base="volumes"
    _xml_vol_obj_plist=("volume-name" "size" "owner" "storage-pool-name" "health")
    [ -f "$_prv_all" ] && rm -rf "$prv_all"
    echo "provisioning_info_get(): Entry" >> $logfile
    pools_info_get $_xml_obj_base "${_xml_obj_plist[@]}" > $_prv_all
    disk_groups_get $_xml_dg_obj_base "${_xml_dg_obj_plist[@]}" >> $_prv_all
    volumes_get $_xml_vol_obj_base "${_xml_vol_obj_plist[@]}" >> $_prv_all
    [ -s $_prv_all ] || {
        echo "provisioning_info_get(): No provisioning data found" >> $logfile
        return 0
    }
    cat $_prv_all
}

remove_dg()
{
    _dg=$1
    echo "remove_dg(): Entry" >> $logfile
    echo "remove_dg(): running command 'remove disk-group $_dg'" >> $logfile

    cmd_run 'remove disk-group $_dg' > $xml_doc
    cli_status_get $xml_doc
}

remove_pool()
{
    _pool=$1
    echo "remove_pool(): Entry" >> $logfile
    echo "remove_pool(): running command 'delete pools $_pool'" >> $logfile
    cmd_run 'delete pools $_pool' > $xml_doc
    cli_status_get $xml_doc
}


convert_to_bytes()
{
    _avail_size=$1
    _kb=1000
    _mb=$_kb*$_kb
    _gb=$_mb*$_kb
    _tb=$_gb*$_kb
    _pb=$_tb*$_kb

    [ -z "$_avail_size" ] && {
        echo "convert_to_bytes(): Error: invalid input received"
        exit 1
    }
    _avail_size_unit=`echo $_avail_size | tr -dc 'A-Z'`
    _avail_size_val=`echo $_avail_size | sed 's/[^0-9.]*//g'`

    echo "convert_to_bytes(): _avail_size: $_avail_size" >> $logfile
    case $_avail_size_unit in
        B)
          _size_bytes=$_avail_size
          ;;
        KB)
          _size_bytes=`bc <<< $_avail_size_val*$_kb`
          ;;
        MB)
          _size_bytes=`bc <<< $_avail_size_val*$_mb`
          ;;
        GB)
          _size_bytes=`bc <<< $_avail_size_val*$_gb`
          ;;
        TB)
          _size_bytes=`bc <<< $_avail_size_val*$_tb`
          ;;
        PB)
          _size_bytes=`bc <<< $_avail_size_val*$_pb`
          ;;
    esac
    # get rid of the decimal points from the size in byte
    bsize=`echo $_size_bytes | cut -d'.' -f1`
    echo "convert_to_bytes(): $_avail_size in bytes: $bsize" >> $logfile
    echo $bsize
}

convert_from_bytes()
{
    _bytes=$1
    _tgt_unit=$2
    _kb=1000
    _mb=$_kb*$_kb
    _gb=$_mb*$_kb
    _tb=$_gb*$_kb
    _pb=$_tb*$_kb

    [ -z "$_bytes" -o -z "$_tgt_unit" ] && {
        echo "convert_from_bytes(): Error: invalid input received"
        exit 1
    }
    echo "convert_from_bytes():$_bytes to $_tgt_unit" >> $logfile
    case $_tgt_unit in
        KB)
          _tgt_usize=`bc -l <<< "scale=2; $_bytes/$(bc <<< $_kb)"`
          ;;
        MB)
          _tgt_usize=`bc -l <<< "scale=2; $_bytes/$(bc <<< $_mb)"`
          ;;
        GB)
          _tgt_usize=`bc -l <<< "scale=2; $_bytes/$(bc <<< $_gb)"`
          ;;
        TB)
          _tgt_usize=`bc -l <<< "scale=2; $_bytes/$(bc <<< $_tb)"`
          ;;
        PB)
          _tgt_usize=`bc -l <<< "scale=2; $_bytes/$(bc <<< $_pb)"`
          ;;
        *)
          echo "convert_from_bytes(): Eror: Invalid unit specified"
          exit 1
          ;;
    esac
    _tgt_usize=`printf "%.2f" "$_tgt_usize"`
    _tgt_usize="${_tgt_usize}$_tgt_unit"
    echo "convert_from_bytes(): $_bytes to $_tgt_unit: $_tgt_usize" >> $logfile
    echo $_tgt_usize
}

vol_size_get()
{
    _avail_size=$1
    _nvols=$2
    _avail_size_unit=`echo $_avail_size | tr -dc 'A-Z'`
    _bytes_avlblsize=`convert_to_bytes $_avail_size`
    _bytes_200mb=`convert_to_bytes 200MB`
    _bytes_2g=`convert_to_bytes 2GB`
    _bytes_24g=`convert_to_bytes 24GB`

    echo "vol_size_get(): avail_size:$_avail_size,"\
        "volumes to be created:$_nvols" >> $logfile
    [ $_bytes_avlblsize -lt $_bytes_200mb ] && {
        echo "Error: Insufficient pool size available:"\
            "`convert_from_bytes $_bytes_avlblsize MB`, exiting";
        exit 1
    }
    _new_size_in_bytes=$(( _bytes_avlblsize - _bytes_24g ))
    _volsize=`bc <<< $_new_size_in_bytes/$_nvols`
    echo "vol_size_get(): new size after 8gb less:"\
        "`convert_from_bytes $_new_size_in_bytes GB`" >> $logfile
    echo "vol_size_get()"\
        "`_volsize:$_volsize, `convert_from_bytes $_volsize GB``" >> $logfile
    [ $_volsize -lt $_bytes_2g ] && {
        echo -e "Error: Volume of size less than 2GB is not supported in EOS" 
        echo -e "Error: Insufficient space($_avail_size)"\
            "available in pool to create"\
                "$_nvols volumes of size of at least 2GB."
        return 1
    } 
    vsize=`convert_from_bytes $_volsize GB`
    echo "vol_size_get(): volsize:$vsize" >> $logfile
    return 0
}

base_lun_get()
{
    _luns="$tmpdir/luns"
    _bt="volume-view-mappings"
    _pl=("lun")

    echo "base_lun_get(): running command 'show volume-maps'" >> $logfile
    cmd_run 'show volume-maps'
    parse_xml $xml_doc $_bt "${_pl[@]}" > $_luns
    echo "base_lun_get(): -------- luns -------" >> $logfile
    cat $_luns >> $logfile
    echo "base_lun_get(): ---------------------" >> $logfile
    base_lun=`cat $_luns | grep -v "N/A" | sort -n | tail -1`
    base_lun=$((base_lun+1))
    echo $base_lun >> $logfile
    echo $base_lun
}

volumes_create()
{
    _baselun_opt="baselun $1"
    _basename_opt="basename $2"
    _nvols=$3
    _nvols_opt="count $_nvols"
    _pool_opt="pool $4"
    _size_opt="size $5"
    _ports_opt="ports $6"
    _cmd="create volume-set"
    _cmd_opts="access rw $_baselun_opt $_basename_opt $_nvols_opt $_pool_opt\
        $_size_opt $_ports_opt"
    _volset_create_cmd="${_cmd} $_cmd_opts"

    echo "volumes_create(): baselun:$1,basename:$2,nvols:$3,"\
        "pool-name:$4,vsize:$5" >> $logfile
    echo "Creating volume-set with $_nvols volumes of $_size_opt in"\
         " $_pool_opt with all the volumes mapped to $_ports_opt"

    cmd_run "$_volset_create_cmd"

    #TODO: Confirm if volume-set created successfully
}

# Provision the cluster
# input parameters
# _pool_type : Type of the pool to be created e.g. virtual or linear
# _level : pool level - adapt, r6 etc.
# _nvols : no of volumes to be created per pool, default 8
# _drange: disk range where the pool to be created over
# _pool_name : pool name
# 
# e.g.
# provision linear adapt 8 0.0-15 dg01
# provision virtual adapt 8 0.16-31 a/b
provision()
{
    _pool_type=$1
    _level=$2
    _nvols=$3
    _drange=$4
    _pool_name=$5
    _pools_info=$tmpdir/prv_pinfo
    
    [ -z "$_pool_type" -o -z "$_level" -o -z "$_nvols" -o \
        -z "$_drange" -o -z "$_pool_name" ] && {
        echo "Error: provision(): Invalid inputs received for provisioning"
        rm -rf $tmpdir
        exit 1
    }
    echo "provision(): pool-type:$1,level:$2,nvols:$3,disks:$4,"\
        "pool-name:$5" >> $logfile
    [ "$_pool_type" != "virtual" -a "$_pool_type" != "linear" ] && {
        echo "Error: Invalid pool type provided- $_pool_type, only virtual"\
             " and linear pool types are supported."
        rm -rf $tmpdir
        exit 1
    }

    # Add the disk group
    echo "provision(): creating $_pool_type pool/disk"\
        "group:$_pool_name" >> $logfile
    disk_group_add $_pool_type $_level $_drange $_pool_name

    # Get pool status to check pool size and health
    # Prepare arguments to be extracted from xml 
    _xml_obj_base="pools"
    _xml_obj_plist=("name" "total-size" "total-avail" "health")

    pools_info_get $_xml_obj_base "${_xml_obj_plist[@]}" > $_pools_info
    [ -s $_pools_info ] || {
        echo "Error: pool $_pool_name doesn't exist"
        rm -rf $_pools_info
        return 1
    }
    cat $_pools_info >> $logfile
    _pool_status=`cat $_pools_info | grep $_pool_name | awk '{ print $4 }'`
    [ "$_pool_status" = "OK" ] && {
        echo "Pool $_pool_name Created Successfully"
    } || {
        echo "Error: Pool $pool_name is not in good health, exiting";
        rm -rf $tmpdir
        exit 1
    }

    # Extract total space available  on the created pool
    _total_space=`cat $_pools_info | grep $_pool_name | awk '{ print $2 }'`
    _avail_space=`cat $_pools_info | grep $_pool_name | awk '{ print $3 }'`
    _avail_space_bytes=`convert_to_bytes $_avail_space`
    _avail_space_gb=`convert_from_bytes $_avail_space_bytes 'GB'`
    echo "provision(): total space in pool:$_total_space" >> $logfile
    echo "provision(): avail space in pool:$_avail_space" >> $logfile
    echo "provision(): avail space(gb) in pool:$_avail_space_gb" >> $logfile
    # Derive size of the volumes to be created
    vsize=0
    vol_size_get $_avail_space_gb $_nvols
    ret=$?
    [ $ret -ne 0 -o $vsize -eq 0 ] && {
        echo "Provision(): Error: exiting"
        rm -rf $tmpdir
        exit 1
    }
    echo "provision(): vol size:$vsize, nvols:$_nvols" >> $logfile

    #get all the UP ports on the controller, the volumes will be
    #mapped to all the ports.
    _ports=`active_ports_get`
    echo "provision(): active port list:$_ports" >> $logfile

    #Get base lun number, it is the next available lun number in the system.
    _baselun=`base_lun_get`
    echo "provision(): baselun:$_baselun" >> $logfile

    #basename is the prefix of the volume name e.g. poola-vol1, poola-vol2 etc
    _basename="$_pool_name-"

    #create volumeset and map all the volumes to all the ports
    echo "provision(): Creating volume-set" >> $logfile
    volumes_create $_baselun $_basename $_nvols $_pool_name $vsize $_ports
}

fw_ver_get()
{
    _tmp_file="$tmpdir/tmp_fw_ver"
    [ -f "$_tmp_file" ] && rm -rf "$_tmp_file"
    _fw_ver="$tmpdir/fw_ver"
    [ -f "$_fw_ver" ] && rm -rf "$_fw_ver"
    echo "fw_ver_get(): Entry" >> $logfile
    _xml_obj_bt="versions"
    _xml_obj_plist=("bundle-version")

    echo "fw_ver_get(): running command: show configuration" >> $logfile
    cmd_run 'show configuration'
    parse_xml $xml_doc $_xml_obj_bt "${_xml_obj_plist[@]}" > $_tmp_file
    [ -s $_tmp_file ] || {
        echo "fw_ver_get(): Couldn't get the firmware version" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    printf '%s'"fw_ver_get() Firmware version\n" > $_fw_ver
    cat $_tmp_file >> $logfile
    printf '%s'"--------------------- Firmware Version -----------------------\n" > $_fw_ver
    printf '%-15s' "${_xml_obj_plist[@]}" >> $_fw_ver
    printf '\n' >> $_fw_ver
    while IFS=' ' read -r line
    do
       arr=($line)
       printf '%-15s' "${arr[@]}" >> $_fw_ver
       printf '\n' >> $_fw_ver
    done < $_tmp_file
    cat $_fw_ver

}

midplane_serial_get()
{
    _tmp_file="$tmpdir/tmp_serial"
    [ -f "$_tmp_file" ] && rm -rf "$_tmp_file"
    _mp_serial="$tmpdir/mp_serial"
    [ -f "$_mp_serial" ] && rm -rf "$_mp_serial"
    echo "midplane_serial_get(): Entry" >> $logfile
    _xml_obj_bt="system"
    _xml_obj_plist=("midplane-serial-number")

    echo "midplane_serial_get(): running command: show system" >> $logfile
    cmd_run 'show system'
    parse_xml $xml_doc $_xml_obj_bt "${_xml_obj_plist[@]}" > $_tmp_file
    [ -s $_tmp_file ] || {
        echo "midplane_serial_get(): Couldn't get the midplane serial " >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    printf '%s'"midplane_seria_get() Serial number\n" > $_mp_serial
    cat $_tmp_file >> $logfile
    printf '%s'"--------------------- Serial number-----------------------\n" > $_mp_serial
    printf '%-15s' "${_xml_obj_plist[@]}" >> $_mp_serial
    printf '\n' >> $_mp_serial
    while IFS=' ' read -r line
    do
       arr=($line)
       printf '%-15s' "${arr[@]}" >> $_mp_serial
       printf '\n' >> $_mp_serial
    done < $_tmp_file
    cat $_mp_serial
}

sc_license_get()
{
    _tmp_file="$tmpdir/license-details"
    [ -f $_tmp_file ] && rm -rf $_tmp_file
    # objects name in the xml
    _xml_obj_bt="license"
    _xml_obj_plist=("virtualization" "volume-copy" "remote-snapshot-replication"\
    "vds" "vss" "sra")
    echo "sc_license_get(): Getting licenses "${_xml_obj_plist[@]}"" >> $logfile

    # run command to get the license details
    echo "Getting license details.."
    echo "sc_license_get(): Running command: 'show license'" >> $logfile
    cmd_run 'show license'
    # parse xml to get required values of properties
    parse_xml $xml_doc $_xml_obj_bt "${_xml_obj_plist[@]}" > $_tmp_file
    [ -s $_tmp_file ] || {
        echo "sc_license_get(): No licenses found on the controller" >> $logfile
        rm -rf $_tmp_file
        return 0
    }
    echo "------licenses---------" >> $logfile
    cat $_tmp_file >> $logfile
    echo "-----------------------" >> $logfile
    printf '%s'"--------------------- licenses ---------------------\n"
    declare -a license_details
    license_details=(`cat "$_tmp_file"`)
    for ((i=0; i<=${#_xml_obj_plist[@]}; i++)); do
        printf '%-28s %s\n' "${_xml_obj_plist[i]}" "${license_details[i]}"
    done
}

fw_license_load()
{
    #TODO: load license here using ftp

}

fw_update()
{
    #TODO: load fw_bundle here over ftp

}

fw_license_show()
{
    fw_ver_get
    midplane_serial_get
    sc_license_get
}

disks_list()
{
    _dskinfo=$tmpdir/dskinfo
    echo "Getting disks details.. this might take time"
    disks_show_all > $_dskinfo
    [ -s $_dskinfo ] && cat $_dskinfo || {
        echo "Error: No disks found on the controller."
        exit 1
    }
}

do_provision()
{
    _prvinfo=$tmpdir/prvinfo

    [ "$pool_type" = "virtual" ] && license_check
    [ "$cleanup" = true ] && cleanup_provisioning
    [ "$default_prv" = true ] && {
        echo "main(): default provisioning" >> $logfile
        is_system_clean
        ret=$?
        [ $ret -eq 1 ] && {
            echo "Error: Controller is not in clean state"
            exit 1
        }
        disks_range_get
        [ -z "$range1" -o -z "$range2" ] && {
            echo "Error: Could not derive the disk list to creat a pool"
            echo "Exiting."
            exit 1
        }
        # Provision the controller with provided input
        provision "$dflt_ptype" "$dflt_plvl" "$nvols" "$range1" "$dflt_p1nam"
        provision "$dflt_ptype" "$dflt_plvl" "$nvols" "$range2" "$dflt_p2nam"

        # Check if provisioning done successfully
        provisioning_info_get > $_prvinfo
        [ -s $_prvinfo ] && {
            echo "Controller provisioned successfully with following details:"
            cat $_prvinfo
         } || echo "Error: Controller could not be provisioned"
    }
    [ "$prvsnr_mode" = "manual" ] && {
        echo "main(): manual provisioning" >> $logfile

        # Provision the controller with provided input
        provision "$pool_type" "$pool_level" "$nvols" "$disk_range" "$pool_name"

        # Check if provisioning done successfully
        provisioning_info_get > $_prvinfo
        [ -s $_prvinfo ] && {
            echo "Controller provisioned successfully with following details:"
            cat $_prvinfo
         } || echo "Error: Controller could not be provisioned"
    }
    [ "$show_prov" = true ] && {
        provisioning_info_get > $_prvinfo
        [ -s $_prvinfo ] && cat $_prvinfo ||
            echo "No provisioning details found on the controller"
    }
}