# xxHecate

A small tool to unlock your devices with fully encrypted disks (LUKS) SSH remotely.

## ✨ Description

xxHecate is a small daemon that allows you to unlock your LUKS (full-disk) encrypted devices remotely via SSH. It is designed to be lightweight and secure. It uses SSH for communication and is easy to install and use. It is designed to be a single point of entry for unlocking multiple LUKS devices on different hosts and networks.

You can use it as a script, as a cron, as a service - it's up to you. It is designed to be flexible and easy to use.

It also depends on you having an SSH to your initramfs (dropbear or other) and a way to unlock your LUKS devices via SSH. You can find a guide on how to enable full disk encryption with LUKS and allow unlock via SSH [here](./guides/setup-dropbear-ssh.md).

For other guides and information, check the [guides](./guides) directory.

### 🎥 Demo

TODO - Add a demo here.

## 📝 Table of Contents

- [xxHecate](#xxhecate)
  - [✨ Description](#-description)
    - [🎥 Demo](#-demo)
  - [📝 Table of Contents](#-table-of-contents)
  - [👍 Pros](#-pros)
  - [👎 Cons](#-cons)
  - [🔩 Technical Details](#-technical-details)
  - [🛠️ Installation](#️-installation)
    - [Via Git](#via-git)
    - [Automate - Setup a Cron Job](#automate---setup-a-cron-job)
    - [Automate - Setup a Systemd Service](#automate---setup-a-systemd-service)
  - [🗑️ Uninstallation](#️-uninstallation)
  - [📚 Usage](#-usage)
  - [📁 Folder Structure](#-folder-structure)
  - [⚙️ Compatability](#️-compatability)
  - [🚀 Roadmap](#-roadmap)
  - [📜 License](#-license)
  - [🙏 Acknowledgements](#-acknowledgements)
  
## 👍 Pros

- **Secure**: Uses SSH for communication.
- **Simple**: Easy to install and use.
- **Lightweight**: Uses minimal resources.
- **Flexible**: Can be configured to unlock multiple hosts.
- **Open Source**: You can audit the code and modify it to your needs.

## 👎 Cons

- **Single Point of Failure**: If the device where the daemon is running compromised, all your LUKS devices are at risk.

## 🔩 Technical Details

The general logic and script flow is quite simple, when the script is executed:

1. It will load `inventory.csv` (and `.env`) to get the list of your LUKS encrypted devices and their passwords.
2. It will test the TCP connection to the hosts in the inventory to verify that they are up.
3. It will check if the SSH keys for each host are valid and have the correct permissions.
4. It will connect to the SSH server with the provided details in `inventory.csv` and then run the `cryptroot-unlock` command to unlock the LUKS device with the password provided in `inventory.csv`.

## 🛠️ Installation

The tool is esentially a Bash script and has `inventory.csv` for your device list and `.env` for configurations. Below are the steps to `install` it.

### Via Git

This will 'install' the tool in your current user's home directory.

```bash
git clone https://github.com/thereisnotime/xxHecate $HOME/.xxHecate
cd $HOME/.xxHecate && cp .env.example .env && cp inventory.csv.example inventory.csv
chmod +x xxhecate.sh
# NOTE: Now you must edit the inventory.csv file to include your hosts and their LUKS decryption passwords.
```

### Automate - Setup a Cron Job

If you want to unlock all your LUKS devices every 15 minutes, you can add a cron job like this:

```bash
(crontab -l 2>/dev/null; echo "*/15 * * * * $HOME/.xxHecate/xxhecate.sh") | crontab -
```

### Automate - Setup a Systemd Service

If you want to run the daemon as a service, you can create a systemd service like this:

```bash
mkdir -p ~/.config/systemd/user && \
echo -e "[Unit]\nDescription=Run xxHecate\n\n[Service]\nType=simple\nExecStart=$HOME/.xxHecate/xxhecate.sh" > ~/.config/systemd/user/xxhecate.service && \
echo -e "[Unit]\nDescription=Runs xxHecate every 15 minutes\n\n[Timer]\nOnCalendar=*:0/15\nPersistent=true\n\n[Install]\nWantedBy=timers.target" > ~/.config/systemd/user/xxhecate.timer && \
systemctl --user daemon-reload && \
systemctl --user enable --now xxhecate.timer
```

## 🗑️ Uninstallation

You can just do:

```bash
rm -rf $HOME/.xxHecate
```

And remove crons or services you have set up for it.

```bash
crontab -e # Remove the cron job
rm -rf ~/.config/systemd/user/xxhecate.* # Remove the systemd service and timer
systemctl --user daemon-reload
```

## 📚 Usage

Simple manual usage is as follows:

```bash
bash xxhecate.sh
```

## 📁 Folder Structure

```text
.
├── 📦 xxHecate
├── .env - Configuration file for the script.
├── .env.example - Example of above.
├── inventory.csv - The inventory with your devices and LUKS passwords.
├── inventory.csv.example - Example of above.
├── xxHecate.log - Default log file for the execution logs.
└── xxhecate.sh - The script itself.
```

## ⚙️ Compatability

Should work fine with all POSIX compliant shells (and some of the not fully compliant ones). Tested with the following combinations:

- Debian/Ubuntu
- bash/zsh/fish

## 🚀 Roadmap

We dun did it so far but here are some things we might do in the future:

- [ ] Add support for detailed configuration per inventory item.
- [ ] Add support for loading the inventory from the environment.
- [ ] Add support for a remote GET function for a secure way to disable/self-destruct the daemon instance (killswitch).
- [ ] Add guide and support for other init systems (ex. initrd) and SSH implementations (ex. dracut-sshd).

## 📜 License

Check the [LICENSE](LICENSE) file for more information.

## 🙏 Acknowledgements

- [dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html)
- [tree-nathanfriend.io](https://tree.nathanfriend.io/?s=(%27opt8s!(%27fancy6~fullPath!false~trailingSlash6~rootDot6)~9(%279%27%F0%9F%93%A6%20J4.env0Configurat82scriptG.en*MvI3%20with%20youBdevicesFnd%20LUKS%20passwordsGM*J.log0Default%20log2execut8%20logsGxxh7.shIscript%20itself.%27)~vers8!%271%27)*v.eAe0EA5ofFboveG0%20-%202%20fil5foBth53inventory4%5Cn5e%206!true7ecate8ion9source!AxamplBr%20F%20aG.4I0Th5JxxH7M3.cs%01MJIGFBA987654320*)
