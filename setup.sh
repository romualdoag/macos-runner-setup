#!/bin/bash -e -o pipefail

source ~/utils.sh

################################################################################
##  Desc:  Create Username to Runner
################################################################################

runner_user='gh-runner'

if [ ! -d "/Users/${runner_user}"]; then
    dscl . -create /Users/$runner_user
    dscl . -create /Users/$runner_user UserShell /bin/zsh
    dscl . -create /Users/$runner_user RealName "GitHub runner"
    dscl . -create /Users/$runner_user UniqueID "1001"
    dscl . -create /Users/$runner_user PrimaryGroupID 20
    dscl . -create /Users/$runner_user NFSHomeDirectory /Users/$runner_user
    dscl . -passwd /Users/$runner_user password
    dscl . -append /Groups/admin GroupMembership $runner_user
    mkdir "/Users/${runner_user}"
    chown ${runner_user}:admin "/Users/${runner_user}"
else
    echo "User ${runner_user} already exists"
    exit 0
fi

sudo tee -a /private/etc/sudoers.d/gh-runner > /dev/null <<EOT
# Give gh-runner sudo access
gh-runner ALL=(ALL) NOPASSWD:ALL
EOT

################################################################################
##  Desc:  Install Python
################################################################################
echo "Brew Installing Python 3"
brew_smart_install "python@3"

echo "Installing pipx"

if is_Arm64; then
    export PIPX_BIN_DIR="$HOME/.local/bin"
    export PIPX_HOME="$HOME/.local/pipx"
else
    export PIPX_BIN_DIR=/usr/local/opt/pipx_bin
    export PIPX_HOME=/usr/local/opt/pipx
fi

brew_smart_install "pipx"

echo "export PIPX_BIN_DIR=${PIPX_BIN_DIR}" >> ${HOME}/.bashrc
echo "export PIPX_HOME=${PIPX_HOME}" >> ${HOME}/.bashrc
echo 'export PATH="$PIPX_BIN_DIR:$PATH"' >> ${HOME}/.bashrc

################################################################################
##  Desc:  Disabling automatic updates
################################################################################

sudo softwareupdate --schedule off
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 0
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 0
defaults write com.apple.commerce AutoUpdate -bool false
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool false

################################################################################
##  Desc:       configure-autologin
################################################################################

echo "Enabling automatic GUI login for the '$USERNAME' user.."
python3 kcpassword.py "$PASSWORD"
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser "$USERNAME"
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow autoLoginUserScreenLocked -bool false


################################################################################
##  Desc:  Configure guest OS settings
################################################################################

echo "Enabling developer mode..."
sudo /usr/sbin/DevToolsSecurity --enable

# Turn off hibernation and get rid of the sleepimage
sudo pmset hibernatemode 0
sudo rm -f /var/vm/sleepimage

# Disable App Nap System Wide
defaults write NSGlobalDomain NSAppSleepDisabled -bool YES

# Disable Keyboard Setup Assistant window
sudo defaults write /Library/Preferences/com.apple.keyboardtype "keyboardtype" -dict-add "3-7582-0" -int 40

# Update VoiceOver Utility to allow VoiceOver to be controlled with AppleScript
# by creating a special Accessibility DB file (SIP must be disabled) and
# updating the user defaults system to reflect this change.
if csrutil status | grep -Eq  "System Integrity Protection status: (disabled|unknown)"; then
    sudo bash -c 'echo -n "a" > /private/var/db/Accessibility/.VoiceOverAppleScriptEnabled'
fi
defaults write com.apple.VoiceOver4/default SCREnableAppleScript -bool YES

echo "Installing Git..."

brew_smart_install "git"

git config --global --add safe.directory "*"

echo "Installing Git LFS"

brew_smart_install "git-lfs"

# Update global git config
git lfs install
# Update system git config
sudo git lfs install --system

echo "Disable all the Git help messages..."
git config --global advice.pushUpdateRejected false
git config --global advice.pushNonFFCurrent false
git config --global advice.pushNonFFMatching false
git config --global advice.pushAlreadyExists false
git config --global advice.pushFetchFirst false
git config --global advice.pushNeedsForce false
git config --global advice.statusHints false
git config --global advice.statusUoption false
git config --global advice.commitBeforeMerge false
git config --global advice.resolveConflict false
git config --global advice.implicitIdentity false
git config --global advice.detachedHead false
git config --global advice.amWorkDir false
git config --global advice.rmHints false


################################################################################
##  Desc:  Configure max files limitation
################################################################################

Launch_Daemons="/Library/LaunchDaemons"

# EOF in quotes to disable variable expansion
echo "Creating limit.maxfiles.plist"
cat > ${Launch_Daemons}/limit.maxfiles.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>limit.maxfiles</string>
    <key>Program</key>
    <string>/Users/$USERNAME/limit-maxfiles.sh</string>
    <key>RunAtLoad</key>
    <true/>
    <key>ServiceIPC</key>
    <false/>
  </dict>
</plist>
EOF

# Creating script for applying workaround https://developer.apple.com/forums/thread/735798

cat > /Users/$USERNAME/limit-maxfiles.sh << EOF
#!/bin/bash
sudo launchctl limit maxfiles 256 unlimited
sudo launchctl limit maxfiles 65536 524288
EOF

echo "limit.maxfiles.sh permissions changing"
chmod +x /Users/$USERNAME/limit-maxfiles.sh

echo "limit.maxfiles.plist permissions changing"
chown root:wheel "${Launch_Daemons}/limit.maxfiles.plist"
chmod 0644 ${Launch_Daemons}/limit.maxfiles.plist

echo "Done, limit.maxfiles has been updated"

################################################################################
##  Desc:  Configure NTP servers and set the timezone to UTC
################################################################################

echo Additional NTP servers adding into /etc/ntp.conf file...
cat > /etc/ntp.conf << EOF
server 0.pool.ntp.org
server 1.pool.ntp.org
server 2.pool.ntp.org
server 3.pool.ntp.org
server time.apple.com
server time.windows.com
EOF

# Set the timezone to UTC.
echo "The Timezone setting to UTC..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

################################################################################
##  Desc:  Configure screensaver
################################################################################

# set screensaver idleTime to 0, to prevent turning screensaver on
macUUID=$(ioreg -rd1 -c IOPlatformExpertDevice | grep -i "UUID" | cut -c27-62)

rm -rf /Users/$USERNAME/Library/Preferences/com.apple.screensaver.$macUUID.plist
rm -rf /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.$macUUID.plist
rm -rf /Users/$USERNAME/Library/Preferences/com.apple.screensaver.plist
rm -rf /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.plist

defaults write /Users/$USERNAME/Library/Preferences/com.apple.screensaver.$macUUID.plist idleTime -string 0
defaults write /Users/$USERNAME/Library/Preferences/com.apple.screensaver.$macUUID.plist CleanExit "YES"
defaults write /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.$macUUID.plist idleTime -string 0
defaults write /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.$macUUID.plist CleanExit "YES"
defaults write /Users/$USERNAME/Library/Preferences/com.apple.screensaver.plist idleTime -string 0
defaults write /Users/$USERNAME/Library/Preferences/com.apple.screensaver.plist CleanExit "YES"
defaults write /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.plist idleTime -string 0
defaults write /Users/$USERNAME/Library/Preferences/ByHost/com.apple.screensaver.plist CleanExit "YES"

chown -R $USERNAME:staff /Users/$USERNAME/Library/Preferences/ByHost/
chown -R $USERNAME:staff /Users/$USERNAME/Library/Preferences/

killall cfprefsd

# Set values to 0, to prevent sleep at all
pmset -a displaysleep 0 sleep 0 disksleep 0

################################################################################
##  Desc:  Configure shell to use bash
################################################################################

arch=$(get_arch)

echo "Changing shell to bash"
sudo chsh -s /bin/bash $USERNAME
sudo chsh -s /bin/bash root

# Check MacOS architecture and add HOMEBREW PATH to bashrc
if [[ $arch == "arm64" ]]; then
  echo "Adding Homebrew environment to bash"
  # Discussed here: https://github.com/Homebrew/brew/pull/18366
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bashrc
fi