#!/bin/bash
# spostare i files dalla dir corrente
# nella dir che porta il nome dell'anno
# ;;presume che le directory esistano
#
#
TOTAL=0
for (( x=2024, y=20240101, z=20250101; y>=20130101; y-=10000, z-=10000, x-=1 ))
do
        COUNT=0
        for target in $(find ./ -maxdepth 1 -type f -newermt $y -not -newermt $z)
        do
		mkdir -p $x
                echo -n "Moving: $target      -> /$x/$target "
                mv $target ./$x/
                echo "Done."
                (( COUNT++ ))
        done
        echo "Anno completato: $y - Files processati: $COUNT"
	(( TOTAL+=COUNT ))
done
