#!/bin/bash

# Warning is default
DEFS="-DAOO_LOG_LEVEL=Verbose"
#DEFS="-DAOO_LOG_LEVEL=Warning"

if [ -n "${AAX_SDK_PATH}" ] ; then
  DEPS="$DEPS -DAAX_SDK_PATH=${AAX_SDK_PATH}"
fi

if [ -n "${VST2_SDK_PATH}" ] ; then
  DEPS="$DEPS -DVST2_SDK_PATH=${VST2_SDK_PATH}"
fi

TEAMOPT=""
if [ x"$APPLE_TEAMID" != x ] ; then
 TEAMOPT=-DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM=$APPLE_TEAMID
fi

# xcode
cmake -GXcode ${DEPS} ${DEFS} -B buildXcode ${TEAMOPT}



