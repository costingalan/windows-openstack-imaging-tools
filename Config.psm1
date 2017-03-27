# Copyright 2017 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$localResourcesDir = "$scriptPath\UnattendResources"
Import-Module "$localResourcesDir\ini.psm1"

function Get-availableConfigOptionOptions {
    return @(
        @{"Name" = "wim_file_path"; "DefaultValue" = "D:\Sources\install.wim";
          "Description" = "The location of the WIM file from the Windows ISO."},
        @{"Name" = "image_name"; "DefaultValue" = "Windows Server 2012 R2 SERVERSTANDARD";
          "Description" = "This is the object which contains all the information about the Windows flavor selected."},
        @{"Name" = "image_path"; "DefaultValue" = "${ENV:TEMP}\win-image.vhdx";
          "Description" = "The destination of the generated image."},
        @{"Name" = "virtual_disk_format"; "DefaultValue" = "VHDX";
          "Description" = "Select between VHD, VHDX, QCow2, VMDK or RAW formats."},
        @{"Name" = "image_type"; "DefaultValue" = "HYPER-V";
          "Description" = "This parameter allows to choose between MAAS, KVM and Hyper-V specific images."},
        @{"Name" = "disk_layout"; "DefaultValue" = "BIOS";
          "Description" = "This parameter can be set to either BIOS or UEFI."},
        @{"Name" = "product_key";
          "Description" = "The product key for the OS selected."},
        @{"Name" = "extra_features";
          "Description" = "Name of the extra features to enable on the generated image.
                           The $ExtraFeatures need be present in the ISO file."},
        @{"Name" = "force"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "It will force the image generation when $RunSysprep is $False or the selected $SwitchName
                           is not an external one. Use this parameter with caution because it can easily generate
                           unstable images."},
        @{"Name" = "install_maas_hooks"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "If set to true, MaaSHooks will be installed."},
        @{"Name" = "zip_password";
          "Description" = "This parameter allows to create a password protected zip from the generated image."},
        @{"Name" = "administrator_password"; "GroupName" = "vm"; "DefaultValue" = "Pa`$`$w0rd";
          "Description" = "Is used by the script to auto-login in the instance while it is generating."},
        @{"Name" = "external_switch"; "GroupName" = "vm"; "DefaultValue" = "external";
          "Description" = "Used to specify the virtual switch the VM will be using to connect to the internet.
                           If none is specified, one will be created."},
        @{"Name" = "cpu_count"; "GroupName" = "vm"; "DefaultValue" = "1";
          "Description" = "The number of CPU cores assigned to the VM used to generate the image."},
        @{"Name" = "ram_size"; "GroupName" = "vm"; "DefaultValue" = "2147483648";
          "Description" = "RAM assigned to the VM used to generate the image."},
        @{"Name" = "disk_size"; "GroupName" = "vm"; "DefaultValue" = "42949672960";
          "Description" = "Disk space assigned to the VM used to generate the image."},
        @{"Name" = "virtio_iso_path"; "GroupName" = "drivers";
          "Description" = "The path to the ISO file containing the VirtIO drivers."},
        @{"Name" = "virtio_base_path"; "GroupName" = "drivers";
          "Description" = "The drive letter of the mounted VirtIO drivers ISO file."},
        @{"Name" = "drivers_path"; "GroupName" = "drivers";
          "Description" = "The location of the drivers files."},
        @{"Name" = "install_updates"; "GroupName" = "updates"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "If set to true, the latest updates will be downloaded and installed."},
        @{"Name" = "purge_updates"; "GroupName" = "updates"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "If set to true, will run DISM with /resetbase option. This will reduce the size of
                           WinSXS folder, but after that Windows updates cannot be uninstalled."},
        @{"Name" = "run_sysprep"; "GroupName" = "sysprep"; "DefaultValue" = $true; "AsBoolean" = $true;
          "Description" = "Used to clean the OS on the VM, and to prepare it for a first-time use."},
        @{"Name" = "unattend_xml_path"; "GroupName" = "sysprep"; "DefaultValue" = "UnattendTemplate.xml";
          "Description" = "The path to the Unattend XML template file."},
        @{"Name" = "disable_swap"; "GroupName" = "sysprep"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "DisableSwap option will disable the swap when the image is generated and will add a setting
                           in the Unattend.xml file which will enable swap at boot time during specialize step.
                           This is required as by default, the amount of swap space on Windows machine is directly
                           proportional to the RAM size and if the image has in the initial stage low disk space,
                           the first boot will fail due to not enough disk space. The swap is set to the default
                           automatic setting right after the resize of the partitions is performed by cloudbase-init."},
        @{"Name" = "persist_drivers_install"; "GroupName" = "sysprep"; "DefaultValue" = $true; "AsBoolean" = $true;
          "Description" = "In case the hardware on which the image is generated will also be the hardware on
                           which the image will be deployed this can be set to true, otherwise the spawned
                           instance is prone to BSOD."},
        @{"Name" = "beta_release"; "GroupName" = "cloudbase_init"; "DefaultValue" = $false; "AsBoolean" = $true;
          "Description" = "This is a switch that allows the selection of Cloudbase-Init branches. If set to true, the
                           beta branch will be used, otherwise the stable branch will be used."}
    )
}

function Get-WindowsImageConfig {
    param([parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )
    $fullConfigFilePath = Resolve-Path $ConfigFilePath -ErrorAction SilentlyContinue
    if (!$fullConfigFilePath -or (-not (Test-Path $fullConfigFilePath))) {
        Write-Warning ("Config file {0} does not exist." -f $configFilePath)
    }
    $winImageConfig = @{}
    $availableConfigOptionOptions = Get-availableConfigOptionOptions
    foreach($availableConfigOption in $availableConfigOptionOptions) {
        try {
            $groupName = "DEFAULT"
            $asBoolean = $false
            if ($availableConfigOption['GroupName']) {
                $groupName = $availableConfigOption['GroupName']
            }
            if ($availableConfigOption['AsBoolean']) {
                $asBoolean = $availableConfigOption['AsBoolean']
            }
            $value = Get-IniFileValue -Path $fullConfigFilePath -Section $groupName `
                                      -Key $availableConfigOption['Name'] `
                                      -Default $availableConfigOption['DefaultValue'] `
                                      -AsBoolean:$asBoolean
        } catch {
            $value = $availableConfigOption['DefaultValue']
        }
        $winImageConfig += @{$availableConfigOption['Name'] = $value}
    }
    return $winImageConfig
}
function Set-IniComment {
    param
    (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Key,
        [parameter()]
        [string]$Section = "DEFAULT",
        [parameter(Mandatory=$false)]
        [string]$Description,
        [parameter(Mandatory=$true)]
        [string]$Path
    )

    $content = Get-Content $Path
    $index = 0
    $descriptionContent = "# $Description"
    foreach ($line in $content) {
        if ($Description -and $line.StartsWith($Key) -and ($content[$index -1] -ne $descriptionContent)) {
            $content = $content[0..($index -1)], $descriptionContent, $content[$index..($content.Length -1)]
            break
        }
        $index += 1
    }
    Set-Content -Value $content -Path $ConfigFilePath -Encoding ASCII
}

function New-WindowsImageConfig {
    param([parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )
    if (Test-Path $ConfigFilePath) {
        Write-Warning "$ConfigFilePath exists and it will be rewritten."
    } else {
        New-Item -ItemType File -Path $ConfigFilePath
    }

    $fullConfigFilePath = Resolve-Path $ConfigFilePath -ErrorAction SilentlyContinue
    $availableConfigOptionOptions = Get-AvailableConfigOptionOptions
    foreach($availableConfigOption in $availableConfigOptionOptions) {
        try {
            $groupName = "DEFAULT"
            $asBoolean = $false
            if ($availableConfigOption['GroupName']) {
                $groupName = $availableConfigOption['GroupName']
            }
            if ($availableConfigOption['AsBoolean']) {
                $asBoolean = $availableConfigOption['AsBoolean']
            }
            $value = Set-IniFileValue -Path $fullConfigFilePath -Section $groupName `
                                      -Key $availableConfigOption['Name'] `
                                      -Value $availableConfigOption['DefaultValue']
            Set-IniComment -Path $fullConfigFilePath -Key $availableConfigOption['Name'] `
                           -Description $availableConfigOption['Description']
        } catch {
            Write-Warning ("Config option {0} could not be written." -f @($availableConfigOption['Name']))
        }
        $winImageConfig += @{$availableConfigOption['Name'] = $value}
    }
}

Export-ModuleMember Get-WindowsImageConfig, New-WindowsImageConfig
