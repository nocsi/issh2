#!/bin/sh

#  Automatic build script for libssh2
#  for iPhoneOS, iPhoneSimulator and MacCatalyst
#

# -u  Attempt to use undefined variable outputs error message, and forces an exit
set -u

# SCRIPT DEFAULTS

# Default version in case no version is specified
DEFAULTVERSION="1.9.0"

# Default (=full) set of architectures (libssh2 <= 1.9.0) or targets (libssh2>= 1.1.0) to build
DEFAULTTARGETS="ios-sim-cross-x86_64 ios-sim-cross-i386 ios64-cross-arm64 ios-cross-armv7s ios-cross-armv7 tvos-sim-cross-x86_64 tvos64-cross-arm64"  # mac-catalyst-x86_64 is a valid target that is not in the DEFAULTTARGETS because it's incompatible with "ios-sim-cross-x86_64"

# Minimum iOS/tvOS SDK version to build for
IOS_MIN_SDK_VERSION="14.0"
TVOS_MIN_SDK_VERSION="10.0"
MACOSX_MIN_SDK_VERSION="11.1"

# Init optional env variables (use available variable or default to empty string)
CURL_OPTIONS="${CURL_OPTIONS:-}"
CONFIG_OPTIONS="${CONFIG_OPTIONS:-}"

echo_help()
{
  echo "Usage: $0 [options...]"
  echo "Generic options"
  echo "     --cleanup                     Clean up build directories (bin, include/libssh2, lib, src) before starting build"
  echo " -h, --help                        Print help (this message)"
  echo "     --ios-sdk=SDKVERSION          Override iOS SDK version"
  echo "     --macosx-sdk=SDKVERSION       Override MacOSX SDK version"
  echo "     --noparallel                  Disable running make with parallel jobs (make -j)"
  echo "     --tvos-sdk=SDKVERSION         Override tvOS SDK version"
  echo "     --disable-bitcode             Disable embedding Bitcode"
  echo " -v, --verbose                     Enable verbose logging"
  echo "     --verbose-on-error            Dump last 500 lines from log file if an error occurs (for Travis builds)"
  echo "     --version=VERSION             libssh2 version to build (defaults to ${DEFAULTVERSION})"
  echo
  echo "Options for libSSH2 1.9.0 and higher ONLY"
  echo "     --targets=\"TARGET TARGET ...\" Space-separated list of build targets"
  echo "                                     Options: ${DEFAULTTARGETS} mac-catalyst-x86_64"
  echo
  echo "For custom configure options, set variable CONFIG_OPTIONS"
  echo "For custom cURL options, set variable CURL_OPTIONS"
  echo "  Example: CURL_OPTIONS=\"--proxy 192.168.1.1:8080\" ./build-libssl.sh"
}

spinner()
{
  local pid=$!
  local delay=0.75
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf "  [%c]" "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b"
  done

  wait $pid
  return $?
}

# Prepare target and source dir in build loop
prepare_target_source_dirs()
{
  OPENSSLDIR="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
  TARGETDIR="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
  mkdir -p "${TARGETDIR}"
  LOG="${TARGETDIR}/build-libssh2-${VERSION}.log"

  echo "Building libssh2-${VERSION} for ${PLATFORM} ${SDKVERSION} ${ARCH}..."
  echo "  Logfile: ${LOG}"

  # Prepare source dir
  SOURCEDIR="${CURRENTPATH}/src/${PLATFORM}-${ARCH}"
  mkdir -p "${SOURCEDIR}"
  tar zxf "${CURRENTPATH}/${LIBSSH_ARCHIVE_FILE_NAME}" -C "${SOURCEDIR}"
  cd "${SOURCEDIR}/${LIBSSH_ARCHIVE_BASE_NAME}"
  chmod u+x ./Configure
}

# Check for error status
check_status()
{
  local STATUS=$1
  local COMMAND=$2

  if [ "${STATUS}" != 0 ]; then
    if [[ "${LOG_VERBOSE}" != "verbose"* ]]; then
      echo "Problem during ${COMMAND} - Please check ${LOG}"
    fi

    # Dump last 500 lines from log file for verbose-on-error
    if [ "${LOG_VERBOSE}" == "verbose-on-error" ]; then
      echo "Problem during ${COMMAND} - Dumping last 500 lines from log file"
      echo
      tail -n 500 "${LOG}"
    fi

    exit 1
  fi
}

# Run Configure in build loop
run_configure()
{
  echo "  Configure..."
  set +e
  export CLANG=`xcrun --find clang`
  unset LDFLAGS
  unset EXTRA_CMAKE_ARGS
  unset PKG_CONFIG_PATH
  export CC="$CLANG"
  export CPP="$CLANG -E"
  #export CFLAGS="-arch $ARCH -pipe -no-cpp-precomp -isysroot $SDKROOT -mios-version-min=13.0 -fembed-bitcode"
  #export CPPFLAGS="-arch $ARCH -pipe -no-cpp-precomp -isysroot $SDKROOT -mios-version-min=13.0"
  echo $LOCAL_CONFIG_OPTIONS

  if [ "${LOG_VERBOSE}" == "verbose" ]; then
    ./Configure ${LOCAL_CONFIG_OPTIONS} | tee "${LOG}"
  else
    (./Configure ${LOCAL_CONFIG_OPTIONS} > "${LOG}" 2>&1) & spinner
  fi

  # Check for error status
  check_status $? "Configure"
}

# Run make in build loop
run_make()
{
  echo "  Make (using ${BUILD_THREADS} thread(s))..."

  if [ "${LOG_VERBOSE}" == "verbose" ]; then
    make -j "${BUILD_THREADS}" | tee -a "${LOG}"
  else
    (make -j "${BUILD_THREADS}" >> "${LOG}" 2>&1) & spinner
  fi

  # Check for error status
  check_status $? "make"
}

# Cleanup and bookkeeping at end of build loop
finish_build_loop()
{
  # Add references to library files to relevant arrays
  if [[ "${PLATFORM}" == AppleTV* ]]; then
    LIBSSH_TVOS+=("${TARGETDIR}/lib/libssh2.a")
    LIBSSHCONF_SUFFIX="tvos_${ARCH}"
  else
    LIBSSH_IOS+=("${TARGETDIR}/lib/libssh2.a")
    if [[ "${PLATFORM}" != MacOSX* ]]; then
      LIBSSHCONF_SUFFIX="ios_${ARCH}"
    else
      LIBSSHCONF_SUFFIX="catalyst_${ARCH}"
    fi
  fi

  # Copy libsshconf.h to bin directory and add to array
  #LIBSSHCONF="libsshconf_${LIBSSHCONF_SUFFIX}.h"
  #cp "${TARGETDIR}/include/libssh2/libsshconf.h" "${CURRENTPATH}/bin/${LIBSSHCONF}"
  #LIBSSHCONF_ALL+=("${LIBSSHCONF}")
  echo $SOURCEDIR
  rm -rf "${TARGETDIR}/include/libssh2"
  mkdir -p "${TARGETDIR}/include/libssh2"
  cp -RL "${SOURCEDIR}/${LIBSSH_ARCHIVE_BASE_NAME}/include/" "${TARGETDIR}/include/libssh2/"
  rm -f "${TARGETDIR}/include/*.h"

  # Keep reference to first build target for include file
  if [ -z "${INCLUDE_DIR}" ]; then
    INCLUDE_DIR="${TARGETDIR}/include/libssh2"
  fi

  # Return to ${CURRENTPATH} and remove source dir
  cd "${CURRENTPATH}"
  rm -r "${SOURCEDIR}"
}

# Init optional command line vars
ARCHS=""
CLEANUP=""
CONFIG_DISABLE_BITCODE=""
CONFIG_NO_DEPRECATED=""
IOS_SDKVERSION=""
MACOSX_SDKVERSION=""
LOG_VERBOSE=""
PARALLEL=""
TARGETS=""
TVOS_SDKVERSION=""
VERSION=""

# Process command line arguments
for i in "$@"
do
case $i in
  --archs=*)
    ARCHS="${i#*=}"
    shift
    ;;
  --cleanup)
    CLEANUP="true"
    ;;
  --deprecated)
    CONFIG_NO_DEPRECATED="false"
    ;;
  --disable-bitcode)
    CONFIG_DISABLE_BITCODE="true"
    ;;
  -h|--help)
    echo_help
    exit
    ;;
  --ios-sdk=*)
    IOS_SDKVERSION="${i#*=}"
    shift
    ;;
  --macosx-sdk=*)
    MACOSX_SDKVERSION="${i#*=}"
    shift
    ;;
  --noparallel)
    PARALLEL="false"
    ;;
  --targets=*)
    TARGETS="${i#*=}"
    shift
    ;;
  --tvos-sdk=*)
    TVOS_SDKVERSION="${i#*=}"
    shift
    ;;
  -v|--verbose)
    LOG_VERBOSE="verbose"
    ;;
  --verbose-on-error)
    LOG_VERBOSE="verbose-on-error"
    ;;
  --version=*)
    VERSION="${i#*=}"
    shift
    ;;
  *)
    echo "Unknown argument: ${i}"
    ;;
esac
done

# Specific version: Verify version number format. Expected: dot notation
if [[ -n "${VERSION}" && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Unknown version number format. Examples: 1.0.2, 1.0.2h"
  exit 1

# Script default
elif [ -z "${VERSION}" ]; then
  VERSION="${DEFAULTVERSION}"
fi

# Set default for TARGETS if not specified
if [ ! -n "${TARGETS}" ]; then
  TARGETS="${DEFAULTTARGETS}"
fi

# Determine SDK versions
if [ ! -n "${IOS_SDKVERSION}" ]; then
  IOS_SDKVERSION=$(xcrun -sdk iphoneos --show-sdk-version)
fi
if [ ! -n "${MACOSX_SDKVERSION}" ]; then
  MACOSX_SDKVERSION=$(xcrun -sdk macosx --show-sdk-version)
fi
if [ ! -n "${TVOS_SDKVERSION}" ]; then
  TVOS_SDKVERSION=$(xcrun -sdk appletvos --show-sdk-version)
fi

# Determine number of cores for (parallel) build
BUILD_THREADS=1
if [ "${PARALLEL}" != "false" ]; then
  BUILD_THREADS=$(sysctl hw.ncpu | awk '{print $2}')
fi

# Determine script directory
SCRIPTDIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)

# Write files relative to current location and validate directory
CURRENTPATH=$(pwd)
case "${CURRENTPATH}" in
  *\ * )
    echo "Your path contains whitespaces, which is not supported by 'make install'."
    exit 1
  ;;
esac
cd "${CURRENTPATH}"

# Validate Xcode Developer path
DEVELOPER=$(xcode-select -print-path)
if [ ! -d "${DEVELOPER}" ]; then
  echo "Xcode path is not set correctly ${DEVELOPER} does not exist"
  echo "run"
  echo "sudo xcode-select -switch <Xcode path>"
  echo "for default installation:"
  echo "sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

case "${DEVELOPER}" in
  *\ * )
    echo "Your Xcode path contains whitespaces, which is not supported."
    exit 1
  ;;
esac

# Show build options
echo
echo "Build options"
echo "  libssh2 version: ${VERSION}"
echo "  Targets: ${TARGETS}"
echo "  iOS SDK: ${IOS_SDKVERSION}"
echo "  tvOS SDK: ${TVOS_SDKVERSION}"
if [ "${CONFIG_DISABLE_BITCODE}" == "true" ]; then
  echo "  Bitcode embedding disabled"
fi
echo "  Number of make threads: ${BUILD_THREADS}"
if [ -n "${CONFIG_OPTIONS}" ]; then
  echo "  Configure options: ${CONFIG_OPTIONS}"
fi
echo "  Build location: ${CURRENTPATH}"
echo

# Download libssh2 when not present
LIBSSH_ARCHIVE_BASE_NAME="libssh2-${VERSION}"
LIBSSH_ARCHIVE_FILE_NAME="${LIBSSH_ARCHIVE_BASE_NAME}.tar.gz"
if [ ! -e ${LIBSSH_ARCHIVE_FILE_NAME} ]; then
  echo "Downloading ${LIBSSH_ARCHIVE_FILE_NAME}..."
  LIBSSH_ARCHIVE_URL="https://www.libssh2.org/download/${LIBSSH_ARCHIVE_FILE_NAME}"

  # Check whether file exists here (this is the location of the latest version for each branch)
  # -s be silent, -f return non-zero exit status on failure, -I get header (do not download)
  curl ${CURL_OPTIONS} -sfI "${LIBSSH_ARCHIVE_URL}" > /dev/null

  # Both attempts failed, so report the error
  if [ $? -ne 0 ]; then
    echo "An error occurred trying to find libssh2 ${VERSION} on ${LIBSSH2_ARCHIVE_URL}"
    echo "Please verify that the version you are trying to build exists, check cURL's error message and/or your network connection."
    exit 1
  fi

  # Archive was found, so proceed with download.
  # -O Use server-specified filename for download
  curl ${CURL_OPTIONS} -O "${LIBSSH_ARCHIVE_URL}"

else
  echo "Using ${LIBSSH_ARCHIVE_FILE_NAME}"
fi

# Set reference to custom configuration (libssh2 1.9.0)
export LIBSSH_LOCAL_CONFIG_DIR="${SCRIPTDIR}/config"

# -e  Abort script at first error, when a command exits with non-zero status (except in until or while loops, if-tests, list constructs)
# -o pipefail  Causes a pipeline to return the exit status of the last command in the pipe that returned a non-zero return value
set -eo pipefail

# Clean up target directories if requested and present
if [ "${CLEANUP}" == "true" ]; then
  if [ -d "${CURRENTPATH}/bin" ]; then
    rm -r "${CURRENTPATH}/bin"
  fi
  if [ -d "${CURRENTPATH}/include/libssh2" ]; then
    rm -r "${CURRENTPATH}/include/libssh2"
    rm -f "${CURRENTPATH}/include/*.h"
  fi
  if [ -d "${CURRENTPATH}/lib" ]; then
    rm -r "${CURRENTPATH}/lib"
  fi
  if [ -d "${CURRENTPATH}/src" ]; then
    rm -r "${CURRENTPATH}/src"
  fi
fi

# (Re-)create target directories
mkdir -p "${CURRENTPATH}/bin"
mkdir -p "${CURRENTPATH}/lib"
mkdir -p "${CURRENTPATH}/src"

# Init vars for library references
INCLUDE_DIR=""
LIBSSHCONF_ALL=()
LIBSSH_IOS=()
LIBSSH_TVOS=()

# Run relevant build loop (archs = 1.0 style, targets = 1.1 style)
source "${SCRIPTDIR}/scripts/build-loop-targets.sh"

#Build iOS library if selected for build
if [ ${#LIBSSH_IOS[@]} -gt 0 ]; then
  echo "Build library for iOS..."
  lipo -create ${LIBSSH_IOS[@]} -output "${CURRENTPATH}/lib/libssh2.a"
  echo "\n=====>iOS SSL and Crypto lib files:"
  echo "${CURRENTPATH}/lib/libssh2.a"
fi

# Build tvOS library if selected for build
if [ ${#LIBSSH_TVOS[@]} -gt 0 ]; then
  echo "Build library for tvOS..."
  lipo -create ${LIBSSH_TVOS[@]} -output "${CURRENTPATH}/lib/libssh2-tvOS.a"
  echo "\n=====>tvOS SSL and Crypto lib files:"
  echo "${CURRENTPATH}/lib/libssh2-tvOS.a"
fi

# Copy include directory
cp -R "${INCLUDE_DIR}" "${CURRENTPATH}/include"

echo "\n=====>Include directory:"
echo "${CURRENTPATH}/include/libssh2"

# Only create intermediate file when building for multiple targets
# For a single target, libsshconf.h is still present in $INCLUDE_DIR (and has just been copied to the target include dir)
if [ ${#LIBSSHCONF_ALL[@]} -gt 1 ]; then

  # Prepare intermediate header file
  # This overwrites libsshconf.h that was copied from $INCLUDE_DIR
  LIBSSHCONF_INTERMEDIATE="${CURRENTPATH}/include/libssh2/libsshconf.h"
  cp "${CURRENTPATH}/include/libsshconf-template.h" "${LIBSSHCONF_INTERMEDIATE}"

  # Loop all header files
  LOOPCOUNT=0
  for LIBSSHCONF_CURRENT in "${LIBSSHCONF_ALL[@]}" ; do

    # Copy specific libsshconf file to include dir
    cp "${CURRENTPATH}/bin/${LIBSSHCONF_CURRENT}" "${CURRENTPATH}/include/libssh2"

    # Determine define condition
    case "${LIBSSHCONF_CURRENT}" in
      *_ios_x86_64.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_SIMULATOR && TARGET_CPU_X86_64"
      ;;
      *_ios_i386.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_SIMULATOR && TARGET_CPU_X86"
      ;;
      *_ios_arm64.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM64"
      ;;
      *_ios_armv7s.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM && defined(__ARM_ARCH_7S__)"
      ;;
      *_ios_armv7.h)
        DEFINE_CONDITION="TARGET_OS_IOS && TARGET_OS_EMBEDDED && TARGET_CPU_ARM && !defined(__ARM_ARCH_7S__)"
      ;;
      *_catalyst_x86_64.h)
        DEFINE_CONDITION="(TARGET_OS_MACCATALYST || (TARGET_OS_IOS && TARGET_OS_SIMULATOR)) && TARGET_CPU_X86_64"
      ;;
      *_catalyst_arm64.h)
        DEFINE_CONDITION="(TARGET_OS_MACCATALYST || (TARGET_OS_IOS && TARGET_OS_SIMULATOR)) && TARGET_CPU_ARM64"
      ;;
      *_tvos_x86_64.h)
        DEFINE_CONDITION="TARGET_OS_TV && TARGET_OS_SIMULATOR && TARGET_CPU_X86_64"
      ;;
      *_tvos_arm64.h)
        DEFINE_CONDITION="TARGET_OS_TV && TARGET_OS_EMBEDDED && TARGET_CPU_ARM64"
      ;;
      *)
        # Don't run into unexpected cases by setting the default condition to false
        DEFINE_CONDITION="0"
      ;;
    esac

    # Determine loopcount; start with if and continue with elif
    LOOPCOUNT=$((LOOPCOUNT + 1))
    if [ ${LOOPCOUNT} -eq 1 ]; then
      echo "#if ${DEFINE_CONDITION}" >> "${LIBSSHCONF_INTERMEDIATE}"
    else
      echo "#elif ${DEFINE_CONDITION}" >> "${LIBSSHCONF_INTERMEDIATE}"
    fi

    # Add include
    echo "# include <libssh/${LIBSSHCONF_CURRENT}>" >> "${LIBSSHCONF_INTERMEDIATE}"
  done

  # Finish
  echo "#else" >> "${LIBSSHCONF_INTERMEDIATE}"
  echo '# error Unable to determine target or target not included in libssh2 build' >> "${LIBSSHCONF_INTERMEDIATE}"
  echo "#endif" >> "${LIBSSHCONF_INTERMEDIATE}"
fi

echo "Done."
