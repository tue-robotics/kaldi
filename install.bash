#!/usr/bin/env bash
#
# Install script for Linux based Speech Recognition System
#
# Arpit Aggarwal
# 2018 TU Eindhoven

# Usage Document
usage()
{
    echo "-----------------------------------------------------------------------------"
    echo -e "\e[35m\e[1m                  Kaldi Automatic Speech Recognition \e[0m"
    echo "-----------------------------------------------------------------------------"
    echo "Usage: sudo ./install.bash [options] <values>"
    echo -e "Options:\n \
        -h | --help\n \
        --tue\n \
        --install-kaldi\n \
        --update-kaldi\n \
        --gst-plugin\n \
        --clean"
    echo
    echo "-----------------------------------------------------------------------------"
}

KALDI_REPO="https://github.com/kaldi-asr/kaldi.git"
KALDI="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ASR_LOG=$KALDI/log

# Create Log directory
if [ ! -d "$ASR_LOG" ]
then
    mkdir $ASR_LOG
fi

# Install the required packages and dependencies
sudo apt-get update -qq > /dev/null 2>&1

# Kaldi install dependencies
_kaldi_install_dependencies()
{
    # Install base packages
    sudo apt-get install --assume-yes build-essential git python python-numpy sox swig zip -qq > /dev/null 2>&1
    echo "Checking and installing dependencies..."
    # Change exit to return to source check_dependencies and change back once done
    sed -i "s|exit|return|g" $KALDI/tools/extras/check_dependencies.sh
    source $KALDI/tools/extras/check_dependencies.sh > /dev/null
    sed -i "s|return|exit|g" $KALDI/tools/extras/check_dependencies.sh

    # Install dependencies
    sudo apt-get install libatlas3-base $debian_packages -qq > /dev/null 2>&1
}

# Kaldi check dependencies
_kaldi_check_dependencies()
{
    echo "Checking dependencies..."
    $KALDI/tools/extras/check_dependencies.sh > /dev/null
}

# Kaldi Build (Common to Installation and Update)
_kaldi_build_tools()
{
    # Build toolkit
    echo "Building toolkit..."
    # Build the tools directory
    cd $KALDI/tools
    make -j 8 &> $ASR_LOG/make_tools.log
    make_tools_status=$( tail -n 1 $ASR_LOG/make_tools.log )

    if [ "$make_tools_status" != "All done OK." ]
    then
        echo -e "\e[34m\e[1m Make kaldi/tools failed \e[0m"
        return 1
    fi
    echo "  - Built tools"
}

_kaldi_build_irstlm()
{
    # Install IRSTLM
    # Remove IRSTLM dir if it exists else the install script fails
    cd $KALDI/tools
    if [ -d "irstlm" ]
    then
        rm -rf irstlm
    fi
    extras/install_irstlm.sh &> $ASR_LOG/install_irstlm.log
    install_irstlm_status=$(grep "Installation of IRSTLM finished successfully" $ASR_LOG/install_irstlm.log )

    if [ -z "$install_irstlm_status" ]
    then
        echo -e "\e[34m\e[1m Install kaldi/tools/extras/install_irstlm.sh failed \e[0m"
        return 1
    fi
    echo "  - Built IRSTLM"
}

_kaldi_build_sequitur()
{
    # Install Sequitur
    cd $KALDI/tools
    extras/install_sequitur.sh &> $ASR_LOG/install_sequitur.log
    install_sequitur_status=$(grep "Installation of SEQUITUR finished successfully" $ASR_LOG/install_sequitur.log)

    if [ -z "$install_sequitur_status" ]
    then
        echo -e "\e[34m\e[1m Install kaldi/tools/extras/install_sequitur.sh failed \e[0m"
        return 1
    fi
    echo "  - Built SEQUITUR"
}

_kaldi_build_srilm()
{
    # Install SRILM
    cd $KALDI/tools
    # Download SRILM if .tgz does not exist
    if [ ! -f "srilm.tgz" ]
    then
        wget -q https://github.com/tue-robotics/kaldi_srilm/blob/master/srilm.tgz?raw=true -O srilm.tgz
    fi
    extras/install_srilm.sh &> $ASR_LOG/install_srilm.log
    install_srilm_status=$(grep "Installation of SRILM finished successfully" $ASR_LOG/install_srilm.log)

    if [ -z "$install_srilm_status" ]
    then
        echo -e "\e[34m\e[1m Install kaldi/tools/extras/install_srilm.sh failed \e[0m"
        return 1
    fi
    echo "  - Built SRILM"
}

_kaldi_build_src_cmake()
{
    # Build src using CMake
    cd $KALDI

    if [ -d build ]
    then
        rm -rf build
    fi

    mkdir build
    cd build
    cmake -GNinja -DCMAKE_INSTALL_PREFIX=../dist -DKALDI_BUILD_EXE=OFF -DKALDI_BUILD_TEST=OFF -DBUILD_SHARED_LIBS=ON ..


}

_kaldi_build_src_make()
{
    # Build the src directory
    cd $KALDI/src
    ./configure --shared &> $ASR_LOG/configure_src.log
    configure_src_status=$( grep "SUCCESS" $ASR_LOG/configure_src.log )

    if [ -z "$configure_src_status" ]
    then
        echo -e "\e[34m\e[1m Configure kaldi/src failed \e[0m"
        return 1
    fi
    echo "  - Configured src for build"

    # Make Kaldi without checks (ensures faster compilation)
    sed -i '/-g # -O0 -DKALDI_PARANOID/c\-O3 -DNDEBUG' kaldi.mk
    make depend -j 8 > /dev/null
    make -j 8 &> $ASR_LOG/make_src.log
    make_src_status=$( grep "Done" $ASR_LOG/make_src.log )

    if [ -z "$make_src_status" ]
    then
        echo -e "\e[34m\e[1m Make kaldi/src failed \e[0m"
        return 1
    fi
    echo "  - Built src"
}

_kaldi_build()
{
    _kaldi_build_tools || return 1
    _kaldi_build_irstlm || return 1
    _kaldi_build_sequitur || return 1
    _kaldi_build_srilm || return 1
    _kaldi_build_src_make || return 1

    # Create a STATUS file to monitor installation
    cd $KALDI
    echo "ALL OK" > STATUS
}

# Kaldi Gstreamer plugin with online decoder build
_kaldi_online_gst()
{
    echo "Building online decoder and gstreamer plugin..."
    # Install PortAudio
    cd $KALDI/tools
    extras/install_portaudio.sh &> $ASR_LOG/install_portaudio.log
    install_portaudio_status=$(grep "PortAudio was successfully installed" $ASR_LOG/install_portaudio.log)

    if [ -z "$install_portaudio_status" ]
    then
        echo -e "\e[34m\e[1m Install kaldi/tools/extras/install_portaudio.sh failed \e[0m"
        return 1
    fi
    echo "  - Installed PortAudio"

    # Build online decoder
    cd $KALDI/src/online
    make -j 8 &> $ASR_LOG/make_online.log || { echo -e "\e[34m\e[1m Make kaldi/src/online failed \e[0m"; return 1; }
    echo "  - Built online decoder"

    # Build Gstreamer plugin
    cd $KALDI/src/gst-plugin
    make depend -j 8 > /dev/null
    make -j 8 &> $ASR_LOG/make_gst-plugin.log || { echo -e "\e[34m\e[1m Make kaldi/src/gst-plugin failed \e[0m"; return 1; }
    echo "  - Built gstreamer plugin"

    # Test Gstreamer plugin
    export GST_PLUGIN_PATH=$KALDI/src/gst-plugin${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}
    gst-inspect-1.0 onlinegmmdecodefaster > /dev/null || { echo -e "\e[34m\e[1m gst-inspect of onlinegmmdecodefaster failed \e[0m"; return 1; }
    echo "  - Gstreamer Plugin Test Successful"
}

# Kaldi Installation
kaldi_install()
{
    echo "Checking for an existing Kaldi-ASR installation in $KALDI"

    if [ ! -d "$KALDI" ]
    then
        # Clone repository into $KALDI
        echo -e "No existing installation found. Cloning from GitHub repository"
        git clone $KALDI_REPO $KALDI
        _kaldi_install_dependencies
        _kaldi_build
    else
        # Read STATUS file. If not "ALL OK", remove directory $KALDI and re-install Kaldi
        kaldi_install_status="$(cat $KALDI/STATUS)"

        if [ "$kaldi_install_status" != "ALL OK" ]
        then
            sudo rm -rf $KALDI
            kaldi_install
        fi
    fi
}

# Kaldi Update
kaldi_update()
{
    if [ ! -d "$KALDI" ]
    then
        # Install Kaldi if directory $KALDI not present
    kaldi_install
    else
        # Read STATUS file. If "ALL OK" then update else remove directory $KALDI
        # and re-install Kaldi
        kaldi_install_status="$(cat $KALDI/STATUS)"

        if [ "$kaldi_install_status" = "ALL OK" ]
        then
            # Pull changes from the repository
            echo "Updating repository from GitHub"
            cd $KALDI
            git pull

            # Clean existing make
            _kaldi_clean
            # Build toolkit
            _kaldi_install_dependencies
            _kaldi_build

            echo -e "\e[36m\e[1m Kaldi-ASR update complete \e[0m"
        else
            sudo rm -rf $KALDI
            kaldi_install
        fi
    fi
}

# Clean the repository
_kaldi_clean()
{
    # Clean existing make
    echo -e "\e[36m\e[1m Cleaning existing make \e[0m"
    cd $KALDI/tools
    make distclean
    cd $KALDI/src
    make distclean

    # Remove anyother file not a part of the repository
    cd $KALDI
    git clean -fdx
}

# Read Postional Parameters
if [ -z "$1" ]
then
    usage
else
    while [ "$1" != "" ]
    do
        case $1 in
            --install-kaldi )
                kaldi_install
                echo -e "\e[36m\e[1m Kaldi installation complete \e[0m" ;;

            --update-kaldi )
                kaldi_update ;;

            --clean )
                _kaldi_clean ;;

            --gst-plugin )
                _kaldi_online_gst ;;

            --tue )
                _kaldi_check_dependencies || exit 1
                _kaldi_build_tools || exit 1
                _kaldi_build_src_cmake || exit 1
                echo -e "\e[36m\e[1m Kaldi installation complete \e[0m" ;;

            -h | --help )
                usage
                exit 1 ;;

            * )
                usage
                exit 1 ;;
        esac
        shift
    done
fi
