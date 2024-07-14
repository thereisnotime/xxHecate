# xxHecate

A small daemon to manage automatic remote full disk encryption (LUKS) unlock via SSH.

## ✨ Description

TODO

## 📝 Table of Contents

TODO

## 👍 Pros

TODO

## 👎 Cons

TODO

## 🛠️ Installation

### Automated

TODO

### Manual

NOTE: This will install the daemon in your current user's home directory.

```bash
git clone https://github.com/thereisnotime/xxHecate $HOME/.xxHecate
cd $HOME/.xxHecate && cp .env.example .env && cp inventory.csv.example inventory.csv
# NOTE: Now edit the inventory.csv file to include your hosts.
```

## 🗑️ Uninstallation

TODO

## 📚 Usage

TODO

## ⚙️ Compatability

Should work fine with all POSIX compliant shells (and some of the not fully compliant ones). Tested with the following combinations:

- Debian/Ubuntu
- bash/zsh

## 🚀 Roadmap

- [ ] Add support for detailed configuration per inventory item.
- [ ] Add support for a remote GET function for a secure way to disable/sefl-destruct the daemon instance.

## 📜 License

Check the [LICENSE](LICENSE) file for more information.

## 🙏 Acknowledgements

TODO
