# Comprehensive Walkthrough: Project ShadowRelay

## Introduction

This guide provides a detailed, step-by-step walkthrough of the "Project: ShadowRelay" vulnerable lab environment. It is designed to act as both a solution guide and an educational resource. 

The lab simulates a legacy ubuntu server that was hurriedly migrated from a Windows environment. Because of this rushed migration, several critical misconfigurations were left behind that allow an attacker to gain a foothold and eventually compromise the entire system as the root user. 

We will cover the entire attack chain from an external perspective, breaking down the concepts and techniques required at each stage.

---

## Stage 1: Initial Foothold via Local File Inclusion (LFI)

### The Objective
The first goal of any external penetration test or lab is to gain access to the system. In this scenario, we have a targeted web application hosted on an Apache web server.

### The Concept: What is Local File Inclusion (LFI)?
Local File Inclusion (LFI) is a web vulnerability that occurs when a web application takes user input and uses it to construct a file path for an `include` statement (like `require()`, `include()`, or `readfile()` in PHP) without proper sanitization. 

Normally, an application might use input like `?page=home.php` to dynamically load content into a template. If an attacker can manipulate that `page` parameter to point to sensitive files on the server instead—such as system configuration files or password hashes—the application will blindly read and display the contents of those files within the web page.

### The Attack
1.  **Reconnaissance**: Navigating to the web application, we notice the URL structure: `http://<TARGET_IP>/?page=home.php`. The `page` parameter immediately stands out as a potential target for LFI testing.
2.  **Testing for LFI**: We can test if the parameter is vulnerable by attempting to traverse directories backward using `../` and requesting a known system file, such as the Linux password file `/etc/passwd`.
    *   Payload: `http://<TARGET_IP>/?page=../../../../etc/passwd`
    *   Result: If the application is vulnerable, the contents of `/etc/passwd` will be appended to the web page content, revealing a list of users on the system (including our target user, `svc_ldap`).
3.  **Discovery**: While reading `/etc/passwd` is useful for identifying usernames, we need credentials to progress. The lab hints at a "legacy" environment migrated from Windows. This implies there might be old configuration files lying around the web directory. 
4.  **Directory Fuzzing/Brute-forcing**: Using a tool like `ffuf` or `dirb` (or simply guessing based on common migration patterns), an attacker enumerates the web root (`/var/www/html`) and discovers a directory named `legacy_backup`. 
5.  **Extracting Secrets**: Inside this directory, the attacker finds a `web.config` file. They use the LFI vulnerability to read it natively:
    *   Payload: `http://<TARGET_IP>/?page=legacy_backup/web.config`
    *   Result: The application outputs the XML contents of the `web.config` file.

### Findings
Inside the `web.config` file, we discover two critical pieces of information:
*   The first flag: `VulnOS{initial_foothold_ldap}` hidden in an XML comment.
*   The plain-text credentials for the `svc_ldap` service account: `svc_ldap:LdapSvc!2024`.

---

## Stage 2: User Access and Lateral Movement

### The Objective
With valid credentials in hand, the next step is to transition from exploiting a web vulnerability to gaining an interactive shell on the underlying operating system.

### The Concept: Credential Reuse and Exposed Services
Often, service accounts or credentials exposed in legacy files are reused across different services. If the system administrators fail to restrict external access to management protocols like SSH, attackers can attempt to log in using the compromised credentials directly.

### The Attack
1.  **Service Assessment**: An initial port scan (e.g., using `nmap`) of the target IP reveals that Port 22 (SSH) is open.
2.  **Authentication Attempt**: We attempt to authenticate via SSH using the credentials extracted from the `web.config` file.
    *   Command: `ssh svc_ldap@<TARGET_IP>`
    *   When prompted, we provide the password: `LdapSvc!2024`.
3.  **Foothold Established**: The authentication successful. We now have a standard, low-privilege interactive bash shell on the Ubuntu server as the user `svc_ldap`.

### Findings
We have successfully bypassed the perimeter defenses and established a presence on the internal host. We can now begin enumerating the system internally to search for a path to root.

---

## Stage 3: Privilege Escalation to Root

### The Objective
The final objective is to elevate our privileges from the standard `svc_ldap` user to the `root` superuser, granting us total control over the server.

### The Concept: Sudo Misconfigurations and Writable Service Files
In Linux, the `sudo` command allows authorized users to execute programs with the security privileges of another user (typically root). System administrators often configure specific `sudo` rules (in `/etc/sudoers` or `/etc/sudoers.d/`) to allow lower-privileged users to perform specific administrative tasks, such as restarting a service, without needing the full root password.

A critical security flaw occurs when a user is granted `sudo` permissions to execute a script or service that they also have write access to. If an attacker can modify the script and then execute it via `sudo`, the injected malicious code will run as `root`.

This is doubly dangerous with `systemd` services. If a custom service is configured to run as root, and a low-privileged user can both modify the executable and trigger a restart of that service via `sudo`, it creates a direct path to full system compromise.

### The Attack
1.  **Internal Enumeration**: Logged in as `svc_ldap`, we first check what commands we are allowed to run with elevated privileges using the command `sudo -l`.
2.  **Sudo Rule Identification**: The output reveals a specific rule:
    `(root) NOPASSWD: /usr/bin/systemctl restart gfs-backup`
    This means our user, `svc_ldap`, can restart the `gfs-backup` systemd service as root, and we don't even need to provide a password to do so.
3.  **Service Inspection**: We need to understand what this service actually does. We inspect the service file configuration:
    `cat /etc/systemd/system/gfs-backup.service`
    We see that the service executes a bash script located at `/usr/local/bin/gfs_backup_service.sh` and runs under the context `User=root`.
4.  **Permissions Check**: Next, we check the permissions of the underlying executable script:
    `ls -la /usr/local/bin/gfs_backup_service.sh`
    The output shows `-rwxrwxr-x 1 root svc_ldap ...`. 
    This is the critical flaw. The file is owned by root, but the *group* is `svc_ldap`, and the group permissions are `rwx` (read, write, execute). Since we are logged in as `svc_ldap`, we have the ability to write to this file.
5.  **Exploitation**: We edit the backup script using a text editor like `nano` or simply append to it using `echo`. We will inject a command that takes advantage of the root execution context. A simple and reliable method is to copy the bash utility and grant it SUID (Set Owner User ID) permissions, allowing us to launch it as root later.
    *   Command: `echo "cp /bin/bash /tmp/rootbash && chmod +s /tmp/rootbash" >> /usr/local/bin/gfs_backup_service.sh`
6.  **Triggering the Exploit**: We execute the `sudo` command we are permitted to run. This restarts the service, which executes our modified script as root.
    *   Command: `sudo systemctl restart gfs-backup`
7.  **Gaining Root Execution**: The service restarts. The command we injected has copied `bash` to `/tmp` and set the SUID bit. We simply execute our new SUID binary with the `-p` flag (to preserve privileged mode).
    *   Command: `/tmp/rootbash -p`
8.  **Verification**: We run the `id` command and confirm our Effective User ID (euid) is 0 (root). We have successfully compromised the machine.

### Findings
As the root user, we navigate to the `/root` directory and claim the final flag:
`cat /root/flag.txt` -> `VulnOS{root_privesc_complete}`

## Conclusion
This lab demonstrates the compounding danger of multiple misconfigurations. A seemingly simple web vulnerabiity (LFI) exposed legacy credentials. Poor password hygiene and lack of network segmentation allowed those credentials to be reused for interactive SSH access. Finally, a misconfigured automation task (writable script + sudo restart rule) provided the final pivot point, allowing a low-privileged user to seize total control of the system.
