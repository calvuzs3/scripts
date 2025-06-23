#!/bin/bash
changeIFSlocal() {
    local IFS=.
    echo "During local: |$IFS|"
}
changeIFSglobal() {
    IFS=.
    echo "During global: |$IFS|"
}
echo "Before: |$IFS|"
changeIFSlocal
echo "After local: |$IFS|"
changeIFSglobal
echo "After global: |$IFS|"
