#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$modulePath = Join-Path $PSScriptRoot 'Anonymizer.Core.psm1'
Import-Module $modulePath -Force

Write-AnonymizerLog -Message 'Запуск Windows-приложения.'

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $smokeSettings = Get-DefaultAnonymizerSettings
    $smokeResult = Invoke-TextAnonymization `
        -Text 'Александр Абрамян работает в Платформикс.' `
        -Settings $smokeSettings
    if (
        $smokeResult.Text -notlike '*[[]PERSON_001[]]*' -or
        $smokeResult.Text -notlike '*[[]COMPANY_001[]]*'
    ) {
        throw 'Встроенная проверка механизма анонимизации не пройдена.'
    }
    Write-AnonymizerLog -Message 'Встроенная проверка механизма пройдена.'

    $xamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
    [xml]$xamlDocument = Get-Content `
        -LiteralPath $xamlPath `
        -Raw `
        -Encoding UTF8
    $xmlReader = New-Object Xml.XmlNodeReader $xamlDocument
    $script:Window = [Windows.Markup.XamlReader]::Load($xmlReader)

    $iconPath = Join-Path $PSScriptRoot 'AppIcon.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $iconImage = [Windows.Media.Imaging.BitmapImage]::new()
        $iconImage.BeginInit()
        $iconImage.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $iconImage.UriSource = [Uri]::new(
            $iconPath,
            [UriKind]::Absolute
        )
        $iconImage.EndInit()
        $script:Window.Icon = $iconImage
    }
}
catch {
    Write-AnonymizerLog -Level ERROR -Message (
        'Не удалось запустить приложение: {0}' -f $_.Exception.Message
    )
    [Windows.MessageBox]::Show(
        "Не удалось запустить приложение.`n`n$($_.Exception.Message)",
        'Локальный анонимизатор',
        [Windows.MessageBoxButton]::OK,
        [Windows.MessageBoxImage]::Error
    ) | Out-Null
    exit 1
}

function Get-Control {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $control = $script:Window.FindName($Name)
    if ($null -eq $control) {
        throw "Элемент интерфейса не найден: $Name"
    }
    $control
}

$script:StatusPanel = Get-Control 'StatusPanel'
$script:StatusIcon = Get-Control 'StatusIcon'
$script:StatusText = Get-Control 'StatusText'
$script:StatusDetails = Get-Control 'StatusDetails'
$script:RulesSummary = Get-Control 'RulesSummary'
$script:SourceTextBox = Get-Control 'SourceTextBox'
$script:ResultTextBox = Get-Control 'ResultTextBox'
$script:PasteButton = Get-Control 'PasteButton'
$script:ProcessButton = Get-Control 'ProcessButton'
$script:CopyButton = Get-Control 'CopyButton'
$script:ExclusionInput = Get-Control 'ExclusionInput'
$script:AddExclusionButton = Get-Control 'AddExclusionButton'
$script:ExclusionsList = Get-Control 'ExclusionsList'
$script:RemoveExclusionButton = Get-Control 'RemoveExclusionButton'
$script:MandatoryInput = Get-Control 'MandatoryInput'
$script:AddMandatoryButton = Get-Control 'AddMandatoryButton'
$script:MandatoryList = Get-Control 'MandatoryList'
$script:RemoveMandatoryButton = Get-Control 'RemoveMandatoryButton'

$script:CategoryDefinitions = Get-AnonymizerCategoryDefinitions
$script:CategoryControls = [ordered]@{
    PERSON     = Get-Control 'CategoryPerson'
    COMPANY    = Get-Control 'CategoryCompany'
    PHONE      = Get-Control 'CategoryPhone'
    EMAIL      = Get-Control 'CategoryEmail'
    IP_ADDRESS = Get-Control 'CategoryIP'
    REQUISITE  = Get-Control 'CategoryRequisite'
}

$script:Settings = Get-AnonymizerSettings
$script:ResultIsCurrent = $false
$script:IsUpdatingSource = $false
$script:AccentBrush = $script:Window.Resources['AccentBrush']
$script:SuccessBrush = $script:Window.Resources['SuccessBrush']

$script:CopyFeedbackTimer = New-Object Windows.Threading.DispatcherTimer
$script:CopyFeedbackTimer.Interval = [TimeSpan]::FromMilliseconds(1800)

function Test-TermExists {
    param(
        [object[]]$Terms,
        [string]$Candidate
    )

    foreach ($term in @($Terms)) {
        if (
            [string]::Equals(
                [string]$term,
                $Candidate,
                [StringComparison]::OrdinalIgnoreCase
            )
        ) {
            return $true
        }
    }
    $false
}

function Update-RulesSummary {
    $enabledCount = @($script:Settings.EnabledCategories).Count
    $categoryCount = @($script:CategoryDefinitions.Keys).Count
    $exclusionCount = @($script:Settings.ExcludedTerms).Count
    $mandatoryCount = @($script:Settings.MandatoryCompanyTerms).Count

    $script:RulesSummary.Text = (
        'Категории: {0} из {1} · Исключения: {2} · Замены слов: {3}' -f
        $enabledCount,
        $categoryCount,
        $exclusionCount,
        $mandatoryCount
    )
}

function Refresh-TermLists {
    $script:ExclusionsList.ItemsSource = $null
    $script:ExclusionsList.ItemsSource = @($script:Settings.ExcludedTerms)
    $script:MandatoryList.ItemsSource = $null
    $script:MandatoryList.ItemsSource = @(
        $script:Settings.MandatoryCompanyTerms
    )

    $script:RemoveExclusionButton.IsEnabled =
        $script:ExclusionsList.SelectedIndex -ge 0
    $script:RemoveMandatoryButton.IsEnabled =
        $script:MandatoryList.SelectedIndex -ge 0
    Update-RulesSummary
}

function Update-InputButtons {
    $script:ProcessButton.IsEnabled =
        -not [string]::IsNullOrWhiteSpace($script:SourceTextBox.Text)
    $script:AddExclusionButton.IsEnabled =
        -not [string]::IsNullOrWhiteSpace($script:ExclusionInput.Text)
    $script:AddMandatoryButton.IsEnabled =
        -not [string]::IsNullOrWhiteSpace($script:MandatoryInput.Text)
}

function Reset-CopyButton {
    $script:CopyFeedbackTimer.Stop()
    $script:CopyButton.Content = 'Скопировать'
    $script:CopyButton.Background = $script:AccentBrush
    $script:CopyButton.BorderBrush = $script:AccentBrush
}

function Invalidate-Result {
    $script:ResultIsCurrent = $false
    $script:CopyButton.IsEnabled = $false
    $script:StatusPanel.Visibility = [Windows.Visibility]::Collapsed
    Reset-CopyButton
}

function Save-SettingsAndInvalidate {
    Save-AnonymizerSettings -Settings $script:Settings
    Update-RulesSummary
    Invalidate-Result
}

function Sync-CategoriesFromControls {
    $enabledCategories = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $script:CategoryControls.GetEnumerator()) {
        if ($entry.Value.IsChecked -eq $true) {
            $enabledCategories.Add([string]$entry.Key) | Out-Null
        }
    }

    $script:Settings.EnabledCategories = @($enabledCategories)
    Save-SettingsAndInvalidate
}

function Add-Exclusion {
    $term = $script:ExclusionInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($term)) {
        return
    }

    if (-not (Test-TermExists $script:Settings.ExcludedTerms $term)) {
        $script:Settings.ExcludedTerms = @(
            @($script:Settings.ExcludedTerms) + $term
        )
        Save-SettingsAndInvalidate
        Refresh-TermLists
    }
    $script:ExclusionInput.Clear()
}

function Remove-SelectedExclusion {
    if ($script:ExclusionsList.SelectedIndex -lt 0) {
        return
    }

    $selected = [string]$script:ExclusionsList.SelectedItem
    $script:Settings.ExcludedTerms = @(
        $script:Settings.ExcludedTerms |
            Where-Object {
                -not [string]::Equals(
                    [string]$_,
                    $selected,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    Save-SettingsAndInvalidate
    Refresh-TermLists
}

function Add-MandatoryTerm {
    $term = $script:MandatoryInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($term)) {
        return
    }

    if (-not (Test-TermExists $script:Settings.MandatoryCompanyTerms $term)) {
        $script:Settings.MandatoryCompanyTerms = @(
            @($script:Settings.MandatoryCompanyTerms) + $term
        )
        Save-SettingsAndInvalidate
        Refresh-TermLists
    }
    $script:MandatoryInput.Clear()
}

function Remove-SelectedMandatoryTerm {
    if ($script:MandatoryList.SelectedIndex -lt 0) {
        return
    }

    $selected = [string]$script:MandatoryList.SelectedItem
    $script:Settings.MandatoryCompanyTerms = @(
        $script:Settings.MandatoryCompanyTerms |
            Where-Object {
                -not [string]::Equals(
                    [string]$_,
                    $selected,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    Save-SettingsAndInvalidate
    Refresh-TermLists
}

function Format-CategorySummary {
    param([hashtable]$Counts)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $script:CategoryDefinitions.GetEnumerator()) {
        if ($Counts.ContainsKey($entry.Key) -and $Counts[$entry.Key] -gt 0) {
            $parts.Add(
                ('{0}: {1}' -f $entry.Value, $Counts[$entry.Key])
            ) | Out-Null
        }
    }
    $parts -join ' · '
}

function Invoke-CurrentTextAnonymization {
    $sourceText = $script:SourceTextBox.Text
    if ([string]::IsNullOrWhiteSpace($sourceText)) {
        return
    }

    $script:StatusPanel.Visibility = [Windows.Visibility]::Visible
    $script:StatusIcon.Text = '●'
    $script:StatusIcon.Foreground = $script:AccentBrush
    $script:StatusText.Text = 'Обработка текста…'
    $script:StatusDetails.Text = ''
    $script:ProcessButton.IsEnabled = $false
    $script:CopyButton.IsEnabled = $false
    $script:Window.Dispatcher.Invoke(
        [Action] {},
        [Windows.Threading.DispatcherPriority]::Render
    )

    try {
        $result = Invoke-TextAnonymization `
            -Text $sourceText `
            -Settings $script:Settings

        $script:ResultTextBox.Text = $result.Text
        $script:ResultIsCurrent = $true
        $script:CopyButton.IsEnabled =
            -not [string]::IsNullOrEmpty($result.Text)
        Reset-CopyButton

        $script:StatusIcon.Foreground = $script:SuccessBrush
        $script:StatusText.Text = (
            'Обработано символов: {0:N0} · Очищено фрагментов: {1:N0}' -f
            $sourceText.Length,
            $result.TotalMatches
        )

        $details = Format-CategorySummary $result.Counts
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = 'Чувствительные данные не найдены'
        }
        $script:StatusDetails.Text = $details
    }
    catch {
        $script:ResultIsCurrent = $false
        $script:StatusIcon.Text = '!'
        $script:StatusIcon.Foreground = [Windows.Media.Brushes]::Crimson
        $script:StatusText.Text = 'Ошибка обработки'
        $script:StatusDetails.Text = $_.Exception.Message
        Write-AnonymizerLog -Level ERROR -Message (
            'Ошибка обработки: {0}' -f $_.Exception.Message
        )
    }
    finally {
        Update-InputButtons
    }
}

function Paste-AndProcess {
    if (-not [Windows.Clipboard]::ContainsText()) {
        [Windows.MessageBox]::Show(
            'В буфере обмена нет текста.',
            'Локальный анонимизатор',
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information
        ) | Out-Null
        Write-AnonymizerLog -Level WARN -Message 'Вставка пропущена: в буфере нет текста.'
        return
    }

    $clipboardText = [Windows.Clipboard]::GetText()
    $script:IsUpdatingSource = $true
    $script:SourceTextBox.Text = $clipboardText
    $script:IsUpdatingSource = $false
    Write-AnonymizerLog -Message (
        'Текст вставлен из буфера: символов {0}.' -f $clipboardText.Length
    )
    Invoke-CurrentTextAnonymization
}

function Copy-Result {
    if (
        -not $script:ResultIsCurrent -or
        [string]::IsNullOrEmpty($script:ResultTextBox.Text)
    ) {
        return
    }

    try {
        [Windows.Clipboard]::SetText($script:ResultTextBox.Text)
        $script:CopyButton.Content = 'Скопировано'
        $script:CopyButton.Background = $script:SuccessBrush
        $script:CopyButton.BorderBrush = $script:SuccessBrush
        $script:CopyFeedbackTimer.Stop()
        $script:CopyFeedbackTimer.Start()
        Write-AnonymizerLog -Message (
            'Результат скопирован: символов {0}.' -f
            $script:ResultTextBox.Text.Length
        )
    }
    catch {
        Write-AnonymizerLog -Level ERROR -Message (
            'Ошибка копирования: {0}' -f $_.Exception.Message
        )
        [Windows.MessageBox]::Show(
            'Не удалось скопировать результат в буфер обмена.',
            'Локальный анонимизатор',
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
}

foreach ($entry in $script:CategoryControls.GetEnumerator()) {
    $entry.Value.IsChecked =
        @($script:Settings.EnabledCategories) -contains $entry.Key
}
Refresh-TermLists
Update-InputButtons
Reset-CopyButton

$script:SourceTextBox.Add_TextChanged({
    if (-not $script:IsUpdatingSource) {
        Invalidate-Result
    }
    Update-InputButtons
})

$script:ExclusionInput.Add_TextChanged({ Update-InputButtons })
$script:MandatoryInput.Add_TextChanged({ Update-InputButtons })

foreach ($entry in $script:CategoryControls.GetEnumerator()) {
    $entry.Value.Add_Checked({ Sync-CategoriesFromControls })
    $entry.Value.Add_Unchecked({ Sync-CategoriesFromControls })
}

$script:AddExclusionButton.Add_Click({ Add-Exclusion })
$script:RemoveExclusionButton.Add_Click({ Remove-SelectedExclusion })
$script:AddMandatoryButton.Add_Click({ Add-MandatoryTerm })
$script:RemoveMandatoryButton.Add_Click({ Remove-SelectedMandatoryTerm })
$script:PasteButton.Add_Click({ Paste-AndProcess })
$script:ProcessButton.Add_Click({ Invoke-CurrentTextAnonymization })
$script:CopyButton.Add_Click({ Copy-Result })

$script:ExclusionsList.Add_SelectionChanged({
    $script:RemoveExclusionButton.IsEnabled =
        $script:ExclusionsList.SelectedIndex -ge 0
})
$script:MandatoryList.Add_SelectionChanged({
    $script:RemoveMandatoryButton.IsEnabled =
        $script:MandatoryList.SelectedIndex -ge 0
})

$script:ExclusionInput.Add_KeyDown({
    param($sender, $eventArguments)
    if ($eventArguments.Key -eq [Windows.Input.Key]::Enter) {
        Add-Exclusion
        $eventArguments.Handled = $true
    }
})
$script:MandatoryInput.Add_KeyDown({
    param($sender, $eventArguments)
    if ($eventArguments.Key -eq [Windows.Input.Key]::Enter) {
        Add-MandatoryTerm
        $eventArguments.Handled = $true
    }
})

$script:CopyFeedbackTimer.Add_Tick({
    $script:CopyFeedbackTimer.Stop()
    Reset-CopyButton
})

$script:Window.Add_PreviewKeyDown({
    param($sender, $eventArguments)

    $modifiers = [Windows.Input.Keyboard]::Modifiers
    $controlPressed = (
        $modifiers -band [Windows.Input.ModifierKeys]::Control
    ) -ne 0
    $shiftPressed = (
        $modifiers -band [Windows.Input.ModifierKeys]::Shift
    ) -ne 0

    if (
        $controlPressed -and
        -not $shiftPressed -and
        $eventArguments.Key -eq [Windows.Input.Key]::Enter
    ) {
        Invoke-CurrentTextAnonymization
        $eventArguments.Handled = $true
    }
    elseif (
        $controlPressed -and
        $shiftPressed -and
        $eventArguments.Key -eq [Windows.Input.Key]::C
    ) {
        Copy-Result
        $eventArguments.Handled = $true
    }
})

$script:Window.Add_Closed({
    Write-AnonymizerLog -Message 'Windows-приложение закрыто.'
})

Write-AnonymizerLog -Message 'Интерфейс Windows загружен.'
$script:Window.ShowDialog() | Out-Null
