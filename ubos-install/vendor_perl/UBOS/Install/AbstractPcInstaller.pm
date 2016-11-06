# 
# Abstract superclass for PC installers.
# 
# This file is part of ubos-install.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-install is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-install is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-install.  If not, see <http://www.gnu.org/licenses/>.
#

# Device-specific notes:
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::AbstractPcInstaller;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;

##
# Install the grub bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $diskLayout: the disk layout
# $kernelPostfix: allows us to add -ec2 to EC2 kernels
# return: number of errors
sub installGrub {
    my $self             = shift;
    my $pacmanConfigFile = shift;
    my $diskLayout       = shift;
    my $kernelPostfix    = shift || '';

    info( 'Installing grub boot loader' );

    my $errors = 0;
    my $target = $self->{target};

    my $bootLoaderDevice = $diskLayout->determineBootLoaderDevice();

    # Ramdisk
    debug( "Generating ramdisk" );

    # The optimized ramdisk doesn't always boot, so we always skip the optimization step
    UBOS::Utils::saveFile( "$target/etc/mkinitcpio.d/linux$kernelPostfix.preset", <<END, 0644, 'root', 'root' );
# mkinitcpio preset file for the 'linux' package, modified for UBOS
#
# Do not autodetect, as the device booting the image is most likely different
# from the device that created the image

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux$kernelPostfix"

PRESETS=('default')
BINARIES="/usr/bin/btrfsck"
MODULES=('btrfs')

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux$kernelPostfix.img"
default_options="-S autodetect"
END

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "chroot '$target' mkinitcpio -p linux$kernelPostfix", undef, \$out, \$err ) ) {
        error( "Generating ramdisk failed:", $err );
        ++$errors;
    }

    # Boot loader
    if( $bootLoaderDevice ) {

# HACKING SOME DEBUG CODE IN
my $newTenLinux    = <<'INSERT';
# Temporary debug code

prefix="/usr"
exec_prefix="/usr"
datarootdir="/usr/share"

. "$pkgdatadir/grub-mkconfig_lib"

export TEXTDOMAIN=grub
export TEXTDOMAINDIR="${datarootdir}/locale"

CLASS="--class gnu-linux --class gnu --class os"

if [ "x${GRUB_DISTRIBUTOR}" = "x" ] ; then
  OS=Linux
else
  OS="${GRUB_DISTRIBUTOR} Linux"
  CLASS="--class $(echo ${GRUB_DISTRIBUTOR} | tr 'A-Z' 'a-z' | cut -d' ' -f1|LC_ALL=C sed 's,[^[:alnum:]_],_,g') ${CLASS}"
fi

echo '# *** GRUB_DEVICE before     ' ${GRUB_DEVICE}

# loop-AES arranges things so that /dev/loop/X can be our root device, but
# the initrds that Linux uses don't like that.
case ${GRUB_DEVICE} in
  /dev/loop/*|/dev/loop[0-9])
    GRUB_DEVICE=`losetup ${GRUB_DEVICE} | sed -e "s/^[^(]*(\([^)]\+\)).*/\1/"`
  ;;
esac

echo '# *** GRUB_DEVICE            ' ${GRUB_DEVICE}
echo '# *** GRUB_DEVICE_UUID       ' ${GRUB_DEVICE_UUID}
echo '# *** GRUB_DISABLE_LINUX_UUID' ${GRUB_DISABLE_LINUX_UUID}
if test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}"; then
    echo '# *** by-uuid exists'
fi
if test -e "${GRUB_DEVICE}"; then
    echo '# *** grub-device exists'
fi
if uses_abstraction "${GRUB_DEVICE}" lvm; then
    echo '# *** uses_abstraction'
fi

ls -al /dev/disk/by-uuid | while read line; do echo "## /dev/disk/by-uuid $line"; done

# btrfs may reside on multiple devices. We cannot pass them as value of root= parameter
# and mounting btrfs requires user space scanning, so force UUID in this case.
if [ "x${GRUB_DEVICE_UUID}" = "x" ] || [ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ] \
    || ! test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}" \
    || ( test -e "${GRUB_DEVICE}" && uses_abstraction "${GRUB_DEVICE}" lvm ); then
  LINUX_ROOT_DEVICE=${GRUB_DEVICE}
else
  LINUX_ROOT_DEVICE=UUID=${GRUB_DEVICE_UUID}
fi
echo '# ** LINUX_ROOT_DEVICE ' ${LINUX_ROOT_DEVICE}

case x"$GRUB_FS" in
    xbtrfs)
        rootsubvol="`make_system_path_relative_to_its_root /`"
        rootsubvol="${rootsubvol#/}"
        if [ "x${rootsubvol}" != x ]; then
            GRUB_CMDLINE_LINUX="rootflags=subvol=${rootsubvol} ${GRUB_CMDLINE_LINUX}"
        fi;;
    xzfs)
        rpool=`${grub_probe} --device ${GRUB_DEVICE} --target=fs_label 2>/dev/null || true`
        bootfs="`make_system_path_relative_to_its_root / | sed -e "s,@$,,"`"
        LINUX_ROOT_DEVICE="ZFS=${rpool}${bootfs}"
        ;;
esac

title_correction_code=

linux_entry ()
{
  os="$1"
  version="$2"
  type="$3"
  args="$4"

  if [ -z "$boot_device_id" ]; then
      boot_device_id="$(grub_get_device_id "${GRUB_DEVICE}")"
  fi
  if [ x$type != xsimple ] ; then
      case $type in
          recovery)
              title="$(gettext_printf "%s, with Linux %s (recovery mode)" "${os}" "${version}")" ;;
          fallback)
              title="$(gettext_printf "%s, with Linux %s (fallback initramfs)" "${os}" "${version}")" ;;
          *)
              title="$(gettext_printf "%s, with Linux %s" "${os}" "${version}")" ;;
      esac
      if [ x"$title" = x"$GRUB_ACTUAL_DEFAULT" ] || [ x"Previous Linux versions>$title" = x"$GRUB_ACTUAL_DEFAULT" ]; then
          replacement_title="$(echo "Advanced options for ${OS}" | sed 's,>,>>,g')>$(echo "$title" | sed 's,>,>>,g')"
          quoted="$(echo "$GRUB_ACTUAL_DEFAULT" | grub_quote)"
          title_correction_code="${title_correction_code}if [ \"x\$default\" = '$quoted' ]; then default='$(echo "$replacement_title" | grub_quote)'; fi;"
          grub_warn "$(gettext_printf "Please don't use old title \`%s' for GRUB_DEFAULT, use \`%s' (for versions before 2.00) or \`%s' (for 2.00 or later)" "$GRUB_ACTUAL_DEFAULT" "$replacement_title" "gnulinux-advanced-$boot_device_id>gnulinux-$version-$type-$boot_device_id")"
      fi
      echo "menuentry '$(echo "$title" | grub_quote)' ${CLASS} \$menuentry_id_option 'gnulinux-$version-$type-$boot_device_id' {" | sed "s/^/$submenu_indentation/"
  else
      echo "menuentry '$(echo "$os" | grub_quote)' ${CLASS} \$menuentry_id_option 'gnulinux-simple-$boot_device_id' {" | sed "s/^/$submenu_indentation/"
  fi      
  if [ x$type != xrecovery ] ; then
      save_default_entry | grub_add_tab
  fi

  # Use ELILO's generic "efifb" when it's known to be available.
  # FIXME: We need an interface to select vesafb in case efifb can't be used.
  if [ "x$GRUB_GFXPAYLOAD_LINUX" = x ]; then
      echo "    load_video" | sed "s/^/$submenu_indentation/"
      if grep -qx "CONFIG_FB_EFI=y" "${config}" 2> /dev/null \
          && grep -qx "CONFIG_VT_HW_CONSOLE_BINDING=y" "${config}" 2> /dev/null; then
          echo "        set gfxpayload=keep" | sed "s/^/$submenu_indentation/"
      fi
  else
      if [ "x$GRUB_GFXPAYLOAD_LINUX" != xtext ]; then
          echo "        load_video" | sed "s/^/$submenu_indentation/"
      fi
      echo "    set gfxpayload=$GRUB_GFXPAYLOAD_LINUX" | sed "s/^/$submenu_indentation/"
  fi

  echo "        insmod gzio" | sed "s/^/$submenu_indentation/"

  if [ x$dirname = x/ ]; then
    if [ -z "${prepare_root_cache}" ]; then
      prepare_root_cache="$(prepare_grub_to_access_device ${GRUB_DEVICE} | grub_add_tab)"
    fi
    printf '%s\n' "${prepare_root_cache}" | sed "s/^/$submenu_indentation/"
  else
    if [ -z "${prepare_boot_cache}" ]; then
      prepare_boot_cache="$(prepare_grub_to_access_device ${GRUB_DEVICE_BOOT} | grub_add_tab)"
    fi
    printf '%s\n' "${prepare_boot_cache}" | sed "s/^/$submenu_indentation/"
  fi
  message="$(gettext_printf "Loading Linux %s ..." ${version})"
  sed "s/^/$submenu_indentation/" << EOF
        echo    '$(echo "$message" | grub_quote)'
        linux   ${rel_dirname}/${basename} root=${linux_root_device_thisversion} rw ${args}
EOF
  if test -n "${initrd}" -o -n "${initrd_extra}" ; then
    # TRANSLATORS: ramdisk isn't identifier. Should be translated.
    message="$(gettext_printf "Loading initial ramdisk ...")"
    printf '    %s\n' "echo     '$(echo "$message" | grub_quote)'" | sed "s/^/$submenu_indentation/"
    printf '    %s ' 'initrd' | sed "s/^/$submenu_indentation/"
    for i in ${initrd_extra} ${initrd}; do
        printf ' %s/%s' "${rel_dirname}" "${i}"
    done
    printf '\n'
  fi
  sed "s/^/$submenu_indentation/" << EOF
}
EOF
}

machine=`uname -m`
case "x$machine" in
    xi?86 | xx86_64)
        list=
        for i in /boot/vmlinuz-* /vmlinuz-* /boot/kernel-* ; do
            if grub_file_is_not_garbage "$i" ; then list="$list $i" ; fi
        done ;;
    *) 
        list=
        for i in /boot/vmlinuz-* /boot/vmlinux-* /vmlinuz-* /vmlinux-* /boot/kernel-* ; do
                  if grub_file_is_not_garbage "$i" ; then list="$list $i" ; fi
        done ;;
esac

case "$machine" in
    i?86) GENKERNEL_ARCH="x86" ;;
    mips|mips64) GENKERNEL_ARCH="mips" ;;
    mipsel|mips64el) GENKERNEL_ARCH="mipsel" ;;
    arm*) GENKERNEL_ARCH="arm" ;;
    *) GENKERNEL_ARCH="$machine" ;;
esac

prepare_boot_cache=
prepare_root_cache=
boot_device_id=
title_correction_code=

# Extra indentation to add to menu entries in a submenu. We're not in a submenu
# yet, so it's empty. In a submenu it will be equal to '\t' (one tab).
submenu_indentation=""

is_top_level=true
while [ "x$list" != "x" ] ; do
  linux=`version_find_latest $list`
  gettext_printf "Found linux image: %s\n" "$linux" >&2
  basename=`basename $linux`
  dirname=`dirname $linux`
  rel_dirname=`make_system_path_relative_to_its_root $dirname`
  version=`echo $basename | sed -e "s,vmlinuz-,,g"`
  alt_version=`echo $version | sed -e "s,\.old$,,g"`

  linux_root_device_thisversion="${LINUX_ROOT_DEVICE}"

  echo '# ** linux_root_device_thisversion (1) ' ${linux_root_device_thisversion}

  initrd=
  for i in "initrd.img-${version}" "initrd-${version}.img" "initrd-${version}.gz" \
           "initrd-${version}" "initramfs-${version}.img" \
           "initrd.img-${alt_version}" "initrd-${alt_version}.img" \
           "initrd-${alt_version}" "initramfs-${alt_version}.img" \
           "initramfs-genkernel-${version}" \
           "initramfs-genkernel-${alt_version}" \
           "initramfs-genkernel-${GENKERNEL_ARCH}-${version}" \
           "initramfs-genkernel-${GENKERNEL_ARCH}-${alt_version}"; do
    if test -e "${dirname}/${i}" ; then
      initrd="$i"
      break
    fi
  done
  initrd_extra=
  for i in intel-ucode.img; do
    if test -e "${dirname}/${i}" ; then
      initrd_extra="${initrd_extra} ${i}"
    fi
  done

  config=
  for i in "${dirname}/config-${version}" "${dirname}/config-${alt_version}" "/etc/kernels/kernel-config-${version}" ; do
    if test -e "${i}" ; then
      config="${i}"
      break
    fi
  done

  initramfs=
  if test -n "${config}" ; then
      initramfs=`grep CONFIG_INITRAMFS_SOURCE= "${config}" | cut -f2 -d= | tr -d \"`
  fi

  if test -n "${initrd}" -o -n "${initrd_extra}" ; then
    gettext_printf "Found initrd image(s) in %s:%s\n" "${dirname}" "${initrd_extra} ${initrd}" >&2
  elif test -z "${initramfs}" ; then
    # "UUID=" and "ZFS=" magic is parsed by initrd or initramfs.  Since there's
    # no initrd or builtin initramfs, it can't work here.
    linux_root_device_thisversion=${GRUB_DEVICE}

    echo '# ** linux_root_device_thisversion (2) ' ${linux_root_device_thisversion}

  fi

  if [ "x$is_top_level" = xtrue ] && [ "x${GRUB_DISABLE_SUBMENU}" != xy ]; then
    linux_entry "${OS}" "${version}" simple \
    "${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT}"

    submenu_indentation="$grub_tab"

    if [ -z "$boot_device_id" ]; then
        boot_device_id="$(grub_get_device_id "${GRUB_DEVICE}")"
    fi
    # TRANSLATORS: %s is replaced with an OS name
    echo "submenu '$(gettext_printf "Advanced options for %s" "${OS}" | grub_quote)' \$menuentry_id_option 'gnulinux-advanced-$boot_device_id' {"
    is_top_level=false
  fi

  linux_entry "${OS}" "${version}" advanced \
              "${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT}"

  if test -e "${dirname}/initramfs-${version}-fallback.img" ; then
    initrd="initramfs-${version}-fallback.img"

    if test -n "${initrd}" ; then
      gettext_printf "Found fallback initrd image(s) in %s:%s\n" "${dirname}" "${initrd_extra} ${initrd}" >&2
    fi

    linux_entry "${OS}" "${version}" fallback \
                "${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT}"
  fi

  if [ "x${GRUB_DISABLE_RECOVERY}" != "xtrue" ]; then
    linux_entry "${OS}" "${version}" recovery \
                "single ${GRUB_CMDLINE_LINUX}"
  fi

  list=`echo $list | tr ' ' '\n' | fgrep -vx "$linux" | tr '\n' ' '`
done

# If at least one kernel was found, then we need to
# add a closing '}' for the submenu command.
if [ x"$is_top_level" != xtrue ]; then
  echo '}'
fi

echo "$title_correction_code"


INSERT

UBOS::Utils::saveFile( "$target/etc/grub.d/10_linux", $newTenLinux, 0755, 'root', 'root' );
# END HACKING

        if( UBOS::Utils::myexec( "grub-install '--boot-directory=$target/boot' --recheck '$bootLoaderDevice'", undef, \$out, \$err )) {
            error( "grub-install failed", $err );
            ++$errors;
        }

        my $chrootScript = <<'END';
set -e

perl -pi -e 's/GRUB_DISTRIBUTOR=".*"/GRUB_DISTRIBUTOR="UBOS"/' /etc/default/grub
END

        if( defined( $self->{additionalkernelparameters} ) && @{$self->{additionalkernelparameters}} ) {
            my $addParString = '';
            map { $addParString .= ' ' . $_ } @{$self->{additionalkernelparameters}};
            $addParString =~ s!(["'/])!\$1!g; # escape quotes and slash

            $chrootScript .= <<END;
perl -pi -e 's/GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/GRUB_CMDLINE_LINUX_DEFAULT="\$1$addParString"/' /etc/default/grub
END
        }

        $chrootScript .= <<'END';
grub-mkconfig -o /boot/grub/grub.cfg
END

        if( UBOS::Utils::myexec( "chroot '$target'", $chrootScript, \$out, \$err )) {
            error( "bootloader chroot script failed:", $err, "\nwas", $chrootScript );
            ++$errors;
        }
    }
    return $errors;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

1;

