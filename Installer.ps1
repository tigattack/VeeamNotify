#Requires -RunAsAdministrator

<#
TODO:
Offer to install the following:
latest prerelease
latest stable
a branch

Add params for every interactive prompt to allow automation of install

#>

# Support for passing a parameter to CLI to install using branch
[CmdletBinding(DefaultParameterSetName='None')]
param (
	[Parameter(ParameterSetName = 'Version', Position = 0, Mandatory = $true)]
	[ValidatePattern('^v(\d+\.)?(\d+\.)?(\*|\d+)$')]
	[String]$Version,

	[Parameter(ParameterSetName = 'Release', Position = 0, Mandatory = $true)]
	[ValidateSet('Latest', 'Prerelease')]
	[String]$Release,

	[Parameter(ParameterSetName = 'Branch', Position = 0, Mandatory = $true)]
	[String]$Branch,

	[Parameter(ParameterSetName = 'Version', Position = 1)]
	[Parameter(ParameterSetName = 'Release', Position = 1)]
	[Parameter(ParameterSetName = 'Branch', Position = 1)]
	[Switch]$NonInterative
)

# Prepare variables
$rootPath = 'C:\VeeamScripts'
$project = 'VeeamNotify'
$ErrorActionPreference = 'Stop'

Write-Output @'
#######################################
#                                     #
#        VeeamNotify Installer        #
#                                     #
#######################################


'@

# Check if this project is already installed and if so, exit
if (Test-Path $rootPath\$project) {
	$installedVersion = Get-Content -Raw "$rootPath\$project\resources\version.txt"
	Write-Output "$project ($installedVersion) is already installed. This script cannot update an existing installation."
	Write-Output 'Please manually update or delete/rename the existing installation and retry.'
}

# Download branch if specified
If ($Branch) {

	# Get branches from GitHub
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	try {
		$branches = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/branches" -Method Get
	}
	catch {
		$versionStatusCode = $_.Exception.Response.StatusCode.value__
		Write-Warning "Failed to query GitHub for project branches. Please check your internet connection and try again.`nStatus code: $versionStatusCode"
		exit 1
	}

	# Query if branch not found
	If (-not $NonInterative) {
		If (-not $branches.name.Contains($Branch)) {
			$unknownBranchQuery_main = New-Object System.Management.Automation.Host.ChoiceDescription '&Main', "'main' branch of VeeamNotify"
			$unknownBranchQuery_dev = New-Object System.Management.Automation.Host.ChoiceDescription '&Dev', "'dev' branch of VeeamNotify"
			$unknownBranchQuery_other = New-Object System.Management.Automation.Host.ChoiceDescription '&Other', 'Another branch of VeeamNotify'
			$unknownBranchQuery_opts = [System.Management.Automation.Host.ChoiceDescription[]]($unknownBranchQuery_main, $unknownBranchQuery_dev, $unknownBranchQuery_other)
			$unknownBranchQuery_result = $host.UI.PromptForChoice('Branch Selection', "Branch '$Branch' not found. Which branch would you like to install?", $unknownBranchQuery_opts, 0)

			Switch ($unknownBranchQuery_result) {
				0 {
					$Branch = 'main'
				}
				1 {
					$Branch = 'dev'
				}
				2 {
					$branchPrompt = 'Branch'
					do {
						$Branch = ($host.UI.Prompt('Branch Name', "You've chosen to install a different branch. Please enter the branch name.", $branchPrompt)).$branchPrompt
						If (-not $branches.name.Contains($Branch)) {
							Write-Warning "Branch '$Branch' not found. Please try again."
						}
					}
					until ($branches.name.Contains($Branch))
				}
			}
		}
	}
	Else {
		Write-Output "Branch '$Branch' not found. Will not prompt for branch in non-interactive mode.`n"
		exit
	}

	# Set $releaseName to branch name
	$releaseName = $Branch

	# Define download URL
	$downloadUrl = "https://github.com/tigattack/$project/archive/refs/heads/$Branch.zip"
}

# Otherwise work with versions
Else {
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

	# Parse latest release and latest prerelease
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

	# If no releases found, exit with notice
	If (-not $releases) {
		Write-Output "`nNo releases were found. Please re-run this script with the '-Branch <branch-name>' parameter."
		Write-Output 'NOTE: If you decide to install from a branch, please know you may be more likely to experience issues.'
		exit
	}

	# Define release to use
	If ($Release) {
		Switch ($Release) {
			'Latest' {
				$releaseName = $latestStable
			}
			'Prerelease' {
				$releaseName = $latestPrerelease
			}
		}
	}
	ElseIf ($Version) {
		$releaseName = $Version
	}
	Else {
		$releasePrompt = $true
		# Query release stream
		$versionQuery_stable = New-Object System.Management.Automation.Host.ChoiceDescription 'Latest &stable', "Latest stable version $latestStable"
		$versionQuery_prerelease = New-Object System.Management.Automation.Host.ChoiceDescription 'Latest &prerelease', "Latest prelease version $latestPrerelease"
		$versionQuery_opts = [System.Management.Automation.Host.ChoiceDescription[]]($versionQuery_stable, $versionQuery_prerelease)
		$versionQuery_result = $host.UI.PromptForChoice('Release Selection', "Which release type would you like to install?`nEnter '?' to see versions.", $versionQuery_opts, 0)

		If ($versionQuery_result -eq 0) {
			$releaseName = $latestStable
		}
		Else {
			$releaseName = $latestPrerelease
		}
	}

	# If release not found, exit with notice
	If ($Version -and (-not $releases.tag_names -contains $Version)) {
		Write-Warning "The specified release could not found. Valid releases are:`n$($releases.tag_name)"
		exit
	}
	If (($Release -or $releasePrompt) -and (-not $releaseName)) {
		Write-Warning 'A release of the specified type could not found.'
		exit
	}

	# Define download URL
	$downloadUrl = "https://github.com/tigattack/$project/releases/download/$releaseName/$project-$releaseName.zip"
}

# Download project from GitHub
$DownloadParams = @{
	Uri     = $downloadUrl
	OutFile = "$env:TEMP\$project-$releaseName.zip"
}
Try {
	Write-Output "`nDownloading $project $releaseName from GitHub..."
	Invoke-WebRequest @DownloadParams
}
catch {
	$downloadStatusCode = $_.Exception.Response.StatusCode.value__
	Write-Warning "Failed to download $project $releaseName. Please check your internet connection and try again.`nStatus code: $downloadStatusCode"
	exit 1
}

# Unblock downloaded ZIP
try {
	Write-Output 'Unblocking ZIP...'
	Unblock-File -Path "$env:TEMP\$project-$releaseName.zip"
}
catch {
	Write-Warning 'Failed to unblock downloaded files. You will need to run the following commands manually once installation is complete:'
	Write-Output "Unblock-File -Path $rootPath\$project\*.ps*"
	Write-Output "Unblock-File -Path $rootPath\$project\resources\*.ps*"
}

# Extract release to destination path
Write-Output "Extracting files to '$rootPath'..."
Expand-Archive -Path "$env:TEMP\$project-$releaseName.zip" -DestinationPath "$rootPath"

# Rename destination and tidy up
Write-Output "Renaming directory and tidying up...`n"
Rename-Item -Path "$rootPath\$project-$releaseName" -NewName "$project"
Remove-Item -Path "$env:TEMP\$project-$releaseName.zip"

If (-not $NonInterative) {
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
			$config.services.discord.webhook = Read-Host -Prompt 'Please enter your webhook URL'
		}
		1 {
			$config.services.slack.webhook = Read-Host -Prompt 'Please enter your webhook URL'
		}
		2 {
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
				$config.services.discord.user_id = Read-Host -Prompt 'Please enter your Discord user ID'
			}
			1 {
				$config.services.slack.user_id = Read-Host -Prompt 'Please enter your Slack member ID'
			}
			2 {
				$config.services.teams.user_id = Read-Host -Prompt 'Please enter your Teams email address'
				Write-Output "Teams also requires a name to be specified for mentions.`nIf you do not specify anything, your username (from your email address) will be used."
				$config.services.teams.user_name = Read-Host -Prompt 'Please enter your name on Teams (e.g. John Smith)'
			}
		}
	}

	# Set config values
	Switch ($mentionPreference_result) {
		0 {
			$config.mentions.on_failure = $false
			$config.mentions.on_warning = $false
		}
		1 {
			$config.mentions.on_failure = $false
			$config.mentions.on_warning = $true
		}
		2 {
			$config.mentions.on_failure = $true
			$config.mentions.on_warning = $false
		}
		3 {
			$config.mentions.on_failure = $true
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
}
Else {
	Write-Output "`nWill not prompt for service and mention configuration in non-interactive mode.`n"
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
