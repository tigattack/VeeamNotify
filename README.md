# VeeamNotify

# WORK IN PROGRESS

Send Veeam Backup & Replication session summary notifications to Discord, Microsoft Teams, and Slack, detailing session result and statistics and optionally alerting you via mention when a job finishes in a warning or failed state.

<a href="https://github.com/tigattack/VeeamDiscordNotifications/blob/master/asset/embeds.png"><img src="https://github.com/tigattack/VeeamDiscordNotifications/blob/dev/asset/embeds-small.png?raw=true" alt="Notification Example" width="90%"/></a>

## Installing

Requirements:
* Veeam Backup & Replication 10 or higher.
* PowerShell 5.1 or higher.

* Option 1 - Install script. This option will also optionally configure any supported Veeam jobs to work with VeeamNotify.
  1. Download [Installer.ps1](Installer.ps1).
  2. Open PowerShell (as Administrator) on your Veeam server.
  3. Run the following commands:
      ```powershell
      PS> Set-ExecutionPolicy -Scope Process -ExecutionPolicy Unrestricted -Force
      PS> Unblock-File C:\path\to\Installer.ps1
      PS> C:\path\to\Installer.ps1
      ```
      <img src="https://github.com/tigattack/VeeamDiscordNotifications/blob/dev/asset/installer.png?raw=true" alt="Installer Example" width="75%"/>

* Option 2 - Manual install
  * Follow the [setup instructions](https://blog.tiga.tech/veeam-b-r-notifications-in-discord/).

## Supported Job Types

* VM Backup
* VM Replication
* Agent jobs managed by backup server

### Agent job caveats

Due to limitations caused by the way some types of Veeam Agent jobs are executed, only Agent jobs of type "Managed by backup server" support post-job scripts.
Such jobs will show up as follows:
* In Veeam Backup & Replication Console, with "Type" property of "Windows/Linux Agent Backup".
If you see "Windows/Linux Agent _Policy_", this job is not supported.
* In Veeam Backup & Replication PowerShell module, with "JobType" property of "EpAgentBackup".
If you see "EpAgentPolicy", this job is not supported.

You can read about the difference between these two Agent job types [here](https://helpcenter.veeam.com/docs/backup/agents/agent_job_protection_mode.html?ver=110#selecting-job-mode).

Unfortunately, even Agent backup sessions managed by the backup server, while supported, are limited in data output.  
As much relevant information as I've been able to discover from such backup sessions is included in the notifications, but I welcome any suggestions for improvement in this area.

## Configuration options

Configuration can be found in `C:\VeeamScripts\VeeamNotify\config\conf.json`

| Name                 | Type    | Required | Default           | Description                                                                                                |
|----------------------|---------|----------|-------------------|------------------------------------------------------------------------------------------------------------|
| `webhook`            | string  | True     | null              | Your webhook URL.                                                                                          |
| `discord_userid`     | string  | False    | null              | Your Discord user ID. Required if either of the `mention_` options below are `true`.                       |
| `slack_userid`       | string  | False    | null              | Your Slack member ID. Required if either of the `mention_` options below are `true`.                       |
| `teams_upn`          | string  | False    | null              | Your user UPN for Teams. Required if either of the `mention_` options below are `true`.                    |
| `mention_on_fail`    | boolean | False    | False             | When `true`, you will be mentioned when a job finishes in a failed state. Requires that `userid` is set.   |
| `mention_on_warning` | boolean | False    | False             | When `true`, you will be mentioned when a job finishes in a warning state. Requires that `userid` is set.  |
| `notify_update`      | boolean | False    | True              | When `true`, the script will notify you if there's a newer version available.                              |
| `self_update`        | boolean | False    | False             | When `true`, the script will update itself if there's a newer version available.                           |
| `debug_log`          | boolean | False    | False             | When `true`, the script will log to a session-specific file in `C:\VeeamScripts\VeeamNotify\logs\`         |
| `thumbnail`          | string  | False    | See example above | Image URL for the thumbnail shown in the report embed.                                                     |
| `log_expiry_days`    | integer | False    | 7                 | Will delete logs older than value. Set to 0 to disable.                                                    |

---

## Credits

[MelonSmasher](https://github.com/MelonSmasher)//[TheSageColleges](https://github.com/TheSageColleges) for [the project](https://github.com/TheSageColleges/VeeamSlackNotifications) which inspired this one. Much of MelonMasher's codebase was incredibly useful.  
[dantho281](https://github.com/dantho281) for various things - Assistance with silly little issues, the odd bugfix here and there, and the inspiration for and first works on the `Updater.ps1` script.  
[Lee_Dailey](https://reddit.com/u/Lee_Dailey) for general pointers and the [first revision](https://pastebin.com/srN5CKty) of the `ConvertTo-ByteUnit` function.  
[philenst](https://github.com/philenst) for the `DeployVeeamConfiguration.ps1` script.  
[s0yun](https://github.com/s0yun) for the `Installer.ps1` script.  

Thank you all.
