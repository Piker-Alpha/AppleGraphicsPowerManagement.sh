#!/bin/bash

#
# Script (AppleGraphicsPowerManagement.sh) to inject the AGPM dictionary from the AppleHDA support kext Info.plist
#
# Version 0.8 - Copyright (c) 2014 by Pike R. Alpha
#
# Updates:
#			- Variable 'gID' was missing (Pike R. Alpha, January 2014)
#			- Removed calls to sudo (Pike R. Alpha, January 2014)
#			- Variable 'gCallOpen' added (Pike R. Alpha, January 2014)
#			- Now lets you skip opening the Info.plist (Pike R. Alpha, January 2014)
#			- Use ALC of running system to update the filename (Pike R. Alpha, January 2014)
#
#
# Example with a MacPro6,1 board-id:
#
#                <key>AGPM</key>
#                <dict>
#                        <key>CFBundleIdentifier</key>
#                        <string>com.apple.driver.AGPM</string>
#                        <key>IOClass</key>
#                        <string>AGPMController</string>
#                        <key>IONameMatch</key>
#                        <string>AGPMEnabler</string>
#                        <key>IOProviderClass</key>
#                        <string>IOPlatformPluginDevice</string>
#                        <key>Machines</key>
#                        <dict>
#                                <key>Mac-F60DEB81FF30ACF6</key>
#                                <dict>
#                                        <key>IGPU</key>
#                                        <dict>
#                                                <key>Heuristic</key>
#                                                <dict>
#                                                        <key>EnableOverride</key>
#                                                        <integer>0</integer>
#                                                        <key>ID</key>
#                                                        <integer>2</integer>
#                                                </dict>
#                                                <key>control-id</key>
#                                                <integer>16</integer>
#                                        </dict>
#                                </dict>
#                        </dict>
#                </dict>

#================================= GLOBAL VARS ==================================

#
# Script version info.
#
gScriptVersion=0.8

#
# Setting the debug mode (default on).
#
let DEBUG=1

#
# Get user id
#
let gID=$(id -u)

#
# Change this to 0 if you don't want additional styling (bold/underlined).
#
let gExtraStyling=1

#
# Output styling.
#
STYLE_RESET="[0m"
STYLE_BOLD="[1m"
STYLE_UNDERLINED="[4m"

#
# Default ALC. Updated in function _getALC to match the codec of the running system.
#
gKextID="unknown"

#
# This is the name of the target kext, but without the extension (.kext)
#
# Note: Updated in function _checkTargetFile()
#
gKextName="AppleHDA${gKextID}"

#
# Change this path accordantly.
#
gTargetDirectory="/System/Library/Extensions"

#
# Initialise variable with Info.plist filename.
#
# Note: Updated in function _checkTargetFile()
#
gInfoPlist="${gTargetDirectory}/${gKextName}.kext/Contents/Info.plist"

#
# The initial board-id. Set later on in the script.
#
gBoardID="unknown"

#
# The first (delete) PlistBuddy command number.
#
let gCommandNumber=1

#
# A value of 1 will open Info.plist in the editor of your choice.
# A value of 2 will first ask for your confirmation before it opens the file.
#
let gCallOpen=2


#
#--------------------------------------------------------------------------------
#

function _showHeader()
{
  printf "AppleGraphicsPowerManagement.sh v${gScriptVersion} Copyright (c) $(date "+%Y") by Pike R. Alpha\n"
  echo -e '------------------------------------------------------------------------'
}

#
#--------------------------------------------------------------------------------
#

function _DEBUG_PRINT()
{
  #
  # Do we have to print debug log data?
  #
  if [[ $DEBUG -eq 1 ]];
    then
      #
      # Yes. Print the line.
      #
      printf "$1"
  fi
}


#
#--------------------------------------------------------------------------------
#

function _PRINT_ERROR()
{
  #
  # Fancy output style?
  #
  if [[ $gExtraStyling -eq 1 ]];
    then
      #
      # Yes. Use a somewhat nicer output style.
      #
      printf "${STYLE_BOLD}Error:${STYLE_RESET} $1"
    else
      #
      # No. Use the basic output style.
      #
      printf "Error: $1"
  fi
}


#
#--------------------------------------------------------------------------------
#
function _ABORT()
{
  #
  # Fancy output style?
  #
  if [[ $gExtraStyling -eq 1 ]];
    then
      #
      # Yes. Use a somewhat nicer output style.
      #
      printf "Aborting ...\n${STYLE_BOLD}Done.${STYLE_RESET}\n\n"
    else
      #
      # No. Use the basic output style.
      #
      printf "Aborting ...\nDone.\n\n"
  fi

  exit 1
}


#
#--------------------------------------------------------------------------------
#

function _getBoardID()
{
  #
  # Grab 'board-id' property from ioreg (stripped with sed / RegEX magic).
  #
  gBoardID=$(ioreg -p IODeviceTree -d 2 -k board-id | grep board-id | sed -e 's/ *["=<>]//g' -e 's/board-id//')
}


#
#--------------------------------------------------------------------------------
#

function _getALC()
{
  #
  # -r = Show subtrees rooted by objects that match the specified criteria (-p and -k)
  # -x = Show data and numbers as hexadecimal (see note below)
  # -p = Traverse the registry plane 'IOService'
  # -c = Show the object properties only if the object is an instance of 'AppleHDAController'
  # -k = Show the object properties only if the object has one with the name 'CodecList'
  #
  ioreg -rxp IOService -c AppleHDAController -k CodecList | grep CodecList | sed -e 's/.*VendorProductID"=//' -e 's/})$//' > /tmp/CodecList.txt
  #
  # cat /tmp/CodecList.txt returns on my rig:
  #
  # 0xffffffff80862807
  # 0x10ec0892
  #
  local codecList=$(cat /tmp/CodecList.txt)
  #
  # Loop through the list (should be at least two).
  #
  for codecID in ${codecList[@]}
  do
    #
    # Convert codeID into something that we can use.
    #
    # Note: 'getconf LONG_MAX' returns 9223372036854775807 (0x7FFFFFFFFFFFFFFF)
    #       and thus we cannot convert something like 0xffffffff80862807 without
    #       first stripping the 'ffffffff' off of it.
    #
    codecString=$(echo $codecID | sed -e 's/ffffffff//g')
    let codecDecimal=$codecString
    #
    # Check codec vendor-id/product-id
    #
    if (( $codecDecimal > 0x10ec0000  && $codecDecimal < 0x10ec0999));
      then
        #
        # Yes. Use it.
        #
        gKextID=$(echo "${codecString:6:4}" | sed 's/^0//')
        _DEBUG_PRINT "ALC ${gKextID} found\n\n"
      else
        #
        # No. Skip it (presumably some Intel HDAU device).
        #
        continue
    fi
  done
}


#
#--------------------------------------------------------------------------------
#

function _checkTargetFile()
{
  #
  # Codec found?
  #
  if [[ $gALC != "unknown" ]];
    then
      #
      # Yes. Re-init variables.
      #
      gKextName="AppleHDA${gKextID}"
      gInfoPlist="${gTargetDirectory}/${gKextName}.kext/Contents/Info.plist"
  fi
  #
  # The target file exists?
  #
  if [[ -e "$gInfoPlist" ]];
    then
      #
      # Yes. Return success status.
      #
      return
    else
      #
      # No. Abort.
      #
      _PRINT_ERROR "File Not Found! "
      _ABORT
  fi
}


#
#--------------------------------------------------------------------------------
#

function _doCommand()
{
  #
  # Print command number and command when DEBUG=1.
  #
  _DEBUG_PRINT "Command[%2d] ${1} " $gCommandNumber
  #
  # Run given command on target file.
  #
  /usr/libexec/PlistBuddy -c "${1}" "$gInfoPlist"
  #
  # Checking status; Failure?
  #
  if [[ $? -eq 1 ]];
    then
      #
      # Yes this is a failure, but is it our delete command?
      #
      if [[ $gCommandNumber -gt 1 ]];
        then
          #
          # No. This is not our delete command. Abort.
          #
          _PRINT_ERROR "Command failed ... "
          _ABORT
        else
          #
          # Yes. This is our delete command. Ignore failure.
          #
          continue
      fi
    else
      #
      # No error. Print newline character.
      #
      _DEBUG_PRINT "\n"
  fi
  #
  # Preparing for the next command (number).
  #
  let gCommandNumber++
}


#
#--------------------------------------------------------------------------------
#

function main()
{
  _showHeader
  _getBoardID
  _getALC
  _checkTargetFile
  #
  # Do we have a board-id?
  #
  if [[ $gBoardID == "unknown" ]];
    then
     #
     # No. Something went wrong. Bail out with error.
     #
      _PRINT_ERROR 'board-id NOT found!'
      _ABORT
    else
      #
      # Yes. Delete AGPM dictionary, in case it is already there.
      #
      # Note: I don't like this. We shouldn't replace everything. Especcialy
      #       without even asking for the users consent. Ergo. We want to add a
      #       confirmation (read -p) here.
      #
      _doCommand "Delete :IOKitPersonalities:AGPM dict"
      #
      # Add new entries.
      #
      _doCommand "Add :IOKitPersonalities:AGPM dict"
      _doCommand "Add :IOKitPersonalities:AGPM:CFBundleIdentifier string com.apple.driver.AGPM"
      _doCommand "Add :IOKitPersonalities:AGPM:IOClass string AGPMController"
      _doCommand "Add :IOKitPersonalities:AGPM:IONameMatch string AGPMEnabler"
      _doCommand "Add :IOKitPersonalities:AGPM:IOProviderClass string IOPlatformPluginDevice"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines dict"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID} dict"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID}:IGPU dict"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID}:IGPU:Heuristic dict"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID}:IGPU:Heuristic:EnableOverride integer 0"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID}:IGPU:Heuristic:ID integer 2"
      _doCommand "Add :IOKitPersonalities:AGPM:Machines:${gBoardID}:IGPU:control-id integer 16"
  fi
  #
  # Should we open the Info.plist?
  #
  if [[ $gCallOpen -eq 1 ]];
    then
      #
      # Yes. Open file.
      #
      open "$gInfoPlist"
    elif [[ $gCallOpen -eq 2 ]];
      #
      # Yes, but conditionally (asks for confirmation).
      #
      then
        echo ''
        read -p "Do you want to open the Info.plist? (y/n) " choice
        case "$choice" in
              y|Y ) _DEBUG_PRINT "Target file: ${gInfoPlist}\n"
                    open "${gInfoPlist}"
                    ;;
        esac
  fi
  #
  # Do we have to trigger a kernel cache refresh?
  #
  if [[ "$gInfoPlist" =~ "/System/Library/Extensions/" ]];
    then
      #
      # Yes. Touch the Extensions directory.
      #
      _DEBUG_PRINT "Triggering a kernelcache refresh ...\n\n"
      touch /System/Library/Extensions

      read -p "Do you want to reboot now? (y/n) " choice
      case "$choice" in
            y|Y ) reboot now
                  ;;
      esac
  fi
  #
  # Fancy output style?
  #
  if [[ $gExtraStyling -eq 1 ]];
    then
      #
      # Yes. Use a somewhat nicer output style.
      #
      printf "${STYLE_BOLD}Done.${STYLE_RESET}\n\n"
    else
      #
      # No. Use the basic output style.
      #
      printf "Done.\n\n"
  fi
}

#==================================== START =====================================

clear

if [[ $gID -ne 0 ]];
  then
    echo "This script ${STYLE_UNDERLINED}must${STYLE_RESET} be run as root!" 1>&2
    #
    # Re-run script with arguments.
    #
    sudo "$0" "$@"
  else
    #
    # We are root. Call main with arguments.
    #
    main "$@"
fi
