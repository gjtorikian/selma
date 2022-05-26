#!/bin/bash

for id in `seq 100 199`; do
    groupadd -g $id group$id
    useradd -M -d /tmp -u $id user$id
done

exit 0
