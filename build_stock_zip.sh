#!/bin/bash
# required in path: simg2img, bbootimg, abootimg-pack-initrd, python3
# need to compile: gen_android_metadata
PKG_TEMPLATE="`dirname $0`/package_template"
CHECK_PROPS="ro.product.device ro.build.product"
SCRIPT_PATH="package/META-INF/com/google/android/updater-script"
MYOWNPATH=`dirname $0`

fail() {
    echo $1

    for img in $IMAGES; do
        umount mnt_images/$img >/dev/null 2>&1
        rmdir mnt_images/$img >/dev/null 2>&1
        rm -f $img-mod.img
    done
    rmdir mnt_images >/dev/null 2>&1

    rm -rf package

    exit 1
}

if [ $(whoami) != "root" ]; then
    echo "Run this script as root!"
    exit 1
fi

if [ "$#" -lt "1" ]; then
    echo "Usage $0 DEVICE [--userdata]"
    exit 1
fi

IMAGES="system"
UBUNTU_TOUCH=false
VENDOR_HACK=false
OUT_FILENAME=""
for arg in "$@"; do
    case $arg in
        grouper|tilapia)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/sdhci-tegra.3/by-name/LNX"
            SYS_DEV="/dev/block/platform/sdhci-tegra.3/by-name/APP"
            CHECK_NAMES="grouper tilapia"
            ;;
        flo|deb)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
            SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
            CHECK_NAMES="flo deb"
            ;;
        hammerhead|mako|shamu)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/msm_sdcc.1/by-name/boot"
            SYS_DEV="/dev/block/platform/msm_sdcc.1/by-name/system"
            CHECK_NAMES="$arg"
            ;;

        angler)
            DEVICE="$arg"
            BOOT_DEV="/dev/block/platform/soc.0/f9824900.sdhci/by-name/boot"
            SYS_DEV="/dev/block/platform/soc.0/f9824900.sdhci/by-name/system"
            CHECK_NAMES="$arg"
            VENDOR_HACK=true
            ;;

        --userdata)
            IMAGES="${IMAGES} userdata"
            ;;
        --utouch)
            UBUNTU_TOUCH=true
            ;;
        --out=*)
            OUT_FILENAME="${arg#--out=}"
            ;;
        *)
            echo "Unknown arg \"$arg\""
            exit 1
            ;;
    esac
done

if [ ! -f "boot.img" ]; then
    echo "boot.img not found!"
    exit 1
fi

echo "Creating package..."
rm -rf package >/dev/null 2>&1
mkdir -p package/rom
cp -a ${PKG_TEMPLATE}/* package/

if $VENDOR_HACK; then
    img="vendor"
    mkdir -p "mnt_images/$img"
    umount "mnt_images/$img" >/dev/null 2>&1
    if [ ! -f "$img-mod.img" ]; then
        if [ ! -f "$img.img" ]; then
            echo "$img.img was not found in this folder!"
            exit 1
        fi

        echo "Converting $img.img to normal image..."
        simg2img $img.img $img-mod.img
    fi
fi


for img in $IMAGES; do
    mkdir -p "mnt_images/$img"
    umount "mnt_images/$img" >/dev/null 2>&1

    if [ ! -f "$img-mod.img" ]; then
        if [ ! -f "$img.img" ]; then
            echo "$img.img was not found in this folder!"
            exit 1
        fi

        echo "Converting $img.img to normal image..."
        simg2img $img.img $img-mod.img
    fi

    mount -o loop -t ext4 $img-mod.img mnt_images/$img || fail "Mount failed!"
    if $VENDOR_HACK && [ $img = "system" ]; then
        rm -r mnt_images/$img/vendor
        mkdir mnt_images/$img/vendor
        chmod 755 mnt_images/$img/vendor
        mount -o loop -t ext4 vendor-mod.img mnt_images/$img/vendor || fail "Vendor mount failed"
    fi

    echo "Creating tar with $img files..."
    cd mnt_images/$img
    tar -c --numeric-owner ./* | pigz -c > ../../package/rom/$img.tar.gz
    cd ../..
done

modify_initrd() {
    if ! $VENDOR_HACK; then
        cp file_contexts ../../package/ || fail "Failed to copy file_contexts!"
    fi
    # Unused for systemless supersu?
    #sed -i 's/ seclabel u:r:install_recovery:s0/ #seclabel u:r:install_recovery:s0/' init.rc # for SuperSU

    fstab="fstab.${DEVICE}"
    if [ -f "$fstab" ]; then
        l="    $(grep 'forceencrypt=' "$fstab")"
        if [ "$?" = "0" ]; then
            echo "Replacing forceencrypt fstab flag with encryptable in $fstab, line:"
            echo "$l"
            sed -i 's/forceencrypt=/encryptable=/' "$fstab"
        fi

        l="    $(grep 'verify=' "$fstab")"
        if [ "$?" = "0" ]; then
            echo "Removing verify fstab from $fstab, line:"
            echo "$l"
            sed -i 's/,\?verify=[^,]*//' "$fstab"
        fi
        l="    $(grep '^/.*/vendor' "$fstab")"
        if $VENDOR_HACK && [ "$?" = "0" ]; then
            echo "Removing vendor partition from $fstab, line:"
            echo "$l"
            sed -i 's@^/.*/vendor .*$@@' "$fstab"
        fi
    else
        echo "File $fstab does not exist!"
    fi
    if $VENDOR_HACK && [ -d "vendor" ]; then
        echo "Removing vendor mountpoint in initrd"
        rm -r vendor
    fi
    if $VENDOR_HACK && [ -f "file_contexts.bin" ]; then
        echo "Injecting readable file_contexts to replace binary version"
        python3 $MYOWNPATH/sefcontext_decompile.py file_contexts.bin >new_file_contexts || fail "Failed to decompile file contexts!"
        sed -e "s@^/vendor/@/system/vendor/@" <new_file_contexts | sort | uniq >new_file_contexts_2
        mv new_file_contexts_2 new_file_contexts
        echo "
# MultiROM folders
/data/media/multirom(/.*)?          <<none>>
/data/media/0/multirom(/.*)?        <<none>>
/realdata/media/multirom(/.*)?      <<none>>
/realdata/media/0/multirom(/.*)?    <<none>>
/mnt/mrom(/.*)?                     <<none>>" >>new_file_contexts
        mv new_file_contexts file_contexts.bin
        chmod 644 file_contexts.bin
        cp file_contexts.bin ../../package/file_contexts || fail "Failed to copy file_contexts!"
    fi
}

process_bootimg() {
    echo "Processing boot.img..."
    rm -rf boot >/dev/null 2>&1
    mkdir boot
    cp boot.img boot/
    cd boot
    $MYOWNPATH/extract_bootimg.sh boot.img > /dev/null || fail "Failed to extract boot image!"
    cd init
    modify_initrd
    cd ..
    $MYOWNPATH/pack_bootimg.sh ../boot.img
    cd ..
    rm -r boot
}

process_initrd_image() {
    echo "Processing initrd.img"
    rm -rf init >/dev/null 2>&1
    mkdir init
    cd init
    zcat ../initrd.img | cpio -i
    cp file_contexts ../package/ || fail "Failed to copy file_contexts!"
    cd ..
    rm -r init
}

if $UBUNTU_TOUCH; then
    cp mnt_images/system/boot/android-ramdisk.img ./initrd.img
fi

if [ -f "initrd.img" ]; then
    process_initrd_image
else
    process_bootimg
fi

cp boot.img package/

echo "Creating script..."

assert_str="assert("
for dev in $CHECK_NAMES; do
    for prop in $CHECK_PROPS; do
        assert_str="${assert_str}getprop(\"$prop\") == \"$dev\" || "
    done
    assert_str="${assert_str}\n       "
done
assert_str="${assert_str% || \\n *});\n"
printf "$assert_str" > $SCRIPT_PATH

echo "format(\"ext4\", \"EMMC\", \"${SYS_DEV}\", \"0\", \"/system\");" >> $SCRIPT_PATH
echo "mount(\"ext4\", \"EMMC\", \"${SYS_DEV}\", \"/system\");" >> $SCRIPT_PATH

if [ -f "package/script_body_${DEVICE}" ]; then
    cat "package/script_body_${DEVICE}" >> $SCRIPT_PATH || fail "Failed to write script body!"
else
    cat "package/script_body" >> $SCRIPT_PATH || fail "Failed to write script body!"
fi
rm package/script_body*

echo 'ui_print("Extracting boot.img...");' >> $SCRIPT_PATH
echo "package_extract_file(\"boot.img\", \"${BOOT_DEV}\");" >> $SCRIPT_PATH

echo 'ui_print("Setting xattrs...");' >> $SCRIPT_PATH
cd mnt_images
# must be "gen_android_metadata system", always - it writes the path into updater-script!
$MYOWNPATH/gen_android_metadata system >> ../$SCRIPT_PATH || fail "Failed to generate metadata!"
cd ..

echo 'unmount("/system");' >> $SCRIPT_PATH
echo 'ui_print("Installation complete!");' >> $SCRIPT_PATH


echo "Packing into ZIP..."
if [ -z "$OUT_FILENAME" ]; then
    ver=$(basename $(pwd) | grep -o --color=never '\-.*');
    OUT_FILENAME="../${ver#-}_${DEVICE}.zip"
fi

rm "$OUT_FILENAME" >/dev/null 2>&1
cd package
zip -r0 "$OUT_FILENAME" ./* || fail "Failed to create ZIP file!"
cd ..

if $VENDOR_HACK; then
    umount mnt_images/$img/vendor
fi
for img in $IMAGES; do
    umount mnt_images/$img >/dev/null 2>&1
    rmdir mnt_images/$img >/dev/null 2>&1
    rm -f $img-mod.img
done

rmdir mnt_images >/dev/null 2>&1
rm -rf package

echo
echo "ZIP \"$OUT_FILENAME\" was successfuly created!"
