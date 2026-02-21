# LinuxGSM Container Helper

A professional Shell Script utility to deploy and manage LinuxGSM (Linux Game Server Managers) instances within Docker containers.

## 🚀 Overview

This script automates the creation of game server containers using the official `gameservermanagers/gameserver` images. It simplifies complex tasks like port mapping, volume strategy selection, and permission handling.

## ✨ Features

* **Dynamic Game List**: Fetches the latest supported games directly from the LinuxGSM repository.
* **Volume Flexibility**: Choose between standard Docker Named Volumes or Local Host Folders (Bind Mounts) for easy file access.
* **TUI Interface**: User-friendly Text User Interface using `whiptail`.
* **Intelligent Error Handling**: Captures Docker daemon errors (like port conflicts) and displays them clearly.
* **Automated Ownership**: Automatically handles permission alignment for local directory mounts.

## 📋 Prerequisites

Ensure you have the following dependencies installed on your host system:

* `docker`
* `wget`
* `whiptail` (usually part of `newt` or `libnewt` packages)
* `sed`, `tr`, `wc`

## 🛠️ Usage

1. Download the script:
   `wget https://raw.githubusercontent.com/gabu8balls/lgsm-helper/main/linuxgsm.sh`

2. Give execution permission:
   `chmod +x linuxgsm.sh`

3. Run the script:
   `./linuxgsm.sh`

## ⚙️ How it Works

1. **Dependency Check**: Verifies if all necessary tools are installed.
2. **Server List**: Downloads the current CSV of supported games.
3. **Configuration**: Prompts for game selection and TCP/UDP ports.
4. **Storage Strategy**: 
    * **Docker Volume**: Managed internally by Docker.
    * **Local Folder**: Files stored in a path of your choice, allowing direct host editing.
5. **Deployment**: Runs the container with `--restart unless-stopped`.

## 📄 License

This project is licensed under the **Creative Commons** License.

---
**Maintained by**: Gabriel (Gabu) Salvador & André (Magrão) Borali.  
**Code Review**: Gemini 3.1 Pro.  
  
**Original project by**: Daniel Gibbs  
**Visit**: https://linuxgsm.com/  
**Repo**: https://github.com/GameServerManagers/LinuxGSM
