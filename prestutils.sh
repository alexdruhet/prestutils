#!/usr/bin/env bash

# PrestUtils -- a program to perform prestashop environment syncing
# Usage :
# -h show this help text
# -v enable verbose mode
# -s sync staging to production (-s stl) or production to staging (-s lts)
# -r restore staging or production (-r s|staging|l|production)"

#-------------------------------------------------#
# SET UP
#-------------------------------------------------#

# Sites URLs
SITES[0]="my-uri.com"
SITES[1]="another-multisite-uri.com"
# and so on...

#
# Production instance parameters
#

# Root directory path
PRODUCTION[0]="/root"
# MySQL user
PRODUCTION[1]="user"
# MySQL password
PRODUCTION[2]="password"
# MySQL host
PRODUCTION[3]="localhost"
# MySQL database
PRODUCTION[4]="database"

#
# Staging instance parameters
#

# Root directory path
STAGING[0]="/root"
# MySQL user
STAGING[1]="user"
# MySQL password
STAGING[2]="password"
# MySQL host
STAGING[3]="localhost"
# MySQL database
STAGING[4]="database"
# Staging subdom 
# eg.: production is "my-uri.com" and staging equivalent is staging.my-uri.com
STAGING[5]="staging"

# Dump directory path
DUMP_PATH="/dumps_dir"
# Server user
# in most case the apache user
SRV_USR="www-data"
# Server user group
# in most case the apache user group
SRV_GRP="www-data"

# Colors
DEFAULT_COLOR='\033[0m'
SUCCESS_COLOR='\033[32m'
NOTICE_COLOR='\033[33m'
ERROR_COLOR='\033[31m'
SUCCESS_COLOR_BOLD='\033[32;1m'
NOTICE_COLOR_BOLD='\033[33;1m'
ERROR_COLOR_BOLD='\033[31;1m'

DONE=$SUCCESS_COLOR_BOLD'✔ Done'$DEFAULT_COLOR

#-------------------------------------------------#
# END SET UP
#-------------------------------------------------#

VERBOSE=""
VERBOSE_FLAG=""
DIRECTION="undefined"
USAGE="$(basename "$0") [-h|help] [-v|verbose] [-s|sync stl|lts] [-r|restore s|staging|l|production] -- A program to perform prestashop environment syncing
where:
    -h show this help text
    -v enable verbose mode
    -s sync staging to production (-s stl) or production to staging (-s lts)
    -r restore staging or production (-r s|staging|l|production)"

# Force processing with www-data user
if [[ $USER != $SRV_USR ]]; then
    echo -e $ERROR_COLOR_BOLD''$(basename "$0")' must be executed by the '$SRV_USR' user'$DEFAULT_COLOR
    echo 'Enter '$SRV_USR' password an try again'
    su $SRV_USR
    exit 0
fi

# backup production files and DB
function saveProduction ()
{
    echo -e ${NOTICE_COLOR}'Saving production DB'${DEFAULT_COLOR} 
    mysqldump ${VERBOSE_FLAG} --password=${PRODUCTION[2]} -u ${PRODUCTION[1]} --host=${PRODUCTION[3]} ${PRODUCTION[4]} > ${DUMP_PATH}/${PRODUCTION[4]}.`date +%Y-%m-%d`.sql
    echo -e ${DONE} 
    echo -e ${NOTICE_COLOR}'Archiving production files'${DEFAULT_COLOR} 
    echo -e ${NOTICE_COLOR}'You should warm a coffee, because this may take few minutes'${DEFAULT_COLOR} 
    tar ${VERBOSE_FLAG} -czf ${DUMP_PATH}/$(basename ${PRODUCTION[0]}).`date +%Y-%m-%d`.tar.gz --totals ${PRODUCTION[0]}
    echo -e $DONE
}

# backup staging files and DB
function saveStaging ()
{
    echo -e ${NOTICE_COLOR}'Saving staging DB'${DEFAULT_COLOR} 
    mysqldump ${VERBOSE_FLAG} --password=${STAGING[2]} -u ${STAGING[1]} --host=${STAGING[3]} ${STAGING[4]} > ${DUMP_PATH}/${STAGING[4]}.`date +%Y-%m-%d`.sql
    echo -e ${DONE}
    echo -e ${NOTICE_COLOR}'Archiving staging files'${DEFAULT_COLOR} 
    echo -e ${NOTICE_COLOR}'You should warm a coffee, because this may take few minutes'${DEFAULT_COLOR}
    tar ${VERBOSE_FLAG} -czf ${DUMP_PATH}/$(basename ${STAGING[0]}).`date +%Y-%m-%d`.tar.gz --totals ${STAGING[0]}
    echo -e $DONE
}

# import production DB dump to staging DB
function importDBProductionToStaging ()
{
    echo -e ${NOTICE_COLOR}'Importing latest Production DB to staging DB'${DEFAULT_COLOR}
    mysql ${VERBOSE_FLAG} -u ${STAGING[1]} --password=${STAGING[2]} --host=${STAGING[3]} ${STAGING[4]} < ${DUMP_PATH}/${PRODUCTION[4]}.`date +%Y-%m-%d`.sql
    echo -e ${DONE}
    echo -e ${NOTICE_COLOR}'Editing staging DB'${DEFAULT_COLOR} 

    # SQL commands concatenation
    SQL1="UPDATE ps_configuration SET"
    SQL2="UPDATE ps_shop_url SET"
    for URI in "${SITES[@]}"
    do
        SQL1=${SQL1}" value = REPLACE(value,'${URI}','${STAGING[5]}.${URI}'),"
        SQL2=${SQL2}" domain = REPLACE(domain,'${URI}','${STAGING[5]}.${URI}'), domain_ssl = REPLACE(domain,'${URI}','${STAGING[5]}.${URI}'),"
    done
    SQL1=${SQL1}";"
    SQL2=${SQL2}";"
    
    mysql ${VERBOSE_FLAG} -u ${STAGING[1]} --password=${STAGING[2]} --host=${STAGING[3]} ${STAGING[4]} -e "${SQL1} ${SQL2}"
    echo -e ${DONE}
}

# restore latest staging DB
function restoreLatestDBStaging ()
{
    echo -e ${NOTICE_COLOR}'Restoring latest staging DB'${DEFAULT_COLOR}
    mysql ${VERBOSE_FLAG} -u ${STAGING[1]} --password=${STAGING[2]} --host=${STAGING[3]} ${STAGING[4]} < ${DUMP_PATH}/${STAGING[4]}.`date +%Y-%m-%d`.sql
    echo -e ${DONE}
}

# restore latest production DB
function restoreLatestDBProduction ()
{
    echo -e ${NOTICE_COLOR}'Restoring latest Production DB'${DEFAULT_COLOR}
    mysql ${VERBOSE_FLAG} -u ${PRODUCTION[1]} --password=${PRODUCTION[2]} --host=${PRODUCTION[3]} ${PRODUCTION[4]} < ${DUMP_PATH}/${PRODUCTION[4]}.`date +%Y-%m-%d`.sql
    echo -e ${DONE}
}

# replace staging files with production files
function importFilesProductionToStaging ()
{
    echo -e ${NOTICE_COLOR}'Importing latest Production files to staging directory'${DEFAULT_COLOR}
    rm ${VERBOSE_FLAG} -rf ${STAGING[0]}/*
    tar ${VERBOSE_FLAG} -xzf ${DUMP_PATH}/$(basename ${PRODUCTION[0]}).`date +%Y-%m-%d`.tar.gz -C ${STAGING[0]}
    mv ${STAGING[0]}${PRODUCTION[0]}/* ${STAGING[0]}
    rm ${VERBOSE_FLAG} -rf ${STAGING[0]}${PRODUCTION[0]}
    echo -e ${DONE}
    echo -e ${NOTICE_COLOR}'Editing settings'${DEFAULT_COLOR}

    sed -i "s/${PRODUCTION[4]}/${STAGING[4]}/g" ${STAGING[0]}/config/settings.inc.php
    for URI in "${SITES[@]}"
    do
        sed -i "s/${URI}/${STAGING[5]}.${URI}/g" ${STAGING[0]}/.htaccess
    done

    echo -e ${DONE}
    echo -e ${NOTICE_COLOR}'Clearing smarty cache'${DEFAULT_COLOR}
    rm ${VERBOSE_FLAG} -rf ${STAGING[0]}/tools/smarty/compile/*
    echo -e ${DONE}
}

# replace production files with staging  files
function importFilesStagingToProduction ()
{
    echo -e ${NOTICE_COLOR}'Importing latest staging files to production directory'${DEFAULT_COLOR}
    tar ${VERBOSE_FLAG} -xzf ${DUMP_PATH}/$(basename ${STAGING[0]}).`date +%Y-%m-%d`.tar.gz -C ${PRODUCTION[0]}
    mv ${PRODUCTION[0]}${STAGING[0]}/* ${PRODUCTION[0]}
    rm ${VERBOSE_FLAG} -rf ${PRODUCTION[0]}${STAGING[0]}
    
    sed -i "s/${STAGING[4]}/${PRODUCTION[4]}/g" ${PRODUCTION[0]}/config/settings.inc.php
    for URI in "${SITES[@]}"
    do
        sed -i "s/${STAGING[5]}.${URI}/${URI}/g" ${PRODUCTION[0]}/.htaccess
    done

    echo -e ${DONE}
    echo -e ${NOTICE_COLOR}'Clearing smarty cache'${DEFAULT_COLOR}
    rm ${VERBOSE_FLAG} -rf ${PRODUCTION[0]}/tools/smarty/compile/*
    echo -e ${DONE}
}

# restore latest staging files backup
function restoreLatestFilesStaging ()
{
    echo -e ${NOTICE_COLOR}'Restoring latest staging files'${DEFAULT_COLOR}
    rm -rf ${STAGING[0]}/*
    tar ${VERBOSE_FLAG} -xzf ${DUMP_PATH}/$(basename ${STAGING[0]}).`date +%Y-%m-%d`.tar.gz -C /
    echo -e ${DONE}
}

# restore latest production files backup
function restoreLatestFilesProduction ()
{
    echo -e ${NOTICE_COLOR}'Restoring latest production files'${DEFAULT_COLOR}
    tar ${VERBOSE_FLAG} -xzf ${DUMP_PATH}/$(basename ${PRODUCTION[0]}).`date +%Y-%m-%d`.tar.gz -C /
    echo -e ${DONE}
}

# restore latest staging files and DB backup
function restoreLatestStaging ()
{
    echo -e ${NOTICE_COLOR}'You are going to restore staging from the latest backup.'${DEFAULT_COLOR}
    echo -e ${NOTICE_COLOR_BOLD}'Do you really want to continue? (y/n):'${DEFAULT_COLOR}
    read answer
    case $answer in
        y|Y) 
            restoreLatestDBStaging
            restoreLatestFilesStaging 
            ;;
        *) 
            echo "operation aborted" >&2
            exit 1
            ;;
    esac
}

# restore latest production files and DB backup
function restoreLatestProduction ()
{
    echo -e $NOTICE_COLOR'You are going to restore production from the latest backup.'$DEFAULT_COLOR
    echo -e $NOTICE_COLOR_BOLD'Do you really want to continue? (y/n):'$DEFAULT_COLOR
    read answer
    case $answer in
        y|Y) restoreLatestDBProduction; restoreLatestFilesproduction ;;
        *) echo "operation aborted" >&2
           exit 1
           ;;
    esac
}

# arguments controller
while getopts ':hvs:r:' option; do
    case $option in

        # Help called
        h|help)  
            echo "${USAGE}"
            exit
            ;;

        # Verbose mode
        v|verbose) 
            VERBOSE="v" 
            VERBOSE_FLAG="-v" 
            ;;

        # Syncing called
        s|sync) 
            DIRECTION=$OPTARG 
            ;;

        # restoring called
        r|restore) 
            DIRECTION="none"
            case $OPTARG in
                s|staging) 
                    restoreLatestStaging 
                    ;;
                l|production) 
                    restoreLatestProduction 
                    ;;
            esac
            exit
            ;;

        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "${USAGE}" >&2
            exit 1
            ;;
        :)
            echo -e ${ERROR_COLOR_BOLD}'Option -'${OPTARG}' requires an argument'${DEFAULT_COLOR} >&2
            echo "${USAGE}" >&2
            exit 1
            ;;
    esac
done

# Check required option
if [ $DIRECTION == 'undefined' ]; then
    echo -e ${ERROR_COLOR_BOLD}'Using an option is mandatory!'${DEFAULT_COLOR}
    echo "${USAGE}" >&2
    exit 1

# Sync production to staging
elif [ $DIRECTION == 'lts' ]; then
    echo -e ${NOTICE_COLOR}'You are going to sync production to staging.'${DEFAULT_COLOR}
    echo -e ${NOTICE_COLOR_BOLD}'Do you really want to continue? (y/n):'${DEFAULT_COLOR}
    read answer
    case $answer in
        y|Y) 
            echo -e ${NOTICE_COLOR}'Start syncing production to staging'${DEFAULT_COLOR}
            ;;
        *) 
            echo "operation aborted" >&2
            exit 1
            ;;
    esac
    saveProduction
    saveStaging
    importDBProductionToStaging
    importFilesProductionToStaging

# Sync staging to production
elif [ $DIRECTION == 'stl' ]; then
    echo -e ${NOTICE_COLOR}'You are going to sync staging files to production files.'${DEFAULT_COLOR}
    echo -e ${NOTICE_COLOR_BOLD}'Do you really want to continue? (y/n):'${DEFAULT_COLOR}
    read answer
    case $answer in
        y|Y) 
            echo -e ${NOTICE_COLOR}'Start syncing staging to production'${DEFAULT_COLOR}
            ;;
        *) 
            echo "operation aborted" >&2
            exit 1
            ;;
    esac
fi
