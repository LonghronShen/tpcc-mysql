#!/bin/bash

# Configration

MYSQL=/usr/bin/mysql
TPCCLOAD=./tpcc_load
TABLESQL=./create_table.sql
CONSTRAINTSQL=./add_fkey_idx.sql
DEGREE=`getconf _NPROCESSORS_ONLN`

SERVER=localhost
DATABASE=tpcc
USER=tpcc
PASS=tpcc
WAREHOUSE=10

# Load

set -e
$MYSQL -u $USER -p$PASS -e "DROP DATABASE IF EXISTS $DATABASE"
$MYSQL -u $USER -p$PASS -e "CREATE DATABASE $DATABASE"
$MYSQL -u $USER -p$PASS $DATABASE < $TABLESQL

echo 'Loading item ...'
$TPCCLOAD $SERVER $DATABASE $USER $PASS $WAREHOUSE 1 1 $WAREHOUSE > /dev/null

set +e
STATUS=0
trap 'STATUS=1; kill 0' INT TERM

for ((WID = 1; WID <= WAREHOUSE; WID++)); do
    echo "Loading warehouse id $WID ..."
    
    (
        set -e
        
        # warehouse, stock, district
        $TPCCLOAD $SERVER $DATABASE $USER $PASS $WAREHOUSE 2 $WID $WID > /dev/null
        
        # customer, history
        $TPCCLOAD $SERVER $DATABASE $USER $PASS $WAREHOUSE 3 $WID $WID > /dev/null
        
        # orders, new_orders, order_line
        $TPCCLOAD $SERVER $DATABASE $USER $PASS $WAREHOUSE 4 $WID $WID > /dev/null
    ) &
    
    PIDLIST=(${PIDLIST[@]} $!)
    
    if [ $((WID % DEGREE)) -eq 0 ]; then
        for PID in ${PIDLIST[@]}; do
            wait $PID
            
            if [ $? -ne 0 ]; then
                STATUS=1
            fi
        done
        
        if [ $STATUS -ne 0 ]; then
            exit $STATUS
        fi
        
        PIDLIST=()
    fi
done

for PID in ${PIDLIST[@]}; do
    wait $PID
    
    if [ $? -ne 0 ]; then
        STATUS=1
    fi
done

if [ $STATUS -eq 0 ]; then
    $MYSQL -u $USER -p$PASS $DATABASE < $CONSTRAINTSQL
    echo 'Completed.'
fi

exit $STATUS
