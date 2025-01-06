#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "plz use <function_list_file> <path>"
    exit 1
fi

FUNCTION_LIST_FILE=$1
SEARCH_PATH=$2

if [ ! -f "$FUNCTION_LIST_FILE" ]; then
    echo "file:'$FUNCTION_LIST_FILE' does not exist."
    exit 1
fi

while IFS= read -r FUNCTION_NAME; do
    grep -rnw --include="*.c" --exclude-dir={test,tests} "$SEARCH_PATH" -e "$FUNCTION_NAME" | sed "s|$SEARCH_PATH/||g"
done < "$FUNCTION_LIST_FILE"
