#!/usr/bin/env bash
set -eu -o pipefail

# Required packages: passwd protobuf java-1.8.0-openjdk-headless java-1.8.0-openjdk-devel gperf wget rsync tar unzip gnupg2 curl maven yasm npm ninja-build nodejs git clang lld llvm flex bison libdrm-devel nss-devel dbus-devel libstdc++-static libatomic-static krb5-devel glib2 glib2-devel glibc.i686 glibc-devel.i686 fakeroot-libs.i686 libgcc.i686 libtool-ltdl.i686 libtool-ltdl-devel.i686
# gn from OpenSUSE Tumbleweed.
# Assuming python2.

chrome_modern_target=chrome_modern_public_bundle
trichrome_chrome_bundle_target=trichrome_chrome_bundle
trichrome_chrome_apk_target=trichrome_library_apk
webview_target=system_webview_apk

chromium_version=86.0.4240.111
ungoogled_chromium_revision=1

# Show env
pwd
env
whoami
echo $PATH
echo $HOME

# Argument parser from https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash/29754866#29754866
# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=da:t:
LONGOPTS=debug,arch:,target:

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

ARCH=- TARGET=- DEBUG=n

# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        -d|--debug)
            DEBUG=y
            shift
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Programming error"
            exit 3
            ;;
    esac
done

if [[ "$ARCH" != "arm64" ]] && [[ "$ARCH" != "arm" ]] && [[ "$ARCH" != "x86" ]]; then
    echo "Wrong architecture"
    exit 4
fi

if [[ "$TARGET" != "$chrome_modern_target" ]] && [[ "$TARGET" != "$trichrome_chrome_bundle_target" ]] && [[ "$TARGET" != "$webview_target" ]] && [[ "$TARGET" != - ]]; then
    echo "Wrong target"
    exit 5
fi

echo "arch: $ARCH, target: $TARGET, debug: $DEBUG"

## Clone ungoogled-chromium repo
git clone https://github.com/Eloston/ungoogled-chromium.git -b ${chromium_version}-${ungoogled_chromium_revision}

## Clone chromium repo
git clone --depth 1 --no-tags https://chromium.googlesource.com/chromium/src.git -b ${chromium_version}

## Fetch depot-tools
depot_tools_commit=$(grep 'depot_tools.git' src/DEPS | cut -d\' -f8)
mkdir -p depot_tools
pushd depot_tools
git init
git remote add origin https://chromium.googlesource.com/chromium/tools/depot_tools.git
git fetch --depth 1 --no-tags origin "${depot_tools_commit}"
git reset --hard FETCH_HEAD
popd
OLD_PATH=$PATH
export PATH="$(pwd -P)/depot_tools:$PATH"
pushd src/third_party
ln -s ../../depot_tools
popd


## Sync files
# third_party/android_deps and some other overrides doesn't work
gclient.py sync --nohooks --no-history --shallow --revision=${chromium_version}


## Fix repos
webrtc_commit=$(grep 'webrtc_git.*/src\.git' src/DEPS | cut -d\' -f8)
mkdir src/third_party/webrtc
pushd src/third_party/webrtc
git init
git remote add origin https://webrtc.googlesource.com/src.git
git fetch --depth 1 --no-tags origin "${webrtc_commit}"
git reset --hard FETCH_HEAD
popd

libsync_commit=$(grep 'libsync\.git' src/DEPS | cut -d\' -f10)
mkdir src/third_party/libsync/src
pushd src/third_party/libsync/src
git init
git remote add origin https://chromium.googlesource.com/aosp/platform/system/core/libsync.git
git fetch --depth 1 --no-tags origin "${libsync_commit}"
git reset --hard FETCH_HEAD
popd

fontconfig_commit=$(grep 'fontconfig\.git' src/DEPS | cut -d\' -f10)
mkdir src/third_party/fontconfig/src
pushd src/third_party/fontconfig/src
git init
git remote add origin https://chromium.googlesource.com/external/fontconfig.git
git fetch --depth 1 --no-tags origin "${fontconfig_commit}"
git reset --hard FETCH_HEAD
popd

# New binary dependency: node
mkdir -p src/third_party/node/linux/node-linux-x64/bin
ln -s /usr/bin/node src/third_party/node/linux/node-linux-x64/bin/
src/third_party/node/update_npm_deps
# Remove bundled jdk
pushd src && patch -p1 --ignore-whitespace -i ../patches/Other/remove-jdk.patch --no-backup-if-mismatch && popd
rm -rf src/third_party/jdk
mkdir -p src/third_party/jdk/current/bin
ln -s /usr/bin/java src/third_party/jdk/current/bin/
ln -s /usr/bin/javac src/third_party/jdk/current/bin/
ln -s /usr/bin/javap src/third_party/jdk/current/bin/
# jre
mkdir -p src/third_party/jdk/extras/java_8 && pushd src/third_party/jdk/extras/java_8
ln -s /usr/lib/jvm/jre-1.8.0 jre
popd

# Link to system clang tools
pushd src/buildtools/linux64
ln -s /usr/bin/clang-format
popd

## Hooks
python src/build/util/lastchange.py -o src/build/util/LASTCHANGE
python src/tools/download_optimization_profile.py --newest_state=src/chrome/android/profiles/newest.txt --local_state=src/chrome/android/profiles/local.txt --output_name=src/chrome/android/profiles/afdo.prof --gs_url_base=chromeos-prebuilt/afdo-job/llvm
python src/build/util/lastchange.py -m GPU_LISTS_VERSION --revision-id-only --header src/gpu/config/gpu_lists_version.h
python src/build/util/lastchange.py -m SKIA_COMMIT_HASH -s src/third_party/skia --header src/skia/ext/skia_commit_hash.h


## Run ungoogled-chromium scripts
# Patch prune list and domain substitution
# TODO some pruned binaries are excluded since they will cause android build to fail
patch -p1 --ignore-whitespace -i patches/Other/ungoogled-main-repo-fix.patch --no-backup-if-mismatch
# Remove the cache file if exists
cache_file="domsubcache.tar.gz"
if [[ -f ${cache_file} ]] ; then
    rm ${cache_file}
fi

# Ignore the pruning error
python3 ungoogled-chromium/utils/prune_binaries.py src ungoogled-chromium/pruning.list || true
python3 ungoogled-chromium/utils/patches.py apply src ungoogled-chromium/patches
python3 ungoogled-chromium/utils/domain_substitution.py apply -r ungoogled-chromium/domain_regex.list -f ungoogled-chromium/domain_substitution.list -c ${cache_file} src


# Workaround for a building failure caused by safe browsing. The file is pre-generated with safe_browsing_mode=2. See https://github.com/nikolowry/bromite-builder/issues/1
cp safe_browsing_proto_files/download_file_types.pb.h src/chrome/common/safe_browsing/download_file_types.pb.h
cp safe_browsing_proto_files/webprotect.pb.h src/components/safe_browsing/core/proto/webprotect.pb.h


## Prepare Android SDK/NDK
SDK_DIR="android-sdk_eng.10.0.0_r14_linux-x86"

# Create symbol links to sdk folders
# The rebuild sdk has a different folder structure from the checked out version, so it is easier to create symbol links
DIRECTORY="src/third_party/android_sdk/public"
if [[ -d "$DIRECTORY" ]]; then
  find $DIRECTORY -mindepth 1 -maxdepth 1 -not -name cmdline-tools -exec rm -rf '{}' \;
fi
pushd ${DIRECTORY}
mkdir build-tools && ln -s ../../../../../android-sdk/${SDK_DIR}/build-tools/android-10 build-tools/30.0.1
mkdir platforms
ln -s ../../../../../android-sdk/${SDK_DIR}/platforms/android-10 platforms/android-30
ln -s ../../../../android-sdk/${SDK_DIR}/platform-tools platform-tools
ln -s ../../../../android-sdk/${SDK_DIR}/tools tools
popd

# remove ndk folders
DIRECTORY="src/third_party/android_ndk"
gn_file="BUILD.gn"
mkdir "ndk_temp"
cp -a "${DIRECTORY}/${gn_file}" ndk_temp
cp -ar "${DIRECTORY}/toolchains/llvm/prebuilt/linux-x86_64" ndk_temp    # Need libgcc.a otherwise compilation will fail
pushd "${DIRECTORY}"
cd ..
rm -rf android_ndk
ln -s ../../android-ndk/android-ndk-r20b android_ndk
popd

# This is Sylvain Beucler's libre Android rebuild
sdk_link="https://android-rebuilds.beuc.net/dl/bundles/android-sdk_eng.10.0.0_r14_linux-x86.zip"
sdk_tools_link="https://android-rebuilds.beuc.net/dl/repository/sdk-repo-linux-tools-26.1.1.zip"
ndk_link="https://android-rebuilds.beuc.net/dl/repository/android-ndk-r20b-linux-x86_64.tar.bz2"

mkdir android-rebuilds
mkdir android-sdk
mkdir android-ndk
pushd android-rebuilds
for i in $(seq 1 5); do curl -O ${sdk_link} && unzip -qqo android-sdk_eng.10.0.0_r14_linux-x86.zip -d ../android-sdk && rm -f android-sdk_eng.10.0.0_r14_linux-x86.zip && s=0 && break || s=$? && sleep 15; done; (exit $s)
for i in $(seq 1 5); do curl -O ${sdk_tools_link} && unzip -qqo sdk-repo-linux-tools-26.1.1.zip -d ../android-sdk/android-sdk_eng.10.0.0_r14_linux-x86 && rm -f sdk-repo-linux-tools-26.1.1.zip && s=0 && break || s=$? && sleep 15; done; (exit $s)
for i in $(seq 1 5); do curl -O ${ndk_link} && tar xjf android-ndk-r20b-linux-x86_64.tar.bz2 -C ../android-ndk && rm -f android-ndk-r20b-linux-x86_64.tar.bz2 && s=0 && break || s=$? && sleep 15; done; (exit $s)
popd

# Move ndk files into place
cp -a "ndk_temp/${gn_file}" android-ndk/android-ndk-r20b
cp -ar "ndk_temp/linux-x86_64" android-ndk/android-ndk-r20b/toolchains/llvm/prebuilt
rm -rf "ndk_temp"


## Compile third-party binaries
# eu-strip is re-compiled with -Wno-error
patch -p1 --ignore-whitespace -i patches/Other/eu-strip-build-script.patch --no-backup-if-mismatch
pushd src/buildtools/third_party/eu-strip
./build.sh
popd
# Some of the support libraries can be grabbed from maven https://android.googlesource.com/platform/prebuilts/maven_repo/android/+/master/com/android/support/

# chromium-web-store, extension version only
# git clone https://github.com/NeverDecaf/chromium-web-store
# cp -ar chromium-web-store/en_nolocale src/chrome/browser/resources/chromium_web_store

# Additional Source Patches
## Extra fixes for Chromium source
python3 ungoogled-chromium/utils/patches.py apply src patches
## Second pruning list
pruning_list_2="pruning_2.list"
python3 ungoogled-chromium/utils/prune_binaries.py src ${pruning_list_2} || true
## Second domain substitution list
substitution_list_2="domain_sub_2.list"
# Remove the cache file if exists
cache_file="domsubcache.tar.gz"
if [[ -f ${cache_file} ]] ; then
    rm ${cache_file}
fi
python3 ungoogled-chromium/utils/domain_substitution.py apply -r ungoogled-chromium/domain_regex.list -f ${substitution_list_2} -c ${cache_file} src


## Configure output folder
export PATH=$OLD_PATH  # remove depot_tools from PATH
pushd src
output_folder="out/Default"
mkdir -p "${output_folder}"
if [ "$DEBUG" = n ] ; then
    cat ../ungoogled-chromium/flags.gn ../android_flags.gn ../android_flags.release.gn > "${output_folder}"/args.gn
    cat ../../uc_keystore/keystore.gn >> "${output_folder}"/args.gn
else
    cat ../android_flags.gn ../android_flags.debug.gn > "${output_folder}"/args.gn
fi
printf '\ntarget_cpu="'"$ARCH"'"\n' >> "${output_folder}"/args.gn
gn gen "${output_folder}" --fail-on-unused-args
popd


## Set compiler flags
export AR=${AR:=llvm-ar}
export NM=${NM:=llvm-nm}
export CC=${CC:=clang}
export CXX=${CXX:=clang++}

## Build
apk_out_folder="apk_out"
mkdir "${apk_out_folder}"
pushd src
if [[ "$TARGET" != - ]]; then
  ninja -C "${output_folder}" $TARGET
  if [[ "$TARGET" == "$trichrome_chrome_bundle_target" ]]; then
    ninja -C "${output_folder}" "$trichrome_chrome_apk_target"
  fi
  ../bundle_generate_apk.sh -o "${output_folder}" -t $TARGET
  find . -iname "*.apk" -exec cp {} ../"${apk_out_folder}" \;
else
  ninja -C out/Default $chrome_modern_target
  ../bundle_generate_apk.sh -o "${output_folder}" -t $chrome_modern_target
  ninja -C out/Default $webview_target

  # arm64 needs to clean before build trichrome otherwise will fail
  if [[ "$ARCH" == "arm64" ]]; then
    find . -iname "*.apk" -exec cp {} ../"${apk_out_folder}" \;
    ninja -C "${output_folder}" -t clean
  fi

  ninja -C "${output_folder}" "$trichrome_chrome_bundle_target"
  ninja -C "${output_folder}" "$trichrome_chrome_apk_target"

  find . -iname "*.apk" -exec cp {} ../"${apk_out_folder}" \;
fi
popd
