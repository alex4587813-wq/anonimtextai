#requires -version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Anonymizer.Core.psm1') -Force

$script:Failures = New-Object System.Collections.Generic.List[string]
$script:Passed = 0

function Assert-Equal {
    param(
        [string]$Name,
        [AllowNull()]
        $Actual,
        [AllowNull()]
        $Expected
    )

    if ($Actual -eq $Expected) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       Ожидалось: $Expected"
        Write-Host "       Получено:  $Actual"
        $script:Failures.Add($Name) | Out-Null
    }
}

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )

    Assert-Equal -Name $Name -Actual $Condition -Expected $true
}

function New-TestSettings {
    param(
        [string[]]$EnabledCategories = @(
            'PERSON',
            'COMPANY',
            'PHONE',
            'EMAIL',
            'IP_ADDRESS',
            'REQUISITE'
        ),
        [string[]]$ExcludedTerms = @(),
        [string[]]$MandatoryCompanyTerms = @()
    )

    [pscustomobject]@{
        SchemaVersion         = 2
        EnabledCategories     = @($EnabledCategories)
        ExcludedTerms         = @($ExcludedTerms)
        MandatoryCompanyTerms = @($MandatoryCompanyTerms)
    }
}

try {
    $defaultResult = Invoke-TextAnonymization `
        -Text "Александр Абрамян работает в компании Платформикс.`r`nТелефон: +7 999 123-45-67"
    Assert-Equal `
        -Name 'Пример из ТЗ' `
        -Actual $defaultResult.Text `
        -Expected "[PERSON_001] работает в компании [COMPANY_001].`r`nТелефон: [PHONE_001]"

    $emailResult = Invoke-TextAnonymization `
        -Text 'Напишите на ivan@example.ru. Повторно: IVAN@example.ru'
    Assert-Equal `
        -Name 'Одинаковый email получает одинаковую метку' `
        -Actual $emailResult.Text `
        -Expected 'Напишите на [EMAIL_001]. Повторно: [EMAIL_001]'

    $companyResult = Invoke-TextAnonymization -Text 'Заказчик — ООО «Ромашка»'
    Assert-Equal `
        -Name 'Организация с правовой формой' `
        -Actual $companyResult.Text `
        -Expected 'Заказчик — [COMPANY_001]'

    $ipResult = Invoke-TextAnonymization `
        -Text 'Серверы: 192.168.1.10 и 999.168.1.10'
    Assert-Equal `
        -Name 'Проверка диапазона IPv4' `
        -Actual $ipResult.Text `
        -Expected 'Серверы: [IP_ADDRESS_001] и 999.168.1.10'

    $excludedSettings = New-TestSettings `
        -ExcludedTerms @('Платформикс') `
        -MandatoryCompanyTerms @()
    $excludedResult = Invoke-TextAnonymization `
        -Text 'Александр Абрамян работает в компании Платформикс.' `
        -Settings $excludedSettings
    Assert-Equal `
        -Name 'Список исключений' `
        -Actual $excludedResult.Text `
        -Expected '[PERSON_001] работает в компании Платформикс.'

    $mandatorySettings = New-TestSettings `
        -EnabledCategories @() `
        -ExcludedTerms @('Платформикс') `
        -MandatoryCompanyTerms @('Платформикс')
    $mandatoryResult = Invoke-TextAnonymization `
        -Text 'Платформикс' `
        -Settings $mandatorySettings
    Assert-Equal `
        -Name 'Обязательная замена приоритетнее исключения' `
        -Actual $mandatoryResult.Text `
        -Expected '[COMPANY_001]'

    $boundarySettings = New-TestSettings `
        -EnabledCategories @() `
        -MandatoryCompanyTerms @('СИЛА')
    $boundaryResult = Invoke-TextAnonymization `
        -Text 'УСИЛАТЬ и СИЛА' `
        -Settings $boundarySettings
    Assert-Equal `
        -Name 'Границы обязательного слова' `
        -Actual $boundaryResult.Text `
        -Expected 'УСИЛАТЬ и [COMPANY_001]'

    $maskSettings = New-TestSettings `
        -EnabledCategories @() `
        -MandatoryCompanyTerms @('Иванов*')
    $maskResult = Invoke-TextAnonymization `
        -Text 'Иванов, Иванову и Ивановым; Иван и Псевдоиванов.' `
        -Settings $maskSettings
    Assert-Equal `
        -Name 'Маска учитывает окончания и границу слова' `
        -Actual $maskResult.Text `
        -Expected '[COMPANY_001], [COMPANY_002] и [COMPANY_003]; Иван и Псевдоиванов.'

    $invalidMaskSettings = New-TestSettings `
        -EnabledCategories @() `
        -MandatoryCompanyTerms @('*', 'Ива*нов')
    $invalidMaskResult = Invoke-TextAnonymization `
        -Text 'Иванов и Иван' `
        -Settings $invalidMaskSettings
    Assert-Equal `
        -Name 'Некорректные маски игнорируются' `
        -Actual $invalidMaskResult.Text `
        -Expected 'Иванов и Иван'

    $requisiteSource = @'
ИНН: 7707083893
КПП: 773601001
ОГРН: 1027700132195
БИК: 044525225
р/с: 40702810900000012345
Юридический адрес: 123456, г. Москва, ул. Ленина, д. 10
'@
    $requisiteResult = Invoke-TextAnonymization -Text $requisiteSource
    Assert-Equal `
        -Name 'Количество реквизитов' `
        -Actual $requisiteResult.Counts['REQUISITE'] `
        -Expected 6
    Assert-True `
        -Name 'ИНН заменён' `
        -Condition ($requisiteResult.Text -like '*ИНН: [[]REQUISITE_001[]]*')

    $personalRequisites = Invoke-TextAnonymization `
        -Text "СНИЛС: 123-456-789 01`r`nПаспорт: серия 4510 № 123456"
    Assert-Equal `
        -Name 'СНИЛС и паспорт' `
        -Actual $personalRequisites.Counts['REQUISITE'] `
        -Expected 2

    $disabledSettings = New-TestSettings `
        -EnabledCategories @('PERSON', 'COMPANY', 'PHONE', 'EMAIL', 'IP_ADDRESS')
    $unmodifiedRequisite = Invoke-TextAnonymization `
        -Text 'ИНН: 7707083893' `
        -Settings $disabledSettings
    Assert-Equal `
        -Name 'Отключение категории реквизитов' `
        -Actual $unmodifiedRequisite.Text `
        -Expected 'ИНН: 7707083893'

    $unlabeledResult = Invoke-TextAnonymization -Text 'Номер заявки: 7707083893'
    Assert-Equal `
        -Name 'Неподписанное число не является реквизитом' `
        -Actual $unlabeledResult.Text `
        -Expected 'Номер заявки: 7707083893'
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $script:Failures.Add('Необработанная ошибка тестов') | Out-Null
}

Write-Host ''
Write-Host "Пройдено: $script:Passed"
Write-Host "Ошибок: $($script:Failures.Count)"

if ($script:Failures.Count -gt 0) {
    exit 1
}

exit 0
