<#
.SYNOPSIS
    Modern WPF GUI for managing Windows 11 Mobile Hotspot (Toggle, SSID, Password, Frequency Band, Connected Devices).
.NOTES
    Requires Windows PowerShell 5.1 (built into Windows 11) with Administrator privileges.
#>

# ==============================================================================
# 1. AUTO-ELEVATION & STA THREAD ENFORCEMENT
# ==============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$isSTA   = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'

if (-not $isAdmin -or -not $isSTA) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    if (-not $scriptPath) {
        Write-Warning "Please save this script as a .ps1 file before running."
        exit
    }
    $powershellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $powershellExe)) { $powershellExe = "powershell.exe" }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $powershellExe
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$scriptPath`""
    $psi.Verb      = "RunAs"
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show("Administrator privileges are required to manage Mobile Hotspot settings.", "Elevation Cancelled", "OK", "Warning")
    }
    exit
}

# ==============================================================================
# 2. LOAD ASSEMBLIES & WINRT RUNTIME TYPES
# ==============================================================================
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Load WinRT Tethering & Connectivity Namespaces
$null = [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringAccessPointConfiguration, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringClient, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]
$null = [Windows.Networking.NetworkOperators.TetheringWiFiBand, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime]

# ==============================================================================
# 3. WINRT ASYNC HELPER FUNCTIONS
# ==============================================================================
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction'
})[0]

function Await-WinRtOperation {
    param($WinRtTask, [Type]$ResultType)
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait()
    return $netTask.Result
}

function Await-WinRtAction {
    param($WinRtAction)
    $netTask = $asTaskAction.Invoke($null, @($WinRtAction))
    $netTask.Wait()
}

# ==============================================================================
# 4. MODERN DARK-THEME WPF XAML DEFINITION (SIDE-BY-SIDE DASHBOARD)
# ==============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Win11 Mobile Hotspot" Width="750"
        SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#18181B" Foreground="#F4F4F5" FontFamily="Segoe UI">
    <Window.Resources>
        <!-- Modern Rounded TextBox -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#3B82F6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Rounded PasswordBox -->
        <Style TargetType="PasswordBox">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="CaretBrush" Value="#3B82F6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Dark ComboBox ToggleButton Template -->
        <ControlTemplate x:Key="ComboBoxToggleButton" TargetType="ToggleButton">
            <Border x:Name="templateRoot" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="6">
                <Border x:Name="splitBorder" Width="28" HorizontalAlignment="Right">
                    <Path x:Name="arrow" Data="M 0 0 L 4 4 L 8 0 Z"
                          Fill="#A1A1AA" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
            </Border>
            <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter TargetName="templateRoot" Property="Background" Value="#323238"/>
                    <Setter TargetName="templateRoot" Property="BorderBrush" Value="#3B82F6"/>
                    <Setter TargetName="arrow" Property="Fill" Value="#FFFFFF"/>
                </Trigger>
                <Trigger Property="IsChecked" Value="True">
                    <Setter TargetName="templateRoot" Property="BorderBrush" Value="#3B82F6"/>
                    <Setter TargetName="arrow" Property="Fill" Value="#3B82F6"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter TargetName="templateRoot" Property="Opacity" Value="0.45"/>
                </Trigger>
            </ControlTemplate.Triggers>
        </ControlTemplate>

        <!-- Modern Dark ComboBox Style & ControlTemplate -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="toggleButton"
                                          Template="{StaticResource ComboBoxToggleButton}"
                                          Background="{TemplateBinding Background}"
                                          BorderBrush="{TemplateBinding BorderBrush}"
                                          BorderThickness="{TemplateBinding BorderThickness}"
                                          Focusable="False"
                                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"/>
                            <ContentPresenter x:Name="contentPresenter"
                                              Content="{TemplateBinding SelectionBoxItem}"
                                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                              ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                              Margin="12,0,32,0"
                                              HorizontalAlignment="Left"
                                              VerticalAlignment="Center"
                                              IsHitTestVisible="False">
                                <TextBlock.Foreground>
                                    <SolidColorBrush Color="#F4F4F5"/>
                                </TextBlock.Foreground>
                            </ContentPresenter>
                            <Popup x:Name="PART_Popup"
                                   AllowsTransparency="True"
                                   IsOpen="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}}"
                                   Placement="Bottom"
                                   PopupAnimation="Slide"
                                   Focusable="False">
                                <Border x:Name="dropDownBorder"
                                        MinWidth="{Binding ActualWidth, ElementName=toggleButton}"
                                        MaxHeight="{TemplateBinding MaxDropDownHeight}"
                                        Background="#202024"
                                        BorderBrush="#3F3F46"
                                        BorderThickness="1"
                                        CornerRadius="6"
                                        Margin="0,4,0,0">
                                    <ScrollViewer x:Name="DropDownScrollViewer" Margin="0,4">
                                        <ItemsPresenter x:Name="ItemsPresenter" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Dark ComboBoxItem Style -->
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="itemBorder"
                                Background="{TemplateBinding Background}"
                                Padding="{TemplateBinding Padding}"
                                Margin="4,1"
                                CornerRadius="4">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsHighlighted" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="#3B82F6"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="itemBorder" Property="Background" Value="#2563EB"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#71717A"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Primary Button -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#3B82F6"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="14,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Opacity" Value="0.75"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button -->
        <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#27272A"/>
            <Setter Property="Foreground" Value="#E4E4E7"/>
        </Style>
    </Window.Resources>

    <Grid Margin="20">
        <Grid.ColumnDefinitions>
            <!-- Left Column: Controls & Configuration -->
            <ColumnDefinition Width="360"/>
            <!-- Column Separator Spacer -->
            <ColumnDefinition Width="16"/>
            <!-- Right Column: Connected Devices Panel -->
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- ================= LEFT COLUMN ================= -->
        <Grid Grid.Column="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- 0. Header & Status Pill -->
            <Grid Grid.Row="0" Margin="0,0,0,16">
                <StackPanel Orientation="Vertical" HorizontalAlignment="Left">
                    <TextBlock Text="Mobile Hotspot" FontSize="20" FontWeight="Bold" Foreground="#FFFFFF"/>
                    <TextBlock x:Name="TxtSubInfo" Text="Share internet connection" FontSize="12" Foreground="#A1A1AA" Margin="0,2,0,0"/>
                </StackPanel>

                <Border x:Name="StatusBadge" Background="#27272A" CornerRadius="12" Padding="12,5" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="#EF4444" Margin="0,0,7,0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="TxtStatus" Text="OFF" FontSize="12" FontWeight="Bold" Foreground="#EF4444" VerticalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </Grid>

            <!-- 1. Main Toggle Action -->
            <Button x:Name="BtnToggle" Grid.Row="1" Content="Turn On Mobile Hotspot" Style="{StaticResource ModernButton}" Height="40" Margin="0,0,0,14"/>

            <!-- 2. Configuration Card -->
            <Border Grid.Row="2" Background="#202024" BorderBrush="#2E2E34" BorderThickness="1" CornerRadius="10" Padding="16">
                <StackPanel>
                    <!-- Network Name (SSID) -->
                    <TextBlock Text="Network Name (SSID)" FontSize="12" Foreground="#A1A1AA" Margin="0,0,0,6"/>
                    <TextBox x:Name="TxtSsid" MaxLength="32" Margin="0,0,0,12"/>

                    <!-- Network Password -->
                    <Grid Margin="0,0,0,6">
                        <TextBlock Text="Network Password (8-63 chars)" FontSize="12" Foreground="#A1A1AA" HorizontalAlignment="Left"/>
                        <CheckBox x:Name="ChkShowPass" Content="Show" Foreground="#A1A1AA" FontSize="11" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                    </Grid>
                    <Grid Margin="0,0,0,12">
                        <PasswordBox x:Name="PwdBox"/>
                        <TextBox x:Name="TxtPassVisible" Visibility="Collapsed"/>
                    </Grid>

                    <!-- Network Band -->
                    <TextBlock Text="Network Band" FontSize="12" Foreground="#A1A1AA" Margin="0,0,0,6"/>
                    <ComboBox x:Name="CmbBand" Height="36"/>
                </StackPanel>
            </Border>

            <!-- 3. Footer Save & Refresh -->
            <Grid Grid.Row="3" Margin="0,14,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Button x:Name="BtnRefresh" Grid.Column="0" Content="Refresh" Style="{StaticResource SecondaryButton}" Width="85" Height="38" Margin="0,0,10,0"/>
                <Button x:Name="BtnSave" Grid.Column="1" Content="Save &amp; Apply Changes" Style="{StaticResource SecondaryButton}" Height="38"/>
            </Grid>
        </Grid>

        <!-- ================= RIGHT COLUMN (CONNECTED DEVICES) ================= -->
        <Border Grid.Column="2" Background="#202024" BorderBrush="#2E2E34" BorderThickness="1" CornerRadius="10" Padding="16">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <!-- Header of Devices Panel -->
                <Grid Grid.Row="0" Margin="0,0,0,12">
                    <StackPanel Orientation="Vertical">
                        <TextBlock Text="Connected Devices" FontSize="14" FontWeight="Bold" Foreground="#FFFFFF"/>
                        <TextBlock Text="Live client activity on hotspot" FontSize="11" Foreground="#A1A1AA" Margin="0,2,0,0"/>
                    </StackPanel>

                    <Border Background="#27272A" CornerRadius="10" Padding="10,4" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <TextBlock x:Name="TxtClientCountBadge" Text="0 of 8" FontSize="12" Foreground="#3B82F6" FontWeight="Bold"/>
                    </Border>
                </Grid>

                <!-- Scrollable Device List Container -->
                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,4,0,0">
                    <StackPanel>
                        <!-- Devices Stack -->
                        <StackPanel x:Name="DevicesPanel"/>

                        <!-- Empty State message -->
                        <TextBlock x:Name="TxtNoDevices" Text="No devices currently connected" FontSize="12" Foreground="#71717A" HorizontalAlignment="Center" Margin="0,24,0,0"/>
                    </StackPanel>
                </ScrollViewer>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

# ==============================================================================
# 5. PARSE XAML & BIND CONTROLS
# ==============================================================================
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$TxtSubInfo          = $window.FindName("TxtSubInfo")
$StatusDot           = $window.FindName("StatusDot")
$TxtStatus           = $window.FindName("TxtStatus")
$BtnToggle           = $window.FindName("BtnToggle")
$TxtSsid             = $window.FindName("TxtSsid")
$ChkShowPass         = $window.FindName("ChkShowPass")
$PwdBox              = $window.FindName("PwdBox")
$TxtPassVisible      = $window.FindName("TxtPassVisible")
$CmbBand             = $window.FindName("CmbBand")
$DevicesPanel        = $window.FindName("DevicesPanel")
$TxtClientCountBadge = $window.FindName("TxtClientCountBadge")
$TxtNoDevices        = $window.FindName("TxtNoDevices")
$BtnRefresh          = $window.FindName("BtnRefresh")
$BtnSave             = $window.FindName("BtnSave")

# ==============================================================================
# 6. HOTSPOT CONTROLLER FUNCTIONS
# ==============================================================================
function Get-TetheringManager {
    $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if (-not $profile) {
        return $null
    }
    return [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
}

function Get-FriendlyErrorMessage {
    param($Status, $BandTag)

    switch ($Status) {
        "RadioRestriction" {
            return "Radio Restriction. Your Wi-Fi adapter cannot broadcast on '$BandTag' while connected to the current Wi-Fi network (or due to regional band restrictions).`n`nRecommendation: Switch to 'Any Available (Auto)' or match your upstream Wi-Fi band."
        }
        "BandInterference" {
            return "Band Interference. The selected band conflicts with current radio traffic. Try 'Any Available (Auto)' or switch to 2.4 GHz."
        }
        "WiFiDeviceOff" {
            return "Wi-Fi is turned off on your system. Please turn Wi-Fi on in Windows settings."
        }
        "OperationInProgress" {
            return "The wireless adapter is busy transitioning states. Please wait a moment and try again."
        }
        "NetworkLimitedConnectivity" {
            return "The internet connection has limited or no connectivity."
        }
        Default {
            return "Operation failed with status: $Status"
        }
    }
}

function Populate-BandOptions {
    param($manager, $config)

    $currentSelectionTag = if ($CmbBand.SelectedItem) { $CmbBand.SelectedItem.Tag } else { $null }
    $configBandTag = $config.Band.ToString()

    $CmbBand.Items.Clear()

    $bandDefs = @(
        @{ Name = "Auto"; Label = "Any Available (Auto)" },
        @{ Name = "TwoPointFourGigahertz"; Label = "2.4 GHz" },
        @{ Name = "FiveGigahertz"; Label = "5 GHz" },
        @{ Name = "SixGigahertz"; Label = "6 GHz (Wi-Fi 6E/7)" }
    )

    $itemToSelect = $null
    $firstEnabled = $null

    foreach ($def in $bandDefs) {
        $bandEnum = [Windows.Networking.NetworkOperators.TetheringWiFiBand]::($def.Name)
        $isSupported = $false
        try {
            $isSupported = Await-WinRtOperation ($config.IsBandSupportedAsync($bandEnum)) ([System.Boolean])
        } catch {
            $isSupported = $false
        }

        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Tag = $def.Name

        if ($isSupported) {
            $item.Content = $def.Label
            $item.IsEnabled = $true
            if (-not $firstEnabled) { $firstEnabled = $item }
        } else {
            $item.Content = "$($def.Label) (Unsupported)"
            $item.IsEnabled = $false
        }

        $null = $CmbBand.Items.Add($item)

        if ($def.Name -eq $configBandTag -and $isSupported) {
            $itemToSelect = $item
        }
    }

    if ($itemToSelect) {
        $CmbBand.SelectedItem = $itemToSelect
    } elseif ($firstEnabled) {
        $CmbBand.SelectedItem = $firstEnabled
    }
}

function Update-ConnectedDevices {
    param($manager)

    $DevicesPanel.Children.Clear()

    if (-not $manager -or $manager.TetheringOperationalState.ToString() -ne "On") {
        $maxClients = if ($manager) { $manager.MaxClientCount } else { 8 }
        $TxtClientCountBadge.Text = "0 of $maxClients"
        $TxtNoDevices.Text = "Hotspot is turned off"
        $TxtNoDevices.Visibility = "Visible"
        return
    }

    $clients = @($manager.GetTetheringClients())
    $count = $clients.Count
    $maxCount = $manager.MaxClientCount
    $TxtClientCountBadge.Text = "$count of $maxCount"

    if ($count -eq 0) {
        $TxtNoDevices.Text = "No devices currently connected"
        $TxtNoDevices.Visibility = "Visible"
        return
    }

    $TxtNoDevices.Visibility = "Collapsed"

    # Pre-parse ARP table for DHCP IP mapping fallback
    $arpTable = @{}
    try {
        $arpLines = arp -a
        foreach ($line in $arpLines) {
            if ($line -match '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s+([0-9a-fA-F-]+)\s+dynamic') {
                $normMac = $matches[2].Replace('-', ':').ToLower()
                $arpTable[$normMac] = $matches[1]
            }
        }
    } catch {}

    $deviceIndex = 1
    foreach ($client in $clients) {
        $mac = if ($client.MacAddress) { $client.MacAddress } else { "Unknown MAC" }
        $normMac = $mac.ToLower()

        $devName = ""
        $ipAddr = ""

        # Extract HostNames from WinRT
        if ($client.HostNames) {
            foreach ($hn in $client.HostNames) {
                if ($hn.Type.ToString() -eq "Ipv4" -or $hn.DisplayName -match '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') {
                    if (-not $ipAddr) { $ipAddr = $hn.DisplayName }
                } else {
                    if (-not $devName) { $devName = $hn.DisplayName }
                }
            }
        }

        # ARP fallback if IP was not extracted
        if (-not $ipAddr -and $arpTable.ContainsKey($normMac)) {
            $ipAddr = $arpTable[$normMac]
        }
        if (-not $ipAddr) {
            $ipAddr = "IP Assigned (DHCP)"
        }

        if (-not $devName) {
            $devName = "Device #$deviceIndex"
        }

        # Build Card for this client
        $cardBorder = New-Object System.Windows.Controls.Border
        $cardBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#27272A")
        $cardBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#3F3F46")
        $cardBorder.BorderThickness = [System.Windows.Thickness]::new(1)
        $cardBorder.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $cardBorder.Padding = [System.Windows.Thickness]::new(10, 8, 10, 8)
        $cardBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

        $grid = New-Object System.Windows.Controls.Grid
        $col0 = New-Object System.Windows.Controls.ColumnDefinition
        $col0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition
        $col1.Width = [System.Windows.GridLength]::Auto
        $grid.ColumnDefinitions.Add($col0)
        $grid.ColumnDefinitions.Add($col1)

        $leftStack = New-Object System.Windows.Controls.StackPanel
        $nameBlock = New-Object System.Windows.Controls.TextBlock
        $nameBlock.Text = $devName
        $nameBlock.FontSize = 13
        $nameBlock.FontWeight = [System.Windows.FontWeights]::SemiBold
        $nameBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F4F4F5")

        $detailsBlock = New-Object System.Windows.Controls.TextBlock
        $detailsBlock.Text = "$ipAddr  •  $mac"
        $detailsBlock.FontSize = 11
        $detailsBlock.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A1A1AA")
        $detailsBlock.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)

        $leftStack.Children.Add($nameBlock)
        $leftStack.Children.Add($detailsBlock)
        [System.Windows.Controls.Grid]::SetColumn($leftStack, 0)
        $grid.Children.Add($leftStack)

        $badgeBorder = New-Object System.Windows.Controls.Border
        $badgeBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#14532D")
        $badgeBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $badgeBorder.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
        $badgeBorder.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $badgeText = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text = "Online"
        $badgeText.FontSize = 10
        $badgeText.FontWeight = [System.Windows.FontWeights]::Bold
        $badgeText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80")
        $badgeBorder.Child = $badgeText

        [System.Windows.Controls.Grid]::SetColumn($badgeBorder, 1)
        $grid.Children.Add($badgeBorder)

        $cardBorder.Child = $grid
        $null = $DevicesPanel.Children.Add($cardBorder)
        $deviceIndex++
    }
}

function Update-UIState {
    $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
    if (-not $profile) {
        $TxtStatus.Text = "NO INTERNET"
        $TxtStatus.Foreground = "#F59E0B"
        $StatusDot.Fill = "#F59E0B"
        $TxtSubInfo.Text = "Connect to a network first to share it"
        $BtnToggle.IsEnabled = $false
        $BtnSave.IsEnabled = $false
        Update-ConnectedDevices $null
        return
    }

    $manager = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
    if (-not $manager) {
        $TxtStatus.Text = "UNAVAILABLE"
        $TxtStatus.Foreground = "#EF4444"
        $StatusDot.Fill = "#EF4444"
        $TxtSubInfo.Text = "Mobile Hotspot is not supported on this adapter"
        $BtnToggle.IsEnabled = $false
        $BtnSave.IsEnabled = $false
        Update-ConnectedDevices $null
        return
    }

    $BtnToggle.IsEnabled = $true
    $BtnSave.IsEnabled = $true

    # Read Operational State
    $state = $manager.TetheringOperationalState.ToString()
    $clients = $manager.ClientCount
    $maxClients = $manager.MaxClientCount

    if ($state -eq "On") {
        $TxtStatus.Text = "ACTIVE"
        $TxtStatus.Foreground = "#22C55E"
        $StatusDot.Fill = "#22C55E"
        $TxtSubInfo.Text = "Sharing '$($profile.ProfileName)' | Devices: $clients / $maxClients"
        $BtnToggle.Content = "Turn Off Mobile Hotspot"
        $BtnToggle.Background = "#DC2626"
    } else {
        $TxtStatus.Text = "OFF"
        $TxtStatus.Foreground = "#EF4444"
        $StatusDot.Fill = "#EF4444"
        $TxtSubInfo.Text = "Ready to share '$($profile.ProfileName)'"
        $BtnToggle.Content = "Turn On Mobile Hotspot"
        $BtnToggle.Background = "#3B82F6"
    }

    # Read Current AP Config
    $config = $manager.GetCurrentAccessPointConfiguration()
    $TxtSsid.Text = $config.Ssid
    $PwdBox.Password = $config.Passphrase
    $TxtPassVisible.Text = $config.Passphrase

    # Populate Bands dynamically based on hardware support
    Populate-BandOptions -manager $manager -config $config

    # Refresh Connected Devices List
    Update-ConnectedDevices $manager
}

function Apply-APConfiguration {
    param($manager, [switch]$RestartIfActive)

    $newSsid = $TxtSsid.Text.Trim()
    $newPass = if ($ChkShowPass.IsChecked) { $TxtPassVisible.Text } else { $PwdBox.Password }

    if (-not $CmbBand.SelectedItem -or -not $CmbBand.SelectedItem.IsEnabled) {
        throw "Please select a supported network band."
    }
    $selectedBandTag = $CmbBand.SelectedItem.Tag

    # Validation
    if ([string]::IsNullOrWhiteSpace($newSsid)) {
        throw "Network Name (SSID) cannot be empty."
    }
    if ($newSsid.Length -gt 32) {
        throw "Network Name (SSID) cannot exceed 32 characters."
    }
    if ($newPass.Length -lt 8 -or $newPass.Length -gt 63) {
        throw "Network Password must be between 8 and 63 characters long."
    }

    $targetBand = [Windows.Networking.NetworkOperators.TetheringWiFiBand]::$selectedBandTag

    # Check if anything changed
    $currentConfig = $manager.GetCurrentAccessPointConfiguration()
    $hasChanged = ($currentConfig.Ssid -ne $newSsid) -or
                  ($currentConfig.Passphrase -ne $newPass) -or
                  ($currentConfig.Band.ToString() -ne $selectedBandTag)

    if (-not $hasChanged) {
        return $false
    }

    # Verify adapter supports target band
    $isSupp = Await-WinRtOperation ($currentConfig.IsBandSupportedAsync($targetBand)) ([System.Boolean])
    if (-not $isSupp) {
        throw "The selected band ($selectedBandTag) is not supported by your wireless hardware."
    }

    $wasActive = ($manager.TetheringOperationalState.ToString() -eq "On")

    if ($wasActive) {
        # Stop hotspot gracefully
        $null = Await-WinRtOperation ($manager.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])

        # Allow adapter time to deallocate virtual AP interface
        $retries = 8
        while ($manager.TetheringOperationalState.ToString() -ne "Off" -and $retries -gt 0) {
            Start-Sleep -Milliseconds 250
            $retries--
        }
    }

    # Apply configuration
    $currentConfig.Ssid = $newSsid
    $currentConfig.Passphrase = $newPass
    $currentConfig.Band = $targetBand
    Await-WinRtAction ($manager.ConfigureAccessPointAsync($currentConfig))

    if ($wasActive -and $RestartIfActive) {
        Start-Sleep -Milliseconds 500
        $startRes = Await-WinRtOperation ($manager.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
        if ($startRes.Status.ToString() -ne "Success") {
            $errDetail = Get-FriendlyErrorMessage $startRes.Status.ToString() $selectedBandTag
            throw "Settings saved, but restarting hotspot failed: $errDetail"
        }
    }

    return $true
}

# ==============================================================================
# 7. UI EVENT HANDLERS & REAL-TIME TIMER
# ==============================================================================

# Show/Hide Password Synchronization
$ChkShowPass.Add_Checked({
    $TxtPassVisible.Text = $PwdBox.Password
    $PwdBox.Visibility = "Collapsed"
    $TxtPassVisible.Visibility = "Visible"
})

$ChkShowPass.Add_Unchecked({
    $PwdBox.Password = $TxtPassVisible.Text
    $TxtPassVisible.Visibility = "Collapsed"
    $PwdBox.Visibility = "Visible"
})

# Toggle Hotspot On/Off
$BtnToggle.Add_Click({
    $manager = Get-TetheringManager
    if (-not $manager) { return }

    $BtnToggle.IsEnabled = $false
    $BtnSave.IsEnabled = $false
    $window.Cursor = [System.Windows.Input.Cursors]::Wait

    try {
        if ($manager.TetheringOperationalState.ToString() -eq "On") {
            $BtnToggle.Content = "Stopping..."
            $res = Await-WinRtOperation ($manager.StopTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
            if ($res.Status.ToString() -ne "Success") {
                [System.Windows.MessageBox]::Show("Hotspot stop failed: $($res.Status)", "Hotspot Error", "OK", "Error")
            }
        } else {
            # Auto-save any pending changes before turning on
            try {
                $null = Apply-APConfiguration -manager $manager -RestartIfActive:$false
            } catch {
                [System.Windows.MessageBox]::Show($_.Exception.Message, "Configuration Error", "OK", "Warning")
                return
            }

            $BtnToggle.Content = "Starting..."
            $res = Await-WinRtOperation ($manager.StartTetheringAsync()) ([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
            if ($res.Status.ToString() -ne "Success") {
                $bandTag = if ($CmbBand.SelectedItem) { $CmbBand.SelectedItem.Tag } else { "Unknown" }
                $msg = Get-FriendlyErrorMessage $res.Status.ToString() $bandTag
                [System.Windows.MessageBox]::Show("Hotspot start failed:`n`n$msg", "Hotspot Error", "OK", "Error")
            }
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error toggling hotspot: $($_.Exception.Message)", "Exception", "OK", "Error")
    } finally {
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        Update-UIState
    }
})

# Save & Apply Settings
$BtnSave.Add_Click({
    $manager = Get-TetheringManager
    if (-not $manager) { return }

    $BtnToggle.IsEnabled = $false
    $BtnSave.IsEnabled = $false
    $BtnSave.Content = "Applying..."
    $window.Cursor = [System.Windows.Input.Cursors]::Wait

    try {
        $saved = Apply-APConfiguration -manager $manager -RestartIfActive:$true
        if ($saved) {
            [System.Windows.MessageBox]::Show("Mobile Hotspot settings applied successfully.", "Saved", "OK", "Information")
        } else {
            [System.Windows.MessageBox]::Show("No settings were changed.", "Info", "OK", "Information")
        }
    } catch {
        [System.Windows.MessageBox]::Show("Failed to apply settings:`n`n$($_.Exception.Message)", "Configuration Error", "OK", "Error")
    } finally {
        $BtnSave.Content = "Save & Apply Changes"
        $window.Cursor = [System.Windows.Input.Cursors]::Arrow
        Update-UIState
    }
})

# Refresh Button
$BtnRefresh.Add_Click({
    Update-UIState
})

# Initialize UI on Window Load
$window.Add_Loaded({
    Update-UIState

    # Real-time background poll (every 3 seconds) for live connected devices update
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(3)
    $timer.Add_Tick({
        $m = Get-TetheringManager
        if ($m -and $m.TetheringOperationalState.ToString() -eq "On") {
            Update-ConnectedDevices $m
            $p = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
            $pName = if ($p) { $p.ProfileName } else { "Network" }
            $TxtSubInfo.Text = "Sharing '$pName' | Devices: $($m.ClientCount) / $($m.MaxClientCount)"
        }
    })
    $timer.Start()
})

# Show GUI
$null = $window.ShowDialog()
