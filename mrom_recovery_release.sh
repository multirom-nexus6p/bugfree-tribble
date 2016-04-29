#!/bin/sh

if [ -z "$TARGET_DEVICE" ]; then
    TARGET_DEVICE=$(basename $OUT)
fi

TAG="$TARGET_DEVICE"

DEST_DIR="/home/nolenjohnson/Git/multirom/update-multirommgr-manifest/$TARGET_DEVICE/"
DEST_DIR_OTHER="/home/nolenjohnson/Git/multirom/update-multirommgr-manifest/$TARGET_DEVICE/"
if [ -z "$IMG_PATH" ]; then
    IMG_PATH="/home/nolenjohnson/omni/out/target/product/$TAG/recovery.img"
fi

if [ "$RECOVERY_SUBVER" = "" ]; then
    RECOVERY_SUBVER="STABLE6"
fi

if [ "$RECOVERY_SUBVER" != "00" ]; then
    DEST_NAME="mr-twrp-recovery-$(date +%m%d%Y)-$RECOVERY_SUBVER.img"
else
    DEST_NAME="mr-twrp-recovery-$(date +%m%d%Y).img"
fi

if [ -d "~/tmp/mrom_recovery_release" ]; then
    rm -r ~/tmp/mrom_recovery_release || exit 1
fi
mkdir ~/tmp/
mkdir ~/tmp/mrom_recovery_release/
cd ~/tmp/mrom_recovery_release/

cp -a $IMG_PATH ./

if [ -n "$TARGET_DEVICE" ]; then
    bbootimg -x ./$(basename "$IMG_PATH") >/dev/null 2>&1 || exit 1

    if lzma -S .img -t initrd.img >/dev/null 2>&1; then
        DCMPR="lzcat -d -S .img"
        CMPR="lzma"
    elif gzip -qt initrd.img >/dev/null 2>&1; then
        DCMPR="zcat"
        CMPR="gzip"
    else
        echo "Failed to identify ramdisk compression!"
        rm -r ~/tmp/mrom_recovery_release
        exit 1
    fi

    mkdir init
    cd init

    $DCMPR ../initrd.img | cpio -i >/dev/null 2>&1

    sed -i -e "s/ro.build.product=$TAG/ro.build.product=$TARGET_DEVICE/g" default.prop
    sed -i -e "s/ro.product.device=$TAG/ro.product.device=$TARGET DEVICE/g" default.prop

    find | sort | cpio --quiet -o -H newc | $CMPR > ../initrd.img
    cd ..

    DEST_NAME_OTHER="mr-twrp-recovery-$(date +%m%d%Y)"
    if [ "$RECOVERY_SUBVER" != "00" ]; then
        DEST_NAME_OTHER="${DEST_NAME_OTHER}-${RECOVERY_SUBVER}.img"
    else
        DEST_NAME_OTHER="${DEST_NAME_OTHER}.img"
    fi

    grep -v "bootsize" bootimg.cfg > bootimg-new.cfg
    bbootimg --create "$DEST_DIR_OTHER/$DEST_NAME_OTHER" -f bootimg-new.cfg -c "name = mrom$(date +%m%d%Y)-$RECOVERY_SUBVER" -k zImage -r initrd.img >/dev/null 2>&1 || exit 1
    if [ "$PRINT_FILES" = "true" ]; then
        printf "${DEST_DIR_OTHER}${DEST_NAME_OTHER} "
    else
        md5sum "$DEST_DIR_OTHER/$DEST_NAME_OTHER"
    fi
fi

bbootimg -u $(basename "$IMG_PATH") -c "name = mrom$(date +%m%d%Y)-$RECOVERY_SUBVER" >/dev/null 2>&1 || exit 1
cp ./$(basename "$IMG_PATH") "${DEST_DIR}/$DEST_NAME"

rm -r ~/tmp/mrom_recovery_release

if [ "$PRINT_FILES" = "true" ]; then
    printf "${DEST_DIR}${DEST_NAME}\n"
else
    md5sum "$DEST_DIR/$DEST_NAME"
fi
echo done
