#!/bin/bash
#

# Sistema la data  file (touch -t _time) tramite lettura
# della stessa nel nome file, secondo una  canonica struttura.
#
# Ad esempio sotto i dispositivi Android le foto hanno un nome del tipo 
#  IMG_AAAAMMGG_hhmmss.jpg ed i video del tipo VID_AAAAMMGG_hhmmss.mp4.
# Mentre le foto di WhatsApp sono del tipo 
#  IMG-AAAAMMDD_WAxxxxx.jpg ed i video del tipo VID-AAAAMMGG_WASEQ.mp4.

#In generale il nome del file può avere i seguenti caratteri:
#
 #   inizi con almeno 3 lettere e non più di 5 minuscole o maiuscole ( ^[A-Za-z]\{3,5\} );
  #  seguito dal carattere “–” o “_” ( [_-] );
   # seguito da 8 cifre ( AAAAMMDD [0-9]\{8\} );
    #seguito dal carattere “–” o “_” ( [_-] );
#    seguito da 2 caratteri (2 cifre o WA .\{2\} );
 #   seguito da 4 cifre ( mmss [0-9]\{4\} ).
  #  seguito da altri caratteri compresa l’estensione del file.
#
#Dove:   
#   AAAA è l’anno di 4 cifre dello scatto;
#    MM   è il mese di 2 cifre dello scatto;
 #   DD   è il giorno di 2 cifre dello scatto;
  #  hh   sono le ore di 2 cifre dello scatto;
   # mm   sono i minuti di 2 cifre dello scatto;
    #ss   sono i secondi di 2 cifre dello scatto;
#    WA   indica che il file è di WhatsApp e quindi si perdono le ore;
 #   SEQ  è una sequenza di 4 cifre a partire da 0000 e si incrementa di uno ad ogni nuova immagine dello stesso giorno: si perdono o minuti ed i secondi.


# Originariamente erano 3 almeno le lettere iniziali
# le porto a 1 perche ho alcuni file nominati P_AAAAMMGG..
#

# Global variables
EXIF_TMP_FILENAME="tmp.setTimeStamp.file.list"
EXIF_TMP_ERROR_FILENAME="tmp.setTimeStamp.error.log"
EXIF_WA_FOLDER="./Whatsapp"
LOGFILE="tmp.setTimeStamp.report.$(date +%Y-%m-%d_%H-%M-%S).log"
EDITED_SUFFIX="-modificato"
  
# Per IPHONE che salva con .HEIC
# si converte in jpeg
#
ConvertHEICtoJPEG() {
  for file in *.HEIC; do
    sips -s format jpeg "$file" --out "${file%.HEIC}.jpeg"
    mv -v "$file.json" "${file%.HEIC}.jpeg.json"
    rm $file
  done
}

# Aggiorna i metadati tramite .json
#
UpdateFromJson() {
  exiftool -d "%s" -tagsfromfile %d%F.json \
  "-DateTimeOriginal<PhotoTakenTimeTimeStamp" \
  "-FileCreationTime<PhotoTakenTimeTimeStamp" \
  "-FileModifyDate<PhotoTakenTimeTimeStamp" \
  -overwrite_original \
  -ext jpg \
  -ext jpeg \
  -ext mp4 \
  -ext mov
}

# Aggiorna i metadati tramite FileModifyDate
#
UpdateFromFileDate() {
  exiftool \
  "-DateTimeOriginal<FileModifyDate" \
  "-FileCreationTime<FileModifyDate" \
  "-FileModifyDate<FileModifyDate" \
  -overwrite_original \
  -ext jpg \
  -ext jpeg \
  -ext mp4 \
  -ext mov \
  $1
}

# Banale, ma funzia per i WA
#
SetTimestampByFilename() {
  local file="$@"
  local f=$(basename "$file")
  local filedate=""
  
  filedate=$( echo $f | sed -e 's/^\([A-Za-z]\{1,5\}\)[_-]//g' -e 's/[_-]WA\([0-9]\{4\}\).*$//g'  )1200.00
  
  if [ "x$f" != "x$filedate" ]; then
    readable_date=$(echo $filedate | sed -e 's/^\(....\)\(..\)\(..\)\(..\)\(..\)\.\(..\)/\/\/ ::/')
    echo "----- (SetTimestampByFilename) setting date of $file to $readable_date ($filedate)"
    touch -t "$filedate" "$file"
    
    ####### Now should adjust the exif 
    #######
    UpdateFromFileDate "$file"

    return 0
   else
     echo "***** (SetTimestampByFilename) err: Invalid file name format: $file" >> "$EXIF_TMP_ERROR_FILENAME"
     return 1
  fi
}

SetTimestampWAbyFilename() {
  local counter=0
  local counter_err=0
  IFS=

  # Se esiste cancella tmp.error..
  rm "$EXIF_TMP_ERROR_FILENAME" 2>/dev/null 1>&2
  
  echo "(SetTimeStampByExif) Begin ..."
  echo `find ./ -type f -name '*WA*' -not -name '*.json'` > "$EXIF_TMP_FILENAME"

  while read -r file
  do 
    SetTimestampByFilename "$file"
    (( counter_err+=$? ))
    (( counter++ ))
  done < "$EXIF_TMP_FILENAME"

    echo "Files processati..: $counter"
    echo "counter_err............: $counter_err"
    echo "Done."
  return 0
}

# Setta il file con il timestamp prelevato dagli exif
#
SetTimestampByExif() {
  local counter=0
  local counter_err=0
  IFS=

  echo "(SetTimeStampByExif) Begin ..."
  echo `find ./ -type f -not -name '*.json'` > "$EXIF_TMP_FILENAME"

  #for file in $(find ./ -type f -not -name '*.json')
  while read -r file
  do 

    local filedate=""
    local readable_date=""

    checkRedableDate () {
      date --date "$@" 2>/dev/null 1>&2
      if [ -z $? ]; then
        # TODO elaborare altre opzioni
        echo "***** (SetTimestampByExif) (CheckReadableDate) err: invalid exif date format ($@)" >&2
        return 1
      fi
      return 0
    }
    

    # Estraiamo la data
    filedate=$(exiftool -p '$photoTakenTime' -d "%Y%m%d%H%M.%S" "$file" 2>/dev/null)
    readable_date=$(exiftool -p '$photoTakenTime' -d "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null)
    checkRedableDate "$readable_date"; [ $? -ne 0 ] && $filedate=""

    if [ -z "$filedate" ]; then
      filedate=$(exiftool -p '$MediaCreateDate' -d "%Y%m%d%H%M.%S" "$file" 2>/dev/null)
      readable_date=$(exiftool -p '$MediaCreateDate' -d "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null)
      checkRedableDate "$readable_date"; [ $? -ne 0 ] && $filedate=""
    fi
    if [ -z "$filedate" ]; then
      filedate=$(exiftool -p '$CreateDate' -d "%Y%m%d%H%M.%S" "$file" 2>/dev/null )
      readable_date=$(exiftool -p '$CreateDate' -d "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null)
      checkRedableDate "$readable_date"; [ $? -ne 0 ] && $filedate=""
    fi
    if [ -z "$filedate" ]; then
      filedate=$(exiftool -p '$DateTimeOriginal' -d "%Y%m%d%H%M.%S" "$file" 2>/dev/null )
      readable_date=$(exiftool -p '$DateTimeOriginal' -d "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null)
      checkRedableDate "$readable_date"; [ $? -ne 0 ] && $filedate=""
    fi

    # Elaboriamo
    if [ -n "$filedate" ]; then
      echo "====== (SetTimestampByExif) $file - $readable_date -ok"
      #cp "${file}" "$file.orig"
      touch -t "$filedate" "$file"
    else
      # TODO elaborare altre opzioni
      echo "***** (SetTimestampByExif) err: exif date not found for: $file" >&2
      echo "***** (SetTimestampByExif) err: exif date not found for: $file" >> "$EXIF_TMP_ERROR_FILENAME"
      (( counter_err++ ))
    fi
    
    (( counter++ ))
  done < "$EXIF_TMP_FILENAME"
          
    echo "Files processati..: $counter."
    echo "Errori............: $counter_err."
    echo "Done."
    IFS=" "

  return 0
}

#Sostituiamo i file originali con i modificati
#
ReplaceOriginalsWithModified () {
  local counter=0
  local counter_err=0
  IFS=

  echo "(ReplaceOriginalsWithModified) Begin ..."
  echo `find ./ -type f -name '*modificato*' -not -name '*.json'` > "$EXIF_TMP_FILENAME"

  while read -r file
  do 
    # Recreate the original name
    original_file=$(echo "$file" | sed s/\-modificato//g )
  
    rm "$original_file"
    mv -v "$file" "./$original_file"
    echo "$file <== $original_file ..ok"
    (( counter_err+=$? ))
    (( counter++ ))
  done < "$EXIF_TMP_FILENAME"
    
    echo "Files processati..: $counter"
    echo "Errori............: $counter_err"
    echo "Done."
  return 0
}

#Sostituiamo i file originali con i modificati
#
MoveWAfilesToFolder () {
  
  counter=0
  counter_err=0
  IFS=

  # Start
  echo "(MoveWAfilesToFolder) Begin ..."
  mkdir -p "$EXIF_WA_FOLDER"

  # Search
  rm "$EXIF_TMP_FILENAME" 2>/dev/null
  echo `find ./ -type f -name '*WA*' -not -name '*.json' -not -path "$EXIF_WA_FOLDER"` > "$EXIF_TMP_FILENAME"

  # foreach file
  while read -r file
  do 
    #echo "==> $file ..ok"
    echo -n "*"
    mv -v "$file" "$EXIF_WA_FOLDER"
    (( counter++ ))
  done < "$EXIF_TMP_FILENAME"
    echo 
    echo "Files processati..: $counter"
    echo "Errori............: $counter_err"
    echo "Done."
  return 0
}

# Remove all json
#
RemoveAllJson () {
  
  local counter=0
  local counter_err=0
  IFS=

  echo "(RemoveAllJson) Begin ..."
  echo `find ./ -type f -name '*.json'` > "$EXIF_TMP_FILENAME"

  # foreach file
  while read -r file
  do 
    #echo "==> $file ..ok"
    echo -n "*"
    rm "$file" 2>/dev/null 1>&2
    [ $? -ne 0 ] && (( counter_err++ ))
    (( counter++ ))
  done < "$EXIF_TMP_FILENAME"
    echo 
    echo "Files processati..: $counter"
    echo "Errori............: $counter_err"
    echo "Done."
  return 0
}

RemoveTMPfiles() {
  rm $EXIF_TMP_ERROR_FILENAME 
  rm $EXIF_TMP_FILENAME 
  echo "Done."
  return 0
}


###############
# Applichiamo..
while :
do
  echo "Menu del giorno:"
  echo "   1) MODIFICATO: sostituisci gli originali con i -modificato"
  echo "   3) ALLDATES: sistema le date SE mancano gli exif"
  echo "   5) GPS: preleva dal .json SE mancano gli exif"
  echo "   9) EXIF: aggiusta la data file (POSIX) dagli exif"
  echo "  19) NOMEFILE (vecchi files WA - obsoleto)"
  echo "  21) SPOSTA WHATSAPP: sposta tutti i files WA nel path $EXIF_WA_FOLDER"
  echo "  97) PULIZIA: Elimina i files tmp.*"
  echo "  99) PULIZIA: Elimina tutti gli *.json"
  echo -n ": "
  read opt
  case $opt in
  1)
    # Per  sostituire gli original con i files editati
    # come Google ama fare, conserva agli originali immutati,
    # crea un secondo file (nomefile)-modificato.(ext)
    #
    echo "Hai scelto MODIFICATO" 
    ReplaceOriginalsWithModified
    ;;
  3)
    echo "Aggiustatutto: Hai scelto reperire gli exif mancanti dal .json" 
      #
      # Recursivo, aggiunge le date exif dal .json SE mancano
      echo "Questo aggiunge le date qualora mancassero nell'originale"
        exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/use_json.args ./
      #
      # File mp4 ma erroneamente salvati come .jpg
      echo "Verifichiamo gli mp4 salvati come jpg"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/jpg_to_mp4.args ./
      #
      # Rename .jpg files that are actually PNG files to have the .png extension
      echo "Verifichiamo gli png salvati come jpg"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/jpg_to_png.args ./
      #
      #Rename .jpg files that are actually PNG files to have the .png extension
      echo "Verifichiamo gli jpg salvati come png"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/png_to_jpg.args ./
      #
      # Se files sono stati cambiati, non avranno i metadati e quindi
      echo "Per i nuovi files mp4 preleva info dal .jpg.json"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/was_jpg_now_mp4.args ./
      echo "Per i nuovi files png preleva info dal .jpg.json"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/was_jpg_now_png.args ./
      echo "Per i nuovi files jpg preleva info dal .png.json"
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/was_png_now_jpg.args ./
      
    echo "Done.";;

  5)
    # aggiunge dati GPS
    #
    echo "Hai scelto GPS"
    echo "Verranno aggiunti i dati GPS qualora mancassero nell'originale"
    echo "Questo modifica la data e l'ora di creazione e modifica file"
    echo ""
      exiftool -@ $HOME/src/scripts/exiftool-scripts-for-takeout/use_json_for_gps.args ./
    echo "Done.";;

  9)
    # Settiamo le date con touch
    #
    echo "Hai scelto EXIF" 
    SetTimestampByExif ;;
  19)
    # Setta la data con nomefile
    #
    echo "Hai scelto NOMEFILE"
    SetTimestampWAbyFilename ;;
  21)
    # Spostiamo i files WA
    #
    echo "Hai scelto Sposta i files Whatsapp" 
    MoveWAfilesToFolder ;;
  97)
    # Pulizia TMP
    #
    echo "Hai scelto Pulizia tmp." 
    RemoveTMPfiles ;;
  99)
    # Pulizia JSON --- LAST
    #
    echo "Hai scelto Pulizia .JSON (crea files tmp)" 
    RemoveAllJson ;;
  *)
    echo "Bye"
    echo
    exit 0
  esac
done;
exit 0
