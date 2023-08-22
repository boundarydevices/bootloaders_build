# Bootloaders build tools

Scripts to build various bootloaders (A-TF, U-Boot, OP-TEE) for MediaTek AIoT

Dependencies:
``` {.sh}
$ sudo apt install bc bison build-essential curl flex git libssl-dev python3 python3-pip meson wget -y
$ pip3 install pycryptodome pyelftools shyaml --user
```

## Build bl2
``` {.sh}
usage: build_bl2.sh [options]

$ build_bl2.sh --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Build libatf
``` {.sh}
usage: build_libatf.sh [options]

$ build_libatf.sh --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Build uboot
``` {.sh}
usage: build_uboot.sh [options]

$ build_uboot.sh --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Build optee
``` {.sh}
usage: build_optee.sh [options]

$ build_optee.sh --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Build fip
``` {.sh}
usage: build_fip.sh [options]

$ build_fip.sh --config=i350-pumpkin.yaml --bl32=tee.bin --bl33=u-boot.bin --output=fip-test.bin

Options:
  --config   Mediatek board config file
  --bl32     Path to bl32 binary
  --bl33     Path to bl33 binary
  --output   (OPTIONAL) Output name of fip binary
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Build ALL
``` {.sh}
usage: build_all.sh [options]

$ build_all.sh --config=i350-pumpkin.yaml

Options:
  --config   Mediatek board config file
  --clean    (OPTIONAL) clean before build
  --mode     (OPTIONAL) [release|debug|factory] mode (default: release)
  --help     (OPTIONAL) display usage
```

## Setup Android
``` {.sh}
usage: setup_android.sh [options]

$ setup_android.sh --aosp=/home/julien/Documents/mediatek/android --branch=jmasson/update-binaries

Options:
  --aosp     Android Root path
  --branch   Branch name
  --clean    (OPTIONAL) clean up AOSP projects
  --help     (OPTIONAL) display usage
```

## Release Android
``` {.sh}
usage: release_android.sh [options]

$ release_android.sh --aosp=/home/julien/Documents/mediatek/android

Options:
  --aosp     Android Root path
  --commit   (OPTIONAL) commit binaries in AOSP
  --config   (OPTIONAL) release ONLY for this board config file
  --help     (OPTIONAL) display usage
  --mode     (OPTIONAL) [release|debug|factory] build only one mode
  --no-build (OPTIONAL) don't rebuild the images
  --silent   (OPTIONAL) silent build commands
  --skip-ta  (OPTIONAL) skip build Trusted Applications

By default release and debug modes are built.
```

## Secure
``` {.sh}
usage: secure.sh function

Functions supported can be found in secure.sh
```

## Commit Binaries

``` {.sh}
usage: commit-binaries.sh [options]

$ commit-binaries.sh --from-repo=<repo root directory> --to-repo=<repo root directory> --to-project=<project sub-path>

Options:
  --from-repo               Absolute path to the source repo
  --from-projects           (OPTIONAL) space-separated list of relative source projects. Defaults to all
  --to-repo                 Absolute path to the destination repo
  --to-project              Relative path in the destination repo where git commit is ran
  --title-prefix            (OPTIONAL) commit message title prefix. Defaults to "generic"
  --dry-run                 (OPTIONAL) don't commit, pass --dry-run to git instead
  --no-fail-on-empty-commit (OPTIONAL) return success if nothing to commit
  --help                    (OPTIONAL) display usage

Examples:
  $ commit-binaries.sh --from-repo=/home/user/src/android-common-kernel --from-projects='common hikey-modules' \
                       --to-repo=/home/user/src/aosp --to-project=device/amlogic/yukawa-kernel
```
