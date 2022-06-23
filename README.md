# VeeamNotify

Send Veeam Backup & Replication session summary notifications to Discord, Microsoft Teams, and Slack, detailing session result and statistics and optionally alerting you via mention when a job finishes in a warning or failed state.

<img src="https://github.com/tigattack/VeeamNotify/blob/dev/asset/discord.png?raw=true" width="30%"></img> <img src="https://github.com/tigattack/VeeamNotify/blob/dev/asset/slack.png?raw=true" width="30%"></img> <img src="https://github.com/tigattack/VeeamNotify/blob/dev/asset/teams.png?raw=true" width="30%"></img> 

## Installing

Requirements:
* Veeam Backup & Replication 11 or higher.
* PowerShell 5.1 or higher.

Please see the [How to Install](https://github.com/tigattack/VeeamNotify/wiki/%F0%9F%94%A7-How-to-Install) wiki page.

## Supported Job Types

* VM Backup
* VM Replication
* Windows & Linux Agent Backup jobs*


\* Due to limitations in Veeam, only some types of Agent jobs are supported.

**Supported** jobs are known as "Agent Backup" or "Managed by backup server". **Unsupported** jobs are known as "Agent policy" or "Managed by agent".

<img src="asset/agenttypes.png" width="75%"></img>  
**Note:** Linux Agent Backup jobs are also supported, this image is only an example.

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
    "notify": {             # Notify definitions.
        "on_success": true,   # If true, a notification will be sent if the job finishes in a Successful state. 
        "on_failure": true,   # If true, a notification will be sent if the job finishes in a Failed state. 
        "on_warning": true    # If true, a notification will be sent if the job finishes in a Warning state.
    },
    "logging": {            # Logging configuration.
        "enabled": true,      # If true, VeeamNotify will log to a session-specific file in C:\VeeamScripts\VeeamNotify\logs\
        "level": "info",      # Logging level. Possibly values: error, warn, info, debug.
        "max_age_days": 7     # Max age of log files. Set to 0 to disable log expiry.
    },
    "update": {             # Update configuration
		"notify": true,       # If true, VeeamNotify will notify you if an update is available.
		"auto_update": false, # DO NOT USE. If true, VeeamNotify will update itself when an update is available.
		"auto_update_comment": "auto_update will NOT work. Leave as 'false'"
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
