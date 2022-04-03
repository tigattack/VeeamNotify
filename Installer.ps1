#Requires -RunAsAdministrator

# Support for passing a parameter to CLI to install using branch
param
(
	[ValidateSet('main', 'dev')]
	$Branch
)

# Prepare variables
$rootPath = 'C:\VeeamScripts'
$project = 'VeeamNotify'
$ErrorActionPreference = 'Stop'

Write-Output @"
#######################################
#                                     #
#        VeeamNotify Installer        #
#                                     #
#######################################`n`n
"@

function Get-ProjectBranch {
	Param
	(
		[Parameter(Mandatory=$true, Position=0)]
		[string]$Branch
	)
	# This is required as release is used later for extracting etc.
	$script:release = $Branch
	# Pull latest version of script from GitHub
	$DownloadParams = @{
		Uri     = "https://github.com/tigattack/$project/archive/refs/heads/$Branch.zip"
		OutFile = "$env:TEMP\$project-$release.zip"
	}
	Try {
		Write-Output "`nDownloading $release branch of $project from GitHub..."
		Invoke-WebRequest @DownloadParams
	}
	catch {
		$downloadStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to download $release branch of $project. Please check your internet connection and try again.`nStatus code: $downloadStatusCode"
		exit 1
	}
}

if ($branch -eq 'main') {
	Get-ProjectBranch -Branch 'main'

}
elseif ($branch -eq 'dev') {
	Get-ProjectBranch -Branch 'dev'


}
else {
	# Get latest release from GitHub
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	try {
		$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/releases" -Method Get
	}
	catch {
		$versionStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to query GitHub for the latest version. Please check your internet connection and try again.`nStatus code: $versionStatusCode"
		exit 1
	}

	foreach ($i in $releases) {
		if ($i.prerelease) {
			$latestPrerelease = $i.tag_name
			break
		}
	}
	foreach ($i in $releases) {
		if (-not $i.prerelease) {
			$latestStable = $i.tag_name
			break
		}
	}

	# Query release stream
	if ($releases[0].prerelease) {
		$versionQuery_stable = New-Object System.Management.Automation.Host.ChoiceDescription '&Stable', "Stable version $latestStable"
		$versionQuery_prerelease = New-Object System.Management.Automation.Host.ChoiceDescription '&Prerelease', "Prelease version $latestPrerelease"
		$versionQuery_opts = [System.Management.Automation.Host.ChoiceDescription[]]($versionQuery_stable, $versionQuery_prerelease)
		$versionQuery_result = $host.UI.PromptForChoice('Release Selection', "Which version would you like to install?`nEnter '?' to see versions.", $versionQuery_opts, 0)

		if ($versionQuery_result -eq 0) {
			$release = $latestStable
		}
		else {
			$release = $latestPrerelease
		}
	}
	else {
		$release = $latestStable
	}

	# Check if this project is already installed and, if so, whether it's the latest version.
	if (Test-Path $rootPath\$project) {
		$installedVersion = Get-Content -Raw "$rootPath\$project\resources\version.txt"
		If ($installedVersion -ge $release) {
			Write-Output "`n$project is already installed and up to date.`nExiting."
			Start-Sleep -Seconds 5
			exit
		}
		else {
			Write-Output "$project is already installed but it's out of date!"
			Write-Output "Please try the updater script in `"$rootPath\$project`" or download from https://github.com/tigattack/$project/releases."
		}
	}

	# Pull latest version of script from GitHub
	$DownloadParams = @{
		Uri     = "https://github.com/tigattack/$project/releases/download/$release/$project-$release.zip"
		OutFile = "$env:TEMP\$project-$release.zip"
	}
	Try {
		Write-Output "`nDownloading $project $release from GitHub..."
		Invoke-WebRequest @DownloadParams
	}
	catch {
		$downloadStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to download $project $release. Please check your internet connection and try again.`nStatus code: $downloadStatusCode"
		exit 1
	}
}

# Unblock downloaded ZIP
try {
	Write-Output 'Unblocking ZIP...'
	Unblock-File -Path "$env:TEMP\$project-$release.zip"
}
catch {
	Write-Warning 'Failed to unblock downloaded files. You will need to run the following commands manually once installation is complete:'
	Write-Output "Unblock-File -Path $rootPath\$project\*.ps*"
	Write-Output "Unblock-File -Path $rootPath\$project\resources\*.ps*"
}

# Extract release to destination path
Write-Output "Extracting files to '$rootPath'..."
Expand-Archive -Path "$env:TEMP\$project-$release.zip" -DestinationPath "$rootPath"

# Rename destination and tidy up
Write-Output "Renaming directory and tidying up...`n"
Rename-Item -Path "$rootPath\$project-$release" -NewName "$project"
Remove-Item -Path "$env:TEMP\$project-$release.zip"

# Get config
$config = Get-Content "$rootPath\$project\config\conf.json" -Raw | ConvertFrom-Json

# Prompt user with config options
$servicePrompt_discord = New-Object System.Management.Automation.Host.ChoiceDescription '&Discord', 'Send notifications to Discord.'
$servicePrompt_slack = New-Object System.Management.Automation.Host.ChoiceDescription '&Slack', 'Send notifications to Slack.'
$servicePrompt_teams = New-Object System.Management.Automation.Host.ChoiceDescription '&Teams', 'Send notifications to Teams.'
$servicePrompt_opts = [System.Management.Automation.Host.ChoiceDescription[]]($servicePrompt_discord, $servicePrompt_slack, $servicePrompt_teams)
$servicePrompt_result = $host.UI.PromptForChoice('Notification Service', 'Which service do you wish to send notifications to?', $servicePrompt_opts, -1)

Switch ($servicePrompt_result) {
	0 {
		$config.services.discord.user_id = 'Please enter your Discord user ID'
		$config.services.discord.webhook = Read-Host -Prompt 'Please enter your webhook URL'
	}
	1 {
		$config.services.slack.user_id = 'Please enter your Slack member ID'
		$config.services.slack.webhook = Read-Host -Prompt 'Please enter your webhook URL'
	}
	2 {
		$config.services.teams.user_id = 'Please enter your Teams email address'
		$config.services.teams.webhook = Read-Host -Prompt 'Please enter your webhook URL'
	}
}

$mentionPreference_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Do not mention me.'
$mentionPreference_warn = New-Object System.Management.Automation.Host.ChoiceDescription '&Warning', 'Mention me when a session finishes in a warning state.'
$mentionPreference_fail = New-Object System.Management.Automation.Host.ChoiceDescription '&Failure', 'Mention me when a session finishes in a failed state.'
$mentionPreference_warnfail = New-Object System.Management.Automation.Host.ChoiceDescription '&Both', 'Notify me when a session finishes in either a warning or a failed state.'
$mentionPreference_opts = [System.Management.Automation.Host.ChoiceDescription[]]($mentionPreference_no, $mentionPreference_warn, $mentionPreference_fail, $mentionPreference_warnfail)
$mentionPreference_message = 'Do you wish to be mentioned/tagged when a session finishes in one of the following states?'
$mentionPreference_result = $host.UI.PromptForChoice('Mention Preference', $mentionPreference_message, $mentionPreference_opts, 2)

If ($mentionPreference_result -ne 0) {
	Switch ($servicePrompt_result) {
		0 {
			$config.services.discord.user_id = 'Please enter your Discord user ID'
		}
		1 {
			$config.services.slack.user_id = 'Please enter your Slack member ID'
		}
		2 {
			$config.services.teams.user_id = 'Please enter your Teams email address'
			Write-Output "Teams also requires a name to be specified for mentions.`nIf you don't enter your name, your username (from your email address) will be used.`nIf you'd prefer this, type nothing and press enter."
			$config.services.teams.user_name = Read-Host -Prompt 'Please enter your name on Teams (e.g. John Smith)'
		}
	}
}

# Set config values
Switch ($mentionPreference_result) {
	0 {
		$config.mentions.on_fail = $false
		$config.mentions.on_warning = $false
	}
	1 {
		$config.mentions.on_fail = $false
		$config.mentions.on_warning = $true
	}
	2 {
		$config.mentions.on_fail = $true
		$config.mentions.on_warning = $false
	}
	3 {
		$config.mentions.on_fail = $true
		$config.mentions.on_warning = $true
	}
}

# Write config
Try {
	Write-Output "`nSetting configuration..."
	ConvertTo-Json $config | Set-Content "$rootPath\$project\config\conf.json"
	Write-Output "`nConfiguration set successfully. Configuration can be found in `"$rootPath\$project\config\conf.json`"."
}
catch {
	Write-Warning "Failed to write configuration file at `"$rootPath\$project\config\conf.json`". Please open the file and complete configuration manually."
}

Write-Output "`nInstallation complete!`n"

# Run configuration deployment script.
$configPrompt_yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes', 'Execute configuration deployment tool.'
$configPrompt_no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Skip configuration deployment tool.'
$configPrompt_opts = [System.Management.Automation.Host.ChoiceDescription[]]($configPrompt_yes, $configPrompt_no)
$configPrompt_result = $host.UI.PromptForChoice('Configuration Deployment Tool', "Would you like to to run the VeeamNotify configuration deployment tool?`nNone of your job configurations will be modified without confirmation.", $configPrompt_opts, 0)

If ($configPrompt_result -eq 0) {
	Write-Output "`nRunning configuration deployment script...`n"
	& "$rootPath\$project\resources\DeployVeeamConfiguration.ps1"
}
else {
	Write-Output 'Exiting.'
	Start-Sleep -Seconds 5
	exit
}
