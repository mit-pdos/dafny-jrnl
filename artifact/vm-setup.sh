#!/usr/bin/env bash

# Set up an Ubuntu VM with dependencies to run the evaluation.
#
# Run this in the VM. Requires no setup after installing Ubuntu.
#
# Make sure to _reboot_ after running, since this script installs a new kernel.

set -eu

cd

# Install really basic dependencies

sudo apt-get update
sudo apt-get install -y git python3-pip wget unzip

# SSH with empty password
sudo passwd -d ubuntu
sudo sed -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' -i /etc/ssh/sshd_config
sudo sed -e 's/PasswordAuthentication no/PasswordAuthentication yes/' -i /etc/ssh/sshd_config
sudo systemctl restart sshd

# Get source code

## assumes https://github.com/mit-pdos/daisy-nfsd has already been cloned to
## ~/daisy-nfsd (since this is the easiest way to run this script)
ln -s ~/daisy-nfsd/eval ~/artifact

git clone \
    --recurse-submodules \
    https://github.com/mit-pdos/perennial

mkdir ~/code
cd ~/code
git clone https://github.com/mit-pdos/go-nfsd
git clone https://github.com/mit-pdos/xv6-public
git clone --depth=1 https://github.com/linux-test-project/ltp
git clone --depth=1 https://github.com/pimlie/ubuntu-mainline-kernel.sh
cd

cat >> ~/.profile <<EOF
export DAISY_NFSD_PATH=$HOME/daisy-nfsd
export GO_NFSD_PATH=$HOME/code/go-nfsd
export PERENNIAL_PATH=$HOME/perennial
export XV6_PATH=$HOME/code/xv6-public
export LTP_PATH=$HOME/code/ltp
EOF
echo "source ~/.profile" >> ~/.zshrc

# Install Dafny

DAFNY_VERSION=3.1.0
wget -O /tmp/dafny.zip "https://github.com/dafny-lang/dafny/releases/download/v$DAFNY_VERSION/dafny-$DAFNY_VERSION-x64-ubuntu-16.04.zip"
cd
unzip /tmp/dafny.zip
mv dafny .dafny-bin
rm /tmp/dafny.zip
echo "export PATH=\$HOME/.dafny-bin:\$PATH" >> ~/.profile

# Set up NFS client and server

sudo apt-get install -y rpcbind nfs-common nfs-server
sudo mkdir -p /srv/nfs/bench
sudo chown "$USER:$USER" /srv/nfs/bench
sudo mkdir -p /mnt/nfs
sudo chown "$USER:$USER" /mnt/nfs
echo "/srv/nfs/bench localhost(rw,sync,no_subtree_check,fsid=0)" | sudo tee -a /etc/exports

## for simplicity we enable these services so they are automatically started,
## but they can instead be started manually on each boot
sudo systemctl enable rpcbind
sudo systemctl enable rpc-statd
sudo systemctl disable nfs-server
# can't run go-nfsd and Linux NFS server at the same time
sudo systemctl stop nfs-server

# Set up Linux file-system tests

sudo apt-get install -y autoconf m4 automake pkg-config
cd ~/code/ltp
make -j4 autotools
./configure
make -j4 -C testcases/kernel/fs/fsstress
make -j4 -C testcases/kernel/fs/fsx-linux
cd

# Install Python dependencies

pip3 install argparse pandas

# gnuplot (for creating graphs)

sudo apt-get install -y gnuplot-nox

# Install Go and Go dependencies

GO_FILE=go1.16.3.linux-amd64.tar.gz
wget https://golang.org/dl/$GO_FILE
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf $GO_FILE
rm $GO_FILE
# shellcheck disable=SC2016
echo 'export PATH=$HOME/go/bin:/usr/local/go/bin:$PATH' >> ~/.profile
export PATH=/usr/local/go/bin:$PATH
go install golang.org/x/tools/cmd/goimports@latest

cd ~/code/go-nfsd
# fetch dependencies
go build ./cmd/go-nfsd && rm go-nfsd
cd

# Install Coq

# opam dependencies
sudo apt-get install -y m4 bubblewrap
# coq dependencies
sudo apt-get install -y libgmp-dev

# use binary installer for opam since it has fewer dependencies than Ubuntu
# package
wget https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh
# echo is to answer question about where to install opam
echo "" | sh install.sh --no-backup
rm install.sh

opam init --auto-setup --bare
# TODO: temporarily disabled since this takes forever
#opam switch create 4.11.0+flambda
#eval $(opam env)
#opam install -y -j4 coq.8.13.1

# Upgrade to Linux 5.11 to get fix for NFS client bug:
# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/fs/nfs?id=3b2a09f127e025674945e82c1ec0c88d6740280e
sudo ~/code/ubuntu-mainline-kernel.sh/ubuntu-mainline-kernel.sh --yes -i v5.11.16
# remove old kernel to save space
#
# TODO: this requires approval because it removes the current kernel, until the
# system is rebooted
# sudo apt-get -y remove linux-image-5.8.0-50-generic linux-modules-5.8.0-50-generic linux-headers-5.8.0-50

sudo apt clean
opam clean
