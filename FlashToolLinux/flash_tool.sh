#!/bin/sh
appname=`basename $0 | sed s/.sh$//g`

dirname=`dirname $0`
tmp="${dirname#?}"

if [ "${dirname%$tmp}" != "/" ]; then
    dirname=$PWD/$dirname
fi

LD_LIBRARY_PATH=$dirname
export LD_LIBRARY_PATH

export QT_X11_NO_MITSHM=1
$dirname/$appname "$@"
