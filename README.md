# xxHecate

A small tool to unlock your encrypted storage (LUKS full-disk, TrueNAS/ZFS datasets) over SSH remotely.

## ✨ Description

xxHecate is a small daemon that allows you to unlock your LUKS (full-disk) encrypted devices remotely via SSH. It is designed to be lightweight and secure. It uses SSH for communication and is easy to install and use. It is designed to be a single point of entry for unlocking multiple LUKS devices on different hosts and networks.

It also unlocks **TrueNAS ZFS native-encrypted datasets**, which do not use LUKS or an initramfs SSH shell. Pick the behaviour per inventory row with the `method` column (see [Unlock methods](#-unlock-methods)).

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
  - [🔓 Unlock methods](#-unlock-methods)
    - [TrueNAS / ZFS notes](#truenas--zfs-notes)
  - [⚙️ Configuration](#️-configuration)
  - [🔐 Security](#-security)
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

- **Secure**: Uses SSH for communication. Passphrases are passed on stdin, never in a command line.
- **Simple**: Easy to install and use.
- **Lightweight**: Uses minimal resources. No dependencies beyond `ssh` and `nc`.
- **Flexible**: Unlocks LUKS (initramfs) and TrueNAS/ZFS hosts from one inventory.
- **Idempotent**: Safe to run on a short timer; already-unlocked targets are skipped.
- **Open Source**: You can audit the code and modify it to your needs.

## 👎 Cons

- **Single Point of Failure**: If the device where the daemon is running compromised, all your LUKS devices are at risk.
- **Unverified initramfs host keys**: the `luks` method cannot verify the host key, because an initramfs presents a different one than the booted OS. See [Security](#-security).

## 🔩 Technical Details

The general logic and script flow is quite simple, when the script is executed:

1. It will load `inventory.csv` (and `.env`) to get the list of your encrypted devices and their passwords.
2. It will test the TCP connection to the hosts in the inventory to verify that they are up.
3. It will check if the SSH keys for each host are valid and have the correct permissions.
4. It will connect to the SSH server with the provided details in `inventory.csv` and run the unlock appropriate to that row's `method`.

## 🔓 Unlock methods

The `method` column selects how a host is unlocked. It is optional: an empty value (or a 5-column inventory with no `method` column at all) means `luks`, so existing inventories keep working unchanged.

| `method` | `target` | What it does |
| --- | --- | --- |
| `luks` (default), `cryptroot` | ignored | SSH into the initramfs shell (dropbear or similar) and pipe the passphrase into `cryptroot-unlock`. |
| `truenas-zfs`, `truenas`, `zfs` | encryption root, default `tank` | SSH into a running TrueNAS and unlock the ZFS dataset tree through the middleware. |

Inventory format:

```csv
host,user,password,port,key,method,target
192.168.1.2,root,luks-passphrase,22,/path/to/keyfile,luks,
192.168.1.3,root,zfs-passphrase,22,/path/to/keyfile,truenas-zfs,tank
```

### TrueNAS / ZFS notes

- **Only the encryption root needs a passphrase.** Every child dataset inherits its key from the root (`encryptionroot` points at it), so one recursive unlock covers the whole tree. Listing each child with the passphrase repeated is unnecessary. Check yours with `zfs get -r -o name,value encryptionroot <pool>` — if every encrypted dataset reports the same root, a single row is enough.
- **The passphrase is passed on stdin, never in argv**, so it does not appear in the process list on the client or on the NAS.
- `pool.dataset.unlock` is a middleware *job*. xxHecate waits for it and reports the real result, instead of returning a job id and assuming success.
- **It is idempotent.** The dataset is queried first and the unlock is skipped when the tree is already unlocked, so it is safe on a short timer.
- Requires `python3` and the `truenas_api_client` module on the NAS. Both ship with TrueNAS SCALE.
- The user needs permission to call the middleware (`root`, or an account with equivalent API access).

## ⚙️ Configuration

All settings live in `.env` (copy `.env.example`). Every one has a working default, so an empty `.env` is fine.

Precedence is **environment > `.env` > default**, so you can override any setting for a single run without editing `.env`:

```bash
XXHECATE_INVENTORY=/tmp/one-host.csv bash xxhecate.sh
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `XXHECATE_INVENTORY` | `inventory.csv` (next to the script) | Path to the inventory. |
| `XXHECATE_LOG_FILE` | `xxHecate.log` (next to the script) | Append-only run log. |
| `XXHECATE_LOOP` | `0` | `0` walks the inventory once and exits. `1` loops forever. |
| `XXHECATE_SLEEP_DURATION` | `60` | Seconds between passes. **Only used when `XXHECATE_LOOP=1`.** |
| `XXHECATE_KNOWN_HOSTS` | *(empty)* | known_hosts file used to verify `truenas-zfs` hosts. Empty means no verification, and a warning is logged. |

Use `XXHECATE_LOOP=0` (the default) with cron or a systemd **timer**. Use `XXHECATE_LOOP=1` only when running it as a long-lived service with no timer, since looping under a timer stacks overlapping runs.

Enable verbose output by creating the debug flag file next to the script:

```bash
touch XXHECATE_DEBUG_MODE
```

## 🔐 Security

Anything that holds every passphrase for every encrypted host deserves a careful read. What this tool does and does not protect:

- **Passphrases are never in argv.** They are written to the SSH channel's stdin, so they do not appear in `ps`, in `/proc`, or in shell history on either the client or the target.
- **Inventory secrets are plaintext on disk.** `inventory.csv` and `.env` are gitignored, but they are not encrypted. Protect them with file permissions (`chmod 600`) and treat the host running xxHecate as being as sensitive as every machine it unlocks.
- **Host-key verification is only possible for booted hosts.** Set `XXHECATE_KNOWN_HOSTS` and `truenas-zfs` targets are verified; a mismatch aborts before the passphrase is sent. Build the file with:

  ```bash
  ssh-keyscan -p 22 <host> >> known_hosts
  ```

- **The `luks` method is unverified by design.** A dropbear initramfs has its own host key, distinct from the booted OS and often regenerated, so strict checking would fail every boot. The practical consequence is that anyone able to impersonate that IP during the unlock window can capture the passphrase. Keep the unlock path on a trusted network segment.
- **Use a dedicated key per purpose.** The unlocker key should grant nothing except the unlock, ideally forced to a single command in the target's `authorized_keys`.

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

One pass, with verification and verbose output:

```bash
XXHECATE_KNOWN_HOSTS=./known_hosts bash xxhecate.sh
```

Run continuously instead of under a timer, re-checking every 5 minutes:

```bash
XXHECATE_LOOP=1 XXHECATE_SLEEP_DURATION=300 bash xxhecate.sh
```

Each run logs to `XXHECATE_LOG_FILE` as well as stdout, so `tail -f xxHecate.log` shows what a cron or timer run did.

## 📁 Folder Structure

```text
.
├── 📦 xxHecate
├── .env - Configuration file for the script.
├── .env.example - Example of above.
├── inventory.csv - The inventory with your devices and LUKS passwords.
├── inventory.csv.example - Example of above.
├── xxHecate.log - Default log file for the execution logs.
├── XXHECATE_DEBUG_MODE - Create this file to enable debug logging (optional).
└── xxhecate.sh - The script itself.
```

## ⚙️ Compatability

Should work fine with all POSIX compliant shells (and some of the not fully compliant ones). Tested with the following combinations:

- Debian/Ubuntu (LUKS / dropbear initramfs)
- TrueNAS SCALE (ZFS native encryption, via the middleware client)
- bash/zsh/fish

## 🚀 Roadmap

We dun did it so far but here are some things we might do in the future:

- [x] Add support for detailed configuration per inventory item (the `method` and `target` columns).
- [x] Add support for unlocking TrueNAS / ZFS native-encrypted datasets.
- [x] Verify host keys where it is possible to do so (`XXHECATE_KNOWN_HOSTS`).
- [ ] Add support for loading the inventory from the environment.
- [ ] Encrypt the inventory at rest (age/sops) instead of relying on file permissions.
- [ ] Add support for a remote GET function for a secure way to disable/self-destruct the daemon instance (killswitch).
- [ ] Add guide and support for other init systems (ex. initrd) and SSH implementations (ex. dracut-sshd).

## 📜 License

Check the [LICENSE](LICENSE) file for more information.

## 🙏 Acknowledgements

- [dropbear](https://matt.ucc.asn.au/dropbear/dropbear.html)
- [tree-nathanfriend.io](https://tree.nathanfriend.io/?s=(%27opt8s!(%27fancy6~fullPath!false~trailingSlash6~rootDot6)~9(%279%27%F0%9F%93%A6%20J4.env0Configurat82scriptG.en*MvI3%20with%20youBdevicesFnd%20LUKS%20passwordsGM*J.log0Default%20log2execut8%20logsGxxh7.shIscript%20itself.%27)~vers8!%271%27)*v.eAe0EA5ofFboveG0%20-%202%20fil5foBth53inventory4%5Cn5e%206!true7ecate8ion9source!AxamplBr%20F%20aG.4I0Th5JxxH7M3.cs%01MJIGFBA987654320*)
