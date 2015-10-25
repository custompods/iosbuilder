#!/bin/bash
# Distributed under the MIT license
# Copyright (c) 2013 Nicolae Ghimbovschi

VERSION=2.0.4

PROJECT_PATH="$1"
APPSCHEME="$2"
ARTIFACTS_PATH="artifacts"
BUILDUSER_NAME="$(whoami)"
WORKPATH="$(pwd)"

export PATH=$PATH:/usr/local/bin

#==========================================================
#==== keychain settings
#==========================================================
XC_KEYCHAIN_PASSWORD=""
XC_KEYCHAIN_PATH="/Users/$BUILDUSER_NAME/Library/Keychains/iosbuilder.keychain"

#==========================================================
#==== xcodebuild settings
#==========================================================
#these are default values, the default values are overriden 
#after processEnvArguments function is called

#use xcodebuild if 1, otherwise use xctool
XC_USE_XCODEBUILD=1

#default build tool, xcodebuild or xctool
XC_BUILD_TOOL="xcodebuild"

#products and intermediate products location 
XC_BUILD_PATH="build"

#path to xcode project or workspace
XC_PROJECT_PATH=$PROJECT_PATH
XC_SCHEME=$APPSCHEME
XC_CONFIGURATION="Release"

#this is automatically populated
XC_BUILD_COMMAND=""

#extra xcodebuild and xctool args appended to the command line
XC_EXTRA_ARGS=""

#build sdk 6.1, 7, 8.1 ...
XC_SDK=""

#iphoneos or iphonesimulator
XC_SDK_TYPE="iphoneos"

#os version of the simulator, used for the destination parameter
XC_SIMOS_VER="latest"

#the name of the simulator device used for the destination parameter
XC_SIMDEVICE="iPhone 6"

#schemes with unit tests
XC_TEST_SCHEMES=""

#test scheme build configuration
XC_TEST_CONFIGURATION="Debug"

#test scheme build sdk type iphonesimulator or iphoneos
XC_TEST_SDK_TYPE="iphonesimulator"

#test scheme build extra args
#there are appended the xcodebuild or xctool
XC_TEST_EXTRA_ARGS=""

#by default tests are not run
XC_TEST_ENABLED=0

#do not build, just test
XC_SKIP_BUILD=0
XC_USE_COCOAPODS=0

#in cases when the productname.app file has
#a different name than the scheme
XC_USE_CUSTOMBUILDAPPNAME=0
XC_CUSTOMBUILDAPPNAME=""

XC_CODECOVERAGE_PREF="GCC_GENERATE_TEST_COVERAGE_FILES=YES GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=YES"
XC_JUNIT_REPORTS_PATH="$ARTIFACTS_PATH/test-reports"

#show the location where to store the build results
XC_DERIVEDDATA_PATH="-derivedDataPath $XC_BUILD_PATH"

#if we use xcodebuild and want nice logs, we need xcpretty
XC_COMPILE_REPORTER="| xcpretty --no-utf"

#-project or -workspace, automatically detected
XC_PROJECT_FORMAT_ARG="-project"

PROVISIONING_PROFILE_NAME=""

#==========================================================
#==== oclint and code coverage flags
#==========================================================
OCTOOL_CODE_ANALYSIS_ENABLED=0
CODE_COVERAGE_ANALYSIS=0
CODE_COVERAGE_HTML=0

#==========================================================
#==== app versioning
#==========================================================
PROJ_TECH_VERSION="1.0.0"
PROJ_MARK_VERSION="1.0"

SET_TECH_VERSION=0
SET_MARK_VERSION=0

#==========================================================
#==== required programs in path
#==========================================================
REQUIRED_PROGRAMS_IN_PATH=(
  "xcodebuild"
  "xctool"
  "agvtool"
  "gcovr"
  "ocunit2junit"
  "xcpretty"
  "oclint-json-compilation-database"
  "oclint-xcodebuild"
  "pod"
  )

#==========================================================
#==== print usage
#==========================================================
function usage() {
  echo "Usage: $0 path_to.xcodeproj|path_to.xcworkspace app_scheme_name"
  echo ""
  echo "Options:"
  echo "       -v shows version"
  exit 1
}

#==========================================================
#==== access control settings for simulator and pods
#==========================================================
LOCKFILE_SIMLATOR=fastlane_simulator.lock
LOCKFILE_PODS=fastlane_cocoapods.lock
LOCKFILE_MAXWAIT=30
LOCKFILE_LOOP_SLEEP=60
LOCKFILE_PODS_CREATED=0
LOCKFILE_SIMULATOR_CREATED=0

#==========================================================
#==== simulator and pods locking functions
#==========================================================
#all locks files are created in /var/tmp
function cleanUpLocks() {
  # remove locks on exist
  printf "\n\n[LOCKER Removing all lock files]\n"

  removePodsLock
  removeSimulatorLock
}

function removePodsLock() {

  if [ $LOCKFILE_PODS_CREATED == 1 ]
  then
    printf "\n\n[LOCKER Removing pods lock files]\n"
    rm -f "/tmp/$LOCKFILE_PODS" 
    LOCKFILE_PODS_CREATED=0
  fi
}

function removeSimulatorLock() {

  if [ $LOCKFILE_SIMULATOR_CREATED == 1 ]
  then
    printf "\n\n[LOCKER Removing simulator lock files]\n"
    rm -f "/tmp/$LOCKFILE_SIMLATOR"
    LOCKFILE_SIMULATOR_CREATED=0
  fi
}

function createLockFile() {
  LOOP_COUNTER=0

  printf "\n\n[LOCKER Waiting to lock file /tmp/$1]\n"

  echo "Removing stale lock files"
  find /var/tmp -name *.lock -type f -mmin +59 -delete

  while [ -f "/tmp/$1" ] ;
  do

    sleep $LOCKFILE_LOOP_SLEEP

    (( LOOP_COUNTER++ ))

    if [ $LOOP_COUNTER -gt $LOCKFILE_MAXWAIT ]
    then
      printf "[LOCKER Could not obtain lock on $1, exiting...]\n"
      exit 1
    fi

  done

  printf "[LOCKER Creating lock file $1]\n\n"
  # now we can create the lock file
  touch "/tmp/$1"

  if [ "$1" == "$LOCKFILE_PODS" ]
  then
    LOCKFILE_PODS_CREATED=1
  else
    LOCKFILE_SIMULATOR_CREATED=1
  fi
}

function matchProvisioningProfile() {
  PROFILE="$1"

  echo "$PROFILE" | grep "[0-9a-fA-F]\{8\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{4\}-[0-9a-fA-F]\{12\}"

  if [ "$?" != "0" ]
  then
    PROVISIONING_PROFILE_NAME="$PROFILE"
    PROVISIONING_PROFILE=$(find "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision -print0 | while read -d $'\0' file;\
     do  UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin <<< $(security cms -D -i "$file"));\
         NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin <<< $(security cms -D -i "$file"));\
      [ "$NAME" == "$PROFILE" ] && echo "$UUID" && break; done)
  else
    PROVISIONING_PROFILE="$PROFILE"
    PROVISIONING_PROFILE_NAME=$(find "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision -print0 | while read -d $'\0' file;\
     do  UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' /dev/stdin <<< $(security cms -D -i "$file"));\
         NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' /dev/stdin <<< $(security cms -D -i "$file"));\
      [ "$UUID" == "$PROFILE" ] && echo "$NAME" && break; done)
  fi
}


#==========================================================
#==== set default xcode app
#==========================================================
function setDefaultXcode() {

  case "$XC_SDK" in
    8.0|8.1|8.2|8.3|8.4)
      export DEVELOPER_DIR="/Applications/Xcode-6.4.app/Contents/Developer"
      ;;

    *)
      export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
      ;;
  esac
}

#==========================================================
#==== process the build settings passed through env variables
#==========================================================
function processEnvArguments() {

  if [[ -n "$USE_XCTOOL" ]] 
  then
    XC_USE_XCODEBUILD=0

    XC_BUILD_TOOL="xctool"
  fi

  if [[ -n "$VERBOSE" ]] 
  then
    #be very verbose
    XC_COMPILE_REPORTER=""
  fi

  if [[ -n "$SDK_VERSION" ]] 
  then
    XC_SDK=$SDK_VERSION
    #update used xcode version
    setDefaultXcode
  fi

  if [[ -n "$SDK_TYPE" ]] 
  then
    XC_SDK_TYPE=$SDK_TYPE
  fi

  if [[ -n "$CONFIGURATION" ]] 
  then
    XC_CONFIGURATION="$CONFIGURATION"
  fi

  #user intends to use a different keychain
  if [[ -n "$KEYCHAIN_PATH" ]] 
  then
    XC_KEYCHAIN_PATH="$KEYCHAIN_PATH"
  fi

  #make xcodebuild use the provided keychain
  export OTHER_CODE_SIGN_FLAGS="--keychain '$XC_KEYCHAIN_PATH'"
  

  if [[ -n "$KEYCHAIN_PASSWORD" ]] 
  then
    XC_KEYCHAIN_PASSWORD="$KEYCHAIN_PASSWORD"
  fi

  if [[ -n "$CODE_SIGN_IDENTITY" ]] 
  then
    XC_EXTRA_ARGS+=" CODE_SIGN_IDENTITY='$CODE_SIGN_IDENTITY' "
  fi

  if [[ -n "$PROVISIONING_PROFILE" ]] 
  then
      matchProvisioningProfile "$PROVISIONING_PROFILE"
    XC_EXTRA_ARGS+=" PROVISIONING_PROFILE='$PROVISIONING_PROFILE' "
  fi

  if [[ -n "$PREPROCESSOR_DEFINITIONS" ]] 
  then
    GCC_PREPROCESSOR_DEFINITIONS=$(printf '$(value) %s' $PREPROCESSOR_DEFINITIONS)
    XC_EXTRA_ARGS+=" GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS' "
  fi

  if [[ -n "$EXTRA_ARGS" ]] 
  then
    XC_EXTRA_ARGS+=" $EXTRA_ARGS "
  fi

  if [[ -n "$TECH_VERSION" ]] 
  then
    SET_TECH_VERSION=1
    PROJ_TECH_VERSION="$TECH_VERSION"
  fi

  if [[ -n "$MARK_VERSION" ]] 
  then
    SET_MARK_VERSION=1
    PROJ_MARK_VERSION="$MARK_VERSION"
  fi

  if [[ -n "$CODE_ANALYSIS_ENABLED" ]] 
  then
    OCTOOL_CODE_ANALYSIS_ENABLED=1
  fi

  if [[ -n "$CREATE_CODE_COVERAGE_REPORT" ]] 
  then
    CODE_COVERAGE_ANALYSIS=1
  else
    #reset code coverage preferences
    XC_CODECOVERAGE_PREF=""
  fi

  if [[ -n "$CREATE_CODE_COVERAGE_HTML_REPORT" ]] 
  then
    CODE_COVERAGE_HTML=1
  fi

  if [[ -n "$TEST_CONFIGURATION" ]] 
  then
    XC_TEST_CONFIGURATION="$TEST_CONFIGURATION"
  fi

  if [[ -n "$TEST_SDK_TYPE" ]] 
  then
    XC_TEST_SDK_TYPE=$TEST_SDK_TYPE
  fi

  if [[ -n "$TEST_CODE_SIGN_IDENTITY" ]] 
  then
    XC_TEST_EXTRA_ARGS+=" CODE_SIGN_IDENTITY='$TEST_CODE_SIGN_IDENTITY' "
  fi

  if [[ -n "$TEST_PROVISIONING_PROFILE" ]] 
  then
    TEST_PROVISIONING_PROFILE=$(matchProvisioningProfileNameToUDID "$TEST_PROVISIONING_PROFILE")
    XC_TEST_EXTRA_ARGS+=" PROVISIONING_PROFILE='$TEST_PROVISIONING_PROFILE' "
  fi

  if [[ -n "$TEST_PREPROCESSOR_DEFINITIONS" ]] 
  then
    GCC_PREPROCESSOR_DEFINITIONS=$(printf '$(value) %s' $TEST_PREPROCESSOR_DEFINITIONS)
    XC_TEST_EXTRA_ARGS+=" GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS' "
  fi

  if [[ -n "$TEST_EXTRA_ARGS" ]] 
  then
    XC_TEST_EXTRA_ARGS+=" $TEST_EXTRA_ARGS "
  fi

  if [[ -n "$TEST_SCHEMES" ]] 
  then
    XC_TEST_ENABLED=1
    XC_TEST_SCHEMES="$TEST_SCHEMES"
  fi

  if [[ -n "$TEST_SIMOSVER" ]] 
  then
    XC_SIMOS_VER=$TEST_SIMOSVER
  fi

  if [[ -n "$TEST_SIMDEVICE" ]] 
  then
    XC_SIMDEVICE=$TEST_SIMDEVICE
  fi

  if [[ -n "$SKIP_BUILD" ]] 
  then
    XC_SKIP_BUILD=1
    OCTOOL_CODE_ANALYSIS_ENABLED=0
  fi

  if [[ -n "$COCOAPODS_PROJECT" ]] 
  then
    XC_USE_COCOAPODS=1
  fi

  if [[ -n "$CUSTOM_IPA_NAME" ]]
  then
      XC_USE_CUSTOMBUILDAPPNAME=1
      XC_CUSTOMBUILDAPPNAME=$CUSTOM_IPA_NAME
  fi

  XC_BUILD_FILE_EXTENSION=${XC_PROJECT_PATH##*.}

  if [ "0$XC_BUILD_FILE_EXTENSION" == "0xcworkspace" ]
  then
    XC_PROJECT_FORMAT_ARG="-workspace"
  fi
}

#==========================================================
#==== make logs beautiful
#==========================================================
function printLog() {

  printf  "\n\n\n[ $1 ]\n\n"
}

#==========================================================
#==== execute string as command
#==========================================================
function run() {

  echo "Executing: $@"

  eval "$@ ; typeset -a a=(\${PIPESTATUS[@]})"

  return_value=$(($? + ${a[0]}))
  if [ $return_value != 0 ]
  then
    echo "Command $@ failed"
    exit -1
  fi
}

#==========================================================
#==== execute string as command
#==========================================================
function validateTools() {

  count=0
  while [ "x${REQUIRED_PROGRAMS_IN_PATH[$count]}" != "x" ]
  do
      program=${REQUIRED_PROGRAMS_IN_PATH[$count]}

    hash $program 2>/dev/null
    if [ $? -eq 1 ]; then
      echo >&2 "ERROR - $program is not installed or not in your PATH"; exit 1;
    fi

     count=$(( $count + 1 ))
  done


}

#==========================================================
#==== unlock the keychanin
#==========================================================
function unlockKeychain() {
  printLog "Unlocking keychain"

  if [ -f "$XC_KEYCHAIN_PATH" ]
  then
    security unlock-keychain -p "$XC_KEYCHAIN_PASSWORD" "$XC_KEYCHAIN_PATH" > /dev/null

    # disable keychain lock and timeout
    security set-keychain-settings "$XC_KEYCHAIN_PATH"
  else
    echo "Keychain '$XC_KEYCHAIN_PATH' is missing"
  fi
}

#==========================================================
#==== set technical and marketing
#==========================================================
function setVersion() {

  SAVEIFS=$IFS
  IFS=$(echo -en "\n\b")

  for xcodefileprojectpath in $(find . -type d -name "*.xcodeproj"  -not -path "./Pods/*" -not -path "./extralib/*")
  do

    PROJECTFILEPATH="`dirname  \"$xcodefileprojectpath\"`"
    cd "$PROJECTFILEPATH"

    if [ $SET_TECH_VERSION == 1 ] 
    then
        echo "Setting tech version in '$PROJECTFILEPATH'"
      run "agvtool new-version -all '$PROJ_TECH_VERSION' >> '$WORKPATH/$ARTIFACTS_PATH/agvtool.log'"
    fi

    if [ $SET_MARK_VERSION == 1 ] 
    then
      echo "Setting marketing version in '$PROJECTFILEPATH'"
      run "agvtool new-marketing-version '$PROJ_MARK_VERSION'  >> '$WORKPATH/$ARTIFACTS_PATH/agvtool.log'"
    fi

    cd "$WORKPATH"

  done

  cd "$WORKPATH"

  IFS=$SAVEIFS
}

#==========================================================
#==== set xcodebuild and xctool build arguments
#==========================================================
function setBuildArguments() {
  XC_BUILD_COMMAND="$XC_BUILD_TOOL $XC_PROJECT_FORMAT_ARG '$XC_PROJECT_PATH' -scheme '$XC_SCHEME' -configuration '$XC_CONFIGURATION' -sdk '${XC_SDK_TYPE}${XC_SDK}' archive"
  XC_BUILD_COMMAND+=" -archivePath '$ARTIFACTS_PATH/app'"
  XC_BUILD_COMMAND+=" $XC_DERIVEDDATA_PATH $XC_EXTRA_ARGS"

  if [ $XC_USE_XCODEBUILD == 1 ]
  then
    XC_BUILD_COMMAND+=" | tee '$ARTIFACTS_PATH/xcodebuild.log' $XC_COMPILE_REPORTER"
  else
    #add xctool arguments
    XC_BUILD_COMMAND+=" -reporter pretty"

    #if the CI tool is teamcity add the teamcity reporter
    if [[ -n "$CITOOL_TEAMCITY" ]]
    then
      XC_BUILD_COMMAND+=" -reporter teamcity"
    fi

    if [ $OCTOOL_CODE_ANALYSIS_ENABLED == 1 ]
    then
      XC_BUILD_COMMAND+=" -reporter json-compilation-database:compile_commands.json"
    fi
  fi
}

#==========================================================
#==== set xcodebuild and xctool test build arguments
#==========================================================
function setTestBuildArguments() {
  XC_BUILD_COMMAND="$XC_BUILD_TOOL $XC_PROJECT_FORMAT_ARG '$XC_PROJECT_PATH' -scheme '$XC_SCHEME' -configuration '$XC_TEST_CONFIGURATION' -sdk '${XC_TEST_SDK_TYPE}${XC_SDK}' build test"
  XC_BUILD_COMMAND+=" $XC_DERIVEDDATA_PATH $XC_CODECOVERAGE_PREF $XC_TEST_EXTRA_ARGS  -destination 'platform=iOS Simulator,OS=$XC_SIMOS_VER,name=$XC_SIMDEVICE' "

  if [ $XC_USE_XCODEBUILD == 1 ]
  then
    XC_BUILD_COMMAND+=" | tee '$ARTIFACTS_PATH/xcodebuild-tests-$XC_SCHEME.log' $XC_COMPILE_REPORTER"
  else 
    #add xctool arguments
    XC_BUILD_COMMAND+=" -reporter pretty -reporter \"junit:${XC_JUNIT_REPORTS_PATH}/${XC_SCHEME}.xml\""
  fi
}


#==========================================================
#==== generate oclint reports
#==========================================================
# Input:
#         $ARTIFACTS_PATH/xcodebuild.log        (only for xcodebuild, generated by runXCodeCommand)
#         $ARTIFACTS_PATH/compile_commands.json (only for xctool)
#
# artifacts:
#         $ARTIFACTS_PATH/oclint.xml
#         $ARTIFACTS_PATH/compile_commands.json (only for xcodebuild)
#
function reportCodeAnalysis {

  if [ $OCTOOL_CODE_ANALYSIS_ENABLED == 1 ]
  then
    printLog "Running static code analysis"

        if [ $XC_USE_XCODEBUILD == 1 ]
    then
      #when building with xcodebuild we need to generate compile_commands.json from compilation logs
      run "oclint-xcodebuild '$ARTIFACTS_PATH/xcodebuild.log'"
    fi

    oclint-json-compilation-database -v $OCLINT_EXCLUDED -- -report-type pmd -o "$ARTIFACTS_PATH/oclint.xml" $OCLINT_ARGS
    mv compile_commands.json "$ARTIFACTS_PATH/"

    echo "Code analysis done."
  fi

}

#==========================================================
#==== generate code coverage reports
#==========================================================
# Input:
#         build/* 
#
# artifacts:
#         $ARTIFACTS_PATH/coverage.xml
#         $ARTIFACTS_PATH/coverage-html
#
function reportCodeCoverage {

  if [ $CODE_COVERAGE_ANALYSIS == 1 ]
  then
    printLog "Creating code coverage report"

    run "gcovr -r . $CODECOVERAGE_EXCLUDES -x -o '$ARTIFACTS_PATH/coverage.xml'"

    if [ $CODE_COVERAGE_HTML == 1 ]
    then
      HTML_COVERAGE_PATH="$ARTIFACTS_PATH/coverage-html"
      mkdir -p "$HTML_COVERAGE_PATH"
      run "gcovr -r . $CODECOVERAGE_EXCLUDES --html --html-details -o '$HTML_COVERAGE_PATH/index.html'"
    fi

  fi

}

#==========================================================
#==== execute the generated xcodebuild or xctool arguments
#==========================================================
function runXCodeCommand() {

  run "$XC_BUILD_COMMAND"

}

#==========================================================
#==== execute the generated xcodebuild or xctool arguments
#==========================================================
# artifacts:
#     build/*                           (all compile results are put in the build folder)
#         $ARTIFACTS_PATH/xcodebuild.log        (only for xcodebuild, generated by runXCodeCommand)
#         $ARTIFACTS_PATH/compile_commands.json (only when xctool is used)
#
function buildProject() {

  if [ $XC_SKIP_BUILD == 0 ]
  then
    printLog "Building the project"

    setVersion
    setBuildArguments

    runXCodeCommand
  fi
}

#==========================================================
#==== runs tests from the listed in TEST_SCHEMES
#==========================================================
# Output:
#     build/*                                  (all compile results are put in the build folder)
#         $ARTIFACTS_PATH/xcodebuild-tests-<scheme_name>.log (only for xcodebuild, generated by runXCodeCommand)
#         $ARTIFACTS_PATH/compile_commands.json        (only when xctool is used)
#         $ARTIFACTS_PATH/test-reports/*.xml 
function testProject() {

  if [ $XC_TEST_ENABLED == 1 ]
  then 

    createLockFile $LOCKFILE_SIMLATOR
    closeSimulator

    OLDIFS=$IFS
    IFS=,

    set -- $XC_TEST_SCHEMES
    for testScheme
    do
      XC_SCHEME=`echo $testScheme | sed -e 's/^[ \t]*//'`

      IFS=$OLDIFS
      setTestBuildArguments

      printLog "Running tests: $testScheme"
      runXCodeCommand

      IFS=,

          if [ $XC_USE_XCODEBUILD == 1 ]
      then
        cat "$ARTIFACTS_PATH/xcodebuild-tests-$XC_SCHEME.log" | ocunit2junit > /dev/null
        mv test-reports/*.xml "$XC_JUNIT_REPORTS_PATH/"
      fi


    done

    IFS=$OLDIFS

    rm -fr test-reports
    
    closeSimulator
    cleanUpLocks

    reportCodeCoverage

  fi
}

#==========================================================
#==== create the IPA and the dSYM packages
#==========================================================
# Output:
#         $ARTIFACTS_PATH/<APPSCHEMNAME-APPVERSION>.ipa
#         $ARTIFACTS_PATH/<APPSCHEMNAME-APPVERSION>.dSYM.zip
function createPackage {

  if [ $XC_SKIP_BUILD == 0 ]
  then

    if [[ -n "$PACKAGE_AS_FRAMEWORK" ]] 
    then
      
      printLog "Creating Framework"

    else

      printLog "Creating IPA and dSYM"

      if [ $XC_USE_CUSTOMBUILDAPPNAME == 1 ]
      then
          APPSCHEME=$XC_CUSTOMBUILDAPPNAME
      fi

      IPA_PATH="$WORKPATH/$ARTIFACTS_PATH/$APPSCHEME-$PROJ_TECH_VERSION.ipa"

      SIGNING_IDENTITY="-exportWithOriginalSigningIdentity"
      if [[ X"$CODE_SIGN_IDENTITY" == X"" && X"$PROVISIONING_PROFILE_NAME" != X"" ]] 
      then
        SIGNING_IDENTITY="-exportProvisioningProfile '$PROVISIONING_PROFILE_NAME'"
      elif [[ X"$PROVISIONING_PROFILE_NAME" == X"" ]] 
      then
        SIGNING_IDENTITY="-exportSigningIdentity '$CODE_SIGN_IDENTITY'"
      fi

      run "xcodebuild -exportArchive -exportFormat ipa -archivePath '$WORKPATH/$ARTIFACTS_PATH/app.xcarchive' -exportPath '$IPA_PATH' $SIGNING_IDENTITY"

      if [ -d "$WORKPATH/$ARTIFACTS_PATH/app.xcarchive/SwiftSupport" ] 
      then
        printLog "Adding SwiftSupport"
        cd "$WORKPATH/$ARTIFACTS_PATH/app.xcarchive"
        run "zip -q -r -9 '$IPA_PATH' SwiftSupport/"
      fi

      if [ -d "$WORKPATH/$ARTIFACTS_PATH/app.xcarchive/WatchKitSupport" ] 
      then
        printLog "Adding WatchKitSupport"
        cd "$WORKPATH/$ARTIFACTS_PATH/app.xcarchive"
        run "zip -q -r -9 '$IPA_PATH' WatchKitSupport/"
      fi

      printLog "Compressing dSYM"
      cd "$WORKPATH/$ARTIFACTS_PATH/app.xcarchive/dSYMs/"
      run "zip -q -r -9 '$WORKPATH/$ARTIFACTS_PATH/$APPSCHEME-$PROJ_TECH_VERSION.dSYM.zip' *.dSYM"

      cd "$WORKPATH"
    fi
  fi

}

#==========================================================
#==== run cocoapods in a safe mode
#==========================================================

function resetPodsCache {
  pod cache clean --all
}

function runCocoaPods {

  if [ $XC_USE_COCOAPODS == 1 ]
  then

    # first time pods install may take a lot of time
    if [ -d "$HOME/.cocoapods" ]; then
      createLockFile $LOCKFILE_PODS
    fi

    #go to cocoapods path location
    if [[ -n "$COCOAPODS_PODPATH" ]] 
    then
      cd "$COCOAPODS_PODPATH"
    fi

    if [[ -n "$COCOAPODS_RESET_CACHE" ]] 
    then
      resetPodsCache
    fi

    pod install

    #comeback path location
    if [[ -n "$COCOAPODS_PODPATH" ]] 
    then
      cd "$WORKPATH"
    fi

    cleanUpLocks
  fi
}

function clean {
  rm -fr build
  rm -fr "$ARTIFACTS_PATH"
  rm -f compile_commands.json
}

function closeSimulator {
  #close the simulator
  osascript -e 'tell app "iOS Simulator" to quit'
}

export LANG=en_US.UTF-8

#==========================================================
#==== call cleanUpLocks on SIGHUP SIGINT SIGTERM EXIT 
#==========================================================
trap cleanUpLocks SIGHUP SIGINT SIGTERM EXIT


#==========================================================
#==== analyse the input arguments
#==========================================================
case "$1" in
  "-v")
      echo $VERSION
      exit 0
  ;;

  "unlockkeychain")
      unlockKeychain
      exit 0
  ;;
esac


if [ $# -lt 2 ] 
then
  usage
fi


clean

validateTools

mkdir -p "$XC_JUNIT_REPORTS_PATH"


processEnvArguments

runCocoaPods

unlockKeychain

buildProject

testProject

createPackage

reportCodeAnalysis
