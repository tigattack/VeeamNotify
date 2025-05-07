param (
	[Parameter(ParameterSetName = 'Branch')]
	[Parameter(ParameterSetName = 'PR')]
	[string]$Branch,
	[Parameter(ParameterSetName = 'PR')]
	[switch]$IsPr,
	[Parameter(Mandatory, ParameterSetName = 'PR')]
	[int]$PrId
)

Describe 'Installer.ps1' {
	BeforeAll {
		# Use TestDrive for installation directory
		$installDir = (Join-Path -Path $TestDrive -ChildPath 'VeeamNotifyInstall')
		New-Item -Path $installDir -ItemType Directory -Force | Out-Null

		# Get installer path
		$installerPath = (Get-ChildItem -Path (Split-Path -Path $PSScriptRoot -Parent) -Filter 'Installer.ps1').FullName

		# Define installer params
		$installerParams = @{
			NonInteractive    = $true
			InstallParentPath = $installDir
		}

		# Define required files
		$expectedFiles = @(
			'.\Bootstrap.ps1',
			'.\AlertSender.ps1'
		)
		$expectedFiles += $(
			foreach ($dir in 'resources', 'config') {
				$files = Get-ChildItem -Path "$(Split-Path -Path $PSScriptRoot -Parent)\$dir" -File -Recurse
				foreach ($file in $files) {
					[string]($file | Resolve-Path -Relative)
				}
			}
		)

		# Define required files check
		[scriptblock]$expectedFilesCheck = {
			foreach ($file in $expectedFiles) {
				Join-Path -Path "$installDir" -ChildPath 'VeeamNotify' | Join-Path -ChildPath $file | Should -Exist
			}
		}
	}

	It 'Install from specific version' {
		$defaultVersion = 'v1.1.1'
		Write-Host "Installing from version: $defaultVersion"
		# Run installer
		& $installerPath -Version $defaultVersion @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from latest release' {
		Write-Host 'Installing from latest release'
		# Run installer
		& $installerPath -Latest Release @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from current branch' -Skip:($IsPr -or [string]::IsNullOrWhitespace($Branch)) {
		Write-Host "Installing from branch: $Branch"
		# Call installer with branch parameter
		& $installerPath -Branch $Branch @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from PR' -Skip:(-not $IsPr) {
		Write-Host "Installing from PR #$PrId"
		# Call installer with PR parameter
		& $installerPath -PullRequest $PrId @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	AfterEach {
		# Remove temp install dir
		Remove-Item -Path $installDir -Recurse -Force
	}
}
