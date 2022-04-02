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

Default configuration can be found in `C:\VeeamScripts\VeeamNotify\config\conf.json`

An example configuration can be found below with highlighted comments.

__Do not copy/paste it. It is not valid JSON.__

```json
{
    "services": {                       # Service definitions.
        "discord": {                      # Discord service.
            "webhook": "DiscordWebhook",    # Discord webhook.
            "user_id": "123456789"          # Discord user id. Required only if any of the mention conditions are true.
        },
        "slack": {                        # Slack service.
            "webhook": "SlackWebhook",      # Slack webhook.
            "user_id": "A1B2C3D4E5"         # Slack user id. Required only if any of the mention conditions are true.
        },
        "teams": {                        # Teams service.
            "webhook": "TeamsWebhook",      # Teams webhook.
            "user_id": "user@domain.tld",   # Teams user id. Required only if any of the mention conditions are true.
            "user_name": "Your Name"        # Teams user name. Required only if any of the mention conditions are true.
        }
    },
    "mentions": {           # Mention definitions. All options require user_id (and user_name if Teams) above.
        "on_failure": false,  # If true, you will be mentioned when a job finishes in a failed state. 
        "on_warning": false   # If true, you will be mentioned when a job finishes in a warning state.
    },
        "notify": {           # Notify definitions.
        "on_success": true,  # If true, a notification will be sent if the job finishes in a Successful state. 
        "on_failure": false,  # If true, a notification will be sent if the job finishes in a Failed state. 
        "on_warning": false   # If true, a notification will be sent if the job finishes in a Warning state.
    },
    "logging": {            # Logging configuration.
        "enabled": true,      # If true, VeeamNotify will log to a session-specific file in C:\VeeamScripts\VeeamNotify\logs\
        "level": "info",      # Logging level. Possibly values: error, warn, info, debug.
        "max_age_days": 7     # Max age of log files. Set to 0 to disable log expiry.
    },
    "update": {             # Update configuration
		"notify": true,       # If true, VeeamNotify will notify you if an update is available.
		"auto_update": false, # DO NOT USE. If true, VeeamNotify will update itself when an update is available.
		"auto_update_comment": "auto_update will NOT work. Leave as 'false'."
	},
    "thumbnail": "https://some.url/img.jpg",  # Image URL for the thumbnail shown in the report embed.
}
```

---

## Credits

[MelonSmasher](https://github.com/MelonSmasher)//[TheSageColleges](https://github.com/TheSageColleges) for [the project](https://github.com/TheSageColleges/VeeamSlackNotifications) which inspired me to make this.  
[dantho281](https://github.com/dantho281) for various things - Assistance with silly little issues, the odd bugfix here and there, and the inspiration for and first works on the `Updater.ps1` script.  
[Lee_Dailey](https://reddit.com/u/Lee_Dailey) for general pointers and the [first revision](https://pastebin.com/srN5CKty) of the `ConvertTo-ByteUnit` function.  
[philenst](https://github.com/philenst) for committing or assisting with a number of core components of the project.  
[s0yun](https://github.com/s0yun) for the `Installer.ps1` script.  

Thank you all.
