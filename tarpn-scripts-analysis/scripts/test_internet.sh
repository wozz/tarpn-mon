#!/bin/bash
#### This script is copyright Tadd Torborg KA2DEW 2014-2025
##### Please leave this copyright notice in the document and if changes are made,
##### indicate at the copyright notice as to what the intent of the changes was.
##### Thanks. - Tadd Raleigh NC

###### Test to see if we can download files  Returns 0 if good, 1 if error.
#### Note: This may be run as root or as user pi.
getTestFile() {
  ### Verify that we have delete/write/read access to our temp file space
INTERNET_TESTFILE="testfile.txt"
GTF_COMMAND_LOG="/var/log/tarpn_command.log"
  echo "##### test_internet.sh: getTestFile()"
  cd /tmp/tarpn
  sudo rm -f testAccess.tmp
  if [ -f testAccess.tmp ];
  then
     echo "ERROR2: FAIL -  /tmp/tarpn/testAccess.tmp cannot be deleted"
     echo -ne $(date) "" >> $GTF_COMMAND_LOG
     echo " getTestFile() - ERROR2: unable to delete /tmp/tarpn/testAccess.tmp. -- FAIL" >> $GTF_COMMAND_LOG
     return 1
  fi

  date > testAccess.tmp
  if [ -f testAccess.tmp ];
  then
     echo -n
  else
     echo "ERROR3: unable to write to /tmp/tarpn/testAccess.tmp."
     echo -ne $(date) "" >> $GTF_COMMAND_LOG
     echo " getTestFile() - ERROR3: unable to write to /tmp/tarpn/testAccess.tmp. -- FAIL" >> $GTF_COMMAND_LOG
     return 1
  fi
  rm -f testAccess.tmp


  ### Establish the source-url to point at the appropriate TARPN url
  if [ -f /usr/local/sbin/source_url.txt ];
  then
      echo -n
  else
     echo "ERROR4: source URL file not found."
     echo -ne $(date) "" >> $GTF_COMMAND_LOG
     echo " getTestFile() - ERROR4 == no source-url file -- FAIL" >> $GTF_COMMAND_LOG
     return 1
  fi

  rm -f $INTERNET_TESTFILE*
  _source_url=$(tr -d '\0' </usr/local/sbin/source_url.txt);
  wget -o /dev/null $_source_url/$INTERNET_TESTFILE
  if [ -f testfile.txt ];
  then
      echo -n
  else
     echo "ERROR5: unable to download testfile into tmp/tarpn directory."
     echo -ne $(date) "" >> $GTF_COMMAND_LOG
     echo " getTestFile() - ERROR5 == unable to download testfile into tmp/tarpn directory -- FAIL" >> $GTF_COMMAND_LOG
     rm -f $INTERNET_TESTFILE*
     return 1
  fi

  if grep -q "test data  is on this line" $INTERNET_TESTFILE; then
     echo -n
  else
     echo "ERROR6: $INTERNET_TESTFILE downloaded from Internet had bad contents."
     echo -ne $(date) "" >> $GTF_COMMAND_LOG
     echo " getTestFile() - ERROR6 == $INTERNET_TESTFILE downloaded from Internet had bad contents-- FAIL" >> $GTF_COMMAND_LOG
     rm -f $INTERNET_TESTFILE*
     return 1

  fi
  rm -f $INTERNET_TESTFILE*
  return 0
}


