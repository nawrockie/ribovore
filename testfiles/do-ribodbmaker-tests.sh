#!/bin/bash

$RIBOSCRIPTSDIR/ribotest.pl -f $RIBOSCRIPTSDIR/testfiles/ribodbmaker.testin rdb-test
if [ $? == 0 ]; then
   rm -rf rdb-test
   echo "Success: all tests passed"
   exit 0
else 
   echo "FAIL: at least one test failed"
   exit 1
fi
