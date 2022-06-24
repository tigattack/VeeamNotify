Describe 'Installer.ps1' {
	BeforeAll {
		# Define project name
		$project = 'VeeamNotify'

		# Create temp install dir
		$installDir = New-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'test-install') -Type Directory -Force

		# Get installer path
		$installerPath = (Get-ChildItem -Path (Split-Path -Path $PSScriptRoot -Parent) -Filter 'Installer.ps1').FullName

		# Define installer params
		$installerParams = @{
			NonInteractive    = $true
			InstallParentPath = $installDir
		}

		# Define required files
		$expectedFiles = @(
			'Bootstrap.ps1',
			'AlertSender.ps1'
		)
		$expectedFiles += $(
			foreach ($dir in 'resources', 'config') {
				$files = Get-ChildItem -Path "$(Split-Path -Path $PSScriptRoot -Parent)\$dir"
				foreach ($file in $files) {
					[string](Join-Path -Path $file.Directory.Name -ChildPath $file.Name)
				}
			}
		)

		# Define required files check
		[scriptblock]$expectedFilesCheck = {
			foreach ($file in $expectedFiles) {
				Join-Path -Path "$installDir\$project" -ChildPath $file | Should -Exist
			}
		}

		# Get releases
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		$releases = Invoke-RestMethod -Uri "https://api.github.com/repos/tigattack/$project/releases" -Method Get
	}

	It 'Install from specific version' -Skip:(-not $releases) {
		# Run installer
		& $installerPath -Version 'v1.0' @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from latest release' -Skip:(-not $releases) {
		# Run installer
		& $installerPath -Latest Release @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	It 'Install from branch' {
		# Run installer
		& $installerPath -Branch dev @installerParams

		# Check for expected files
		Invoke-Command -ScriptBlock $expectedFilesCheck
	}

	AfterEach {
		# Remove temp install dir
		Remove-Item -Path $installDir -Recurse -Force
	}
}
