#!/bin/bash

# Parse options using getopt
TEMP=$(getopt -o r:t:v: --long repo:,tag:,value: -n 'getopt_example.sh' -- "$@")
if [ $? != 0 ]; then
    echo "Terminating..." >&2
    exit 1
fi

# Note the quotes around `$TEMP`: they are essential!
eval set -- "$TEMP"

# Initialize variables
flag_a=false
flag_b=false
value=""

# Extract options and their arguments
while true; do
    case "$1" in
        -r | --optiona )
           flag_a=$2; shift 2;;
        -t | --optionb )
           flag_b=$2; shift 2;;
        -v | --value )
           value=$2; shift 2;;
        -- )
            shift; break ;;
        * )
            break ;;
    esac
done

# Print parsed options and arguments
echo "Flag a: $flag_a"
echo "Flag b: $flag_b"
echo "Value: $value"
echo "Remaining arguments: $@"
