#!/bin/bash

script_dir=$(dirname $0)
export logdir="/opt/seagate/eos-prvsnr/generated_configs/sc"
[ ! -d $logdir ] && mkdir -p $logdir

export tmpdir="$logdir/tmp"
[ ! -d $tmpdir ] && mkdir -p $tmpdir

export logfile=$logdir/controller.log
[ -f $logfile ] && rm -rf $logfile

source $script_dir/provision.sh
source $script_dir/xml.sh

export cli_cmd
export element
export ret_txt
export vsize=0
export pool_type
export pool_level
export pool_name
export disk_range
export nvols=8
export default_prv=false
export cleanup=false
export show_prov=false
export show_license=false
export load_license=false
export license_file=""
export user=""
export pass=""
export host=""
export ssh_tool="/usr/bin/sshpass"
export ssh_cred=""
export ssh_cmd=""
export remote_cmd=""
export range1
export range2
export dflt_ptype="linear"
export dflt_plvl="adapt"
export dflt_p1nam="dg01"
export dflt_p2nam="dg02"
export prvsnr_mode=""
export show_disks=false
export update_fw=false
export fw_bundle=""
export show_fw_ver=false
export show_license=false
export load_license=false

usage()
{
    echo -e " Utility to configure the Seagate Gallium stroage controller\n"\
    "=========================================================\n"\
    "usage:\n"\
    "$0\n\t { host -h <hostname|ip> -u <username> -p <password> }\n"\
    "\t [{ prov [-a|--all][-c|--cleanup][-s|--show-prov]\n"\
    "\t   [-t <pool-type> -l <level> -m <pool-name> -d <disk-range>"\
    "[-n <no-of-vols>] }]\n"\
    "\t [-s|--show-disks]\n"
    "\t [-h|--help]\n"
}

help()
{
    echo -e " Utility to configure the Seagate Gallium stroage controller\n"\
    "=========================================================\n"\
    "usage:\n"\
    "$0\n\t { host -h <hostname|ip> -u <username> -p <password> }\n"\
    "\t { prov [-a|--all][-c|--cleanup][-s|--show-prov]\n"\
    "\t   [-t <pool-type> -l <level> -m <pool-name> -d <disk-range>"\
    "[-n <no-of-vols>] }\n"\
    "\t [-s|--show-disks]"
    echo -e "\n"\
    "\t [-h|--help]\n"\
    "where:\n"\
    "  hostname      :- hostname or ip of the controller\n"\
    "  username      :- username of the controller to be provisioned,\n"\
    "                   user must have the manage role assigned to it\n"\
    "  password      :- password for the <username>\n"\
    "  pool-type     :- type of pool to be created - linear/virtual\n"\
    "  level         :- pool configuration level .e.g. adapt, r6 etc\n"\
    "                   supported levels: r1,r5,r6,r10,r50,adapt"
    echo -e "   pool-name     :- name of the pool to be created\n"\
    "                   for the virtual pool type the pool-name can only"\
    "be either 'a' or 'b'\n"\
    "  disk-range    :- range of disks e.g. '0.0-41',"\
    "                   '0.42-83', '0.0-5,0.7-20,0.24'\n"\
    "  no-of-vols    :- no of volumes to be created under the pool"\
    "<pool-name>, the argument\n"\
    "                   is optional, by default 8 volumes in a pool will be"\
    "created\n"\
    "  -a|--all      :- (Optional) Provisions the controller with standard"\
    "configuration:\n"\
    "                   2 linear pools with 8 volumes per pool mapped to all"\
    "the initiators\n"\
    "                   NOTE: -a option is mutually exclusive to <-t -l -m -d"\
    "-n> options\n"\
    "  -c|--cleanup  :- Cleanups the existing provisioning (delete all volumes"\
    "& pools)\n"\
    "  -s|--show-prov:- Shows current provisioning- only pools\n"
    echo -e " Sample commands:\n"\
    "========================================================="
    echo -e "\n"\
    "1. To cleanup existing pools and provision with the default configuration"\
    "for controller sati10b\n"\
    "   with following credentials(user/password) - admin/!admin"
    echo -e " \n\t $0 host -h 'sati10b' -u admin -p '!admin' prov -a -c"
    echo -e "\n"\
    "2. Create an adapt linear pool dg01 with disks ranging from 0.0 to 0.41"\
    "for controller ip 192.168.1.1\n"\
    "   with following credentials(user/password) - admin/!paswd"
    echo -e "\n"\
    " \n\t $0 host -h '192.168.1.1' -u admin -p '!paswd' prov -t linear -l"\
    "adapt -m dg01 -d '0.0-41'\n"\
    " \n\t Note: by default 8 volumes of equal size will also be created"\
    "under the dg01 &\n"\
    " \t       and mapped to all the initiators. To override this behavior\n"\
    " \t       use -n arg under prov option to provide the no of volumes\n"\
    " \t       to be created, e.g. shown below"
    echo -e "\n"\
    "3. Provision a raid6 virtual pool named 'a' for disks range"\
    "'0.42-0.83' & create 5 volumes under it.\n"\
    "   With controller host details as: (host: host.seagate.com, user:"\
    "admin, passwd: !passwd)\n"\
    " \n\t $0 host -h hostname -u admin -p '!passwd' prov -t virtual -l r6 -m"\
    "a -d '0.42-0.83' -n 5"
    echo -e "\n 4. Show the current provisioning on the controller"\
    "host(host10.seagate.com, admin, !passwd)\n"\
    " \n\t $0 host -h 'host.seagate.com' -u admin -p '!passwd' prov -s\n"
    echo -e "\n 5. Show/List the disks on the controller"\
    "host(host10.seagate.com, admin, !passwd)\n"\
    " \n\t $0 host -h 'host.seagate.com' -u admin -p '!passwd' -s"
}

parse_hopts()
{
  unset $host
  unset $user
  unset $pass
  echo "parse_hopts(): nargs:$#, \$@=$@">> $logfile
  [ $# -lt 6 ] && echo "invalid input" && exit 1
  while getopts ':h:u:p:' opt 
  do
      case $opt in
        h) host="$OPTARG";;
        u) user="$OPTARG";;
        p) pass="$OPTARG";;
        ?) echo "Unrecognized option '$OPTARG' for host"; usage; exit 1;;
        *) usage; exit 1;;
      esac
  done
  [ -z "$pass" -o -z "$host" -o -z "$user" ] && {
        echo "Error: proper input not provided for host"
        usage
        exit 1
  }
  echo "parse_hopts():$host, $user, $pass" >> $logfile
  ssh_cred="$ssh_tool -p $pass"
  ssh_cmd="ssh $user@$host"
  remote_cmd="$ssh_cred $ssh_cmd"
}

parse_args()
{
    echo "parse_args(): parsing input arguments" > $logfile
    host_optparse_done=false
    prov_optparse_done=false
    prvsnr_mode=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            host)
                if $host_optparse_done; then
                    echo "Error: host options already parsed"; exit 1
                fi
                echo "parse_args nargs=$#, args=$@" >> $logfile
                [ $# -lt 7 ] && {
                    echo "Error: insufficient arguments for host" && exit 1
                }
                hopts=("$2" "$3" "$4" "$5" "$6" "$7")
                parse_hopts "${hopts[@]}"
                shift 7
                host_optparse_done=true
                ;;
            prov)
                if $prov_optparse_done; then
                    echo "Error: prov options already parsed"; exit 1
                fi
                shift # this is to get rid of 'prov' 
                nvol_opt=false
                while [[ $# -gt 0 ]]
                do
                    case "$1" in
                        -a|--all)
                            default_prv=true
                            echo "parse_args(): default_prv=true">>$logfile
                            shift;;
                        -c|--cleanup)
                            cleanup=true;
                            echo "parse_args():clenaup=true" >>$logfile;shift;;
                        -s|--show-prov)
                            show_prov=true;
                            echo "parse_args():show_prov=true" >> $logfile
                            shift ;;
                        -t)
                            [ -z "$2" ] &&
                                echo "Error: pool-type not provided" && exit 1;
                            pool_type="$2"; shift 2;;
                        -l)
                            [ -z "$2" ] &&
                                echo "Error: pool-level not provided" && exit 1;
                            pool_level="$2"; shift 2 ;;
                        -m)
                            [ -z "$2" ] &&
                                echo "Error: pool-name not provided" && exit 1;
                            pool_name="$2"; shift 2 ;;
                        -d)
                            [ -z "$2" ] &&
                                echo "Error: disk-range not provided" && exit 1;
                            disk_range="$2"; shift 2 ;;
                        -n)
                            [ -z "$2" ] &&
                                echo "Error: nvols not provided" && exit 1;
                            nvols="$2"; nvol_opt=true;shift 2 ;;
                        *) break ;;
                    esac
                done
                [ ! -z "$pool_type" -a ! -z "$pool_level" -a \
                    ! -z "$pool_name" -a ! -z "$disk_range" ] && {
                        echo "parse_args(): manual provisioning" >> $logfile
                        prvsnr_mode="manual"
                } || {
                    [ ! -z "$pool_type" -o ! -z "$pool_level" -o\
                        ! -z "$pool_name" -o ! -z "$disk_range" ] && {
                            echo "parse_args():partial opts provided" >>$logfile
                            prvsnr_mode="partial"
                            echo "Error: Incomplete arguments provided"\
                                "for prov, make sure all of the [t|l|m|d]"\
                                "options are provided, exiting..." 
                            echo "Error, exiting.."
                        exit 1
                    }
                }
                echo "parse_args(): default_prv=$default_prv" >> $logfile
                echo "parse_args(): prvsnr_mode='$prvsnr_opts'" >> $logfile
                [ "$default_prv" = true -a ! -z "$prvsnr_mode" ] && {
                    echo "Error: the prov options [-a|--all] and"\
                        "-[t|l|m|d|n] are mutually exclusive,"\
                        " please use either of them, exiting.." 
                        exit 1
                }
                [ "$prvsnr_mode" = "manual" ] && {
                    [ $pool_type != "linear" -a $pool_type != "virtual" ] && {
                        echo "Error: Invalid pool-type provided,"\
                            "only 'linear' or 'virtual' are supported, exiting.."
                        exit 1
                    }
                    [ $pool_type = "virtual" ] && {
                        [ $pool_name != "a" -a $pool_name != "b" ] && {
                            echo "Error: Invalid 'virtual' pool-name provided"\
                                "'virtual' pool-type can only be 'a' or 'b'"
                            echo "Error, exiting"
                            exit 1
                        }
                    }
                }
                # exit if none of the prov option is provided
                [ "$default_prv" = false -a "$prvsnr_mode" != "manual" -a\
                    "$cleanup" = false -a "$show_prov" = false ] && {
                        echo "Error: Insufficient prov opts provided"
                        exit 1
                }
                prov_optparse_done=true
                echo "parse_args(): continue: opt: $#, $@">> $logfile
                continue
                ;;
            -h|--help) help; exit 0 ;;
            -s|--show-disks)
                echo "parse_args(): show disks" >> $logfile
                if $prov_optparse_done; then
                    echo "Error: prov options already parsed"; exit 1
                fi
                show_disks=true
                shift
                ;;
            -u|--update-fw)
                echo "parse_args(): update firmware" >> $logfile
                update_fw=true
                [ -z "$2" ] &&
                    echo "Error: firmware bundle not provided" && exit 1;
                fw_bundle="$2"; shift 2
                [ "$prov_optparse_done" = true ] &&
                    echo "Error: firmware and prov options are not supported"\
                        "together.." && exit 1
                ftp_op=true ;;
            -v|--show-fw-ver)
                echo "parse_args(): update firmware" >> $logfile
                show_fw_ver=true
                [ "$prov_optparse_done" = true ] &&
                    echo "Error: firmware and prov options are not supported"\
                        "together.." && exit 1
                shift
                ;;
            --show-license)
                echo "parse_args(): show license" >> $logfile
                show_license=true
                shift
                ;;
            -l|--load-license)
                echo "parse_args(): load license" >> $logfile
                [ "$prov_optparse_done" = true ] &&
                    echo "Error: firmware and prov options are not supported"\
                        "together.." && exit 1
                load_license=true
                [ -z "$2" ] &&
                    echo "Error: License file not provided" && exit 1;
                license_file="$2"
                shift 2 ;;
            *) echo "Invalid option $1"; exit 1;;
        esac
    done
    [ "$host_optparse_done" = false ] &&
        echo "Error: Controller details not provided, exiting.." && exit 1

    [ "$prov_optparse_done" = false -a "$show_disks" = false -a\
        "$show_license" = false -a "$load_license" = false -a\
        "$show_fw_ver" = false -a "$update_fw" = false ] && {
        echo "Error: Incomplete arguments provided, exiting.."
        exit 1
    } 
    echo "parse_args(): parsing done" >> $logfile
    return 0
}

check_packages()
{
   for pkg in "$@"; do
       [ ! -f "$pkg" ] && echo "Error: $pkg is not installed" && exit 1
   done   
}

main()
{
    check_packages "$ssh_tool" "$xml_cmd"
    parse_args "$@"
    [ "$prov_optparse_done" = true ] && do_provision
    [ "$show_disks" = true ] && disks_list
    [ "$load_license" = true ] && fw_license_load
    [ "$update_fw" = true ] && fw_update
    [ "$show_fw_ver" = true ] && fw_ver_get
    [ "$show_license" = true ] && fw_license_show

    rm -rf $tmpdir $xml_doc
}

main "$@"