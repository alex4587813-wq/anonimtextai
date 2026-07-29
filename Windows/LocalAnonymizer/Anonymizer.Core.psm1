Set-StrictMode -Version Latest

$script:CategoryDisplayNames = [ordered]@{
    PERSON     = 'ФИО'
    COMPANY    = 'Организации'
    PHONE      = 'Телефоны'
    EMAIL      = 'Email'
    IP_ADDRESS = 'IP'
    REQUISITE  = 'Реквизиты'
}

$script:DefaultMandatoryCompanyTerms = @(
    'СИЛА'
    'Платформикс'
    'Базовые решения'
)

$script:CommonFirstNames = @(
    'александр', 'алексей', 'алёна', 'анастасия', 'анатолий', 'андрей',
    'анна', 'антон', 'аркадий', 'артём', 'борис', 'вадим', 'валентин',
    'валентина', 'валерий', 'василий', 'вера', 'виктор', 'виктория',
    'виталий', 'владимир', 'владислав', 'вячеслав', 'галина', 'геннадий',
    'георгий', 'григорий', 'дарья', 'денис', 'дмитрий', 'евгений',
    'евгения', 'екатерина', 'елена', 'елизавета', 'иван', 'игорь',
    'илья', 'инна', 'ирина', 'кирилл', 'константин', 'ксения', 'лариса',
    'лев', 'лидия', 'любовь', 'людмила', 'максим', 'маргарита', 'марина',
    'мария', 'михаил', 'надежда', 'наталья', 'никита', 'николай', 'нина',
    'олег', 'ольга', 'павел', 'пётр', 'полина', 'роман', 'светлана',
    'семён', 'сергей', 'софия', 'станислав', 'степан', 'тамара', 'татьяна',
    'тимофей', 'фёдор', 'юлия', 'юрий', 'яна', 'ярослав'
)

$script:SurnameEndings = @(
    'ов', 'ев', 'ёв', 'ин', 'ын', 'ова', 'ева', 'ёва', 'ина', 'ына',
    'ский', 'цкий', 'ской', 'цкой', 'ская', 'цкая', 'ян', 'янц',
    'енко', 'ко', 'ук', 'юк', 'ич', 'ец', 'дзе', 'швили'
)

$script:PatronymicEndings = @(
    'ович', 'евич', 'ич', 'овна', 'евна', 'ична', 'инична'
)

function Get-AnonymizerDataDirectory {
    $baseDirectory = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )
    Join-Path $baseDirectory 'LocalAnonymizer'
}

function Write-AnonymizerLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ), $Level, $Message

    Write-Host $line

    try {
        $dataDirectory = Get-AnonymizerDataDirectory
        if (-not (Test-Path -LiteralPath $dataDirectory)) {
            New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
        }

        $logPath = Join-Path $dataDirectory 'app.log'
        [IO.File]::AppendAllText(
            $logPath,
            $line + [Environment]::NewLine,
            [Text.Encoding]::UTF8
        )
    }
    catch {
        Write-Host '[WARN] Не удалось записать технический журнал.'
    }
}

function Get-AnonymizerCategoryDefinitions {
    [ordered]@{
        PERSON     = $script:CategoryDisplayNames.PERSON
        COMPANY    = $script:CategoryDisplayNames.COMPANY
        PHONE      = $script:CategoryDisplayNames.PHONE
        EMAIL      = $script:CategoryDisplayNames.EMAIL
        IP_ADDRESS = $script:CategoryDisplayNames.IP_ADDRESS
        REQUISITE  = $script:CategoryDisplayNames.REQUISITE
    }
}

function Get-UniqueTerms {
    param([object[]]$Terms)

    $result = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($item in @($Terms)) {
        if ($null -eq $item) {
            continue
        }

        $term = ([string]$item).Trim()
        if ([string]::IsNullOrWhiteSpace($term)) {
            continue
        }

        $key = $term.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $result.Add($term) | Out-Null
        }
    }

    @($result)
}

function Get-DefaultAnonymizerSettings {
    [pscustomobject]@{
        SchemaVersion         = 2
        EnabledCategories     = @($script:CategoryDisplayNames.Keys)
        ExcludedTerms         = @()
        MandatoryCompanyTerms = @($script:DefaultMandatoryCompanyTerms)
    }
}

function Get-AnonymizerSettings {
    $settingsPath = Join-Path (Get-AnonymizerDataDirectory) 'settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return (Get-DefaultAnonymizerSettings)
    }

    try {
        $saved = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $propertyNames = @($saved.PSObject.Properties.Name)
        $schemaVersion = 1

        if ($propertyNames -contains 'SchemaVersion') {
            $schemaVersion = [int]$saved.SchemaVersion
        }

        $enabledCategories = @()
        if ($propertyNames -contains 'EnabledCategories') {
            $enabledCategories = @(
                $saved.EnabledCategories |
                    Where-Object { $script:CategoryDisplayNames.Contains($_) }
            )
        }

        if ($schemaVersion -lt 2 -and $enabledCategories -notcontains 'REQUISITE') {
            $enabledCategories += 'REQUISITE'
        }

        $excludedTerms = @()
        if ($propertyNames -contains 'ExcludedTerms') {
            $excludedTerms = @(Get-UniqueTerms @($saved.ExcludedTerms))
        }

        if ($propertyNames -contains 'MandatoryCompanyTerms') {
            $mandatoryTerms = @(Get-UniqueTerms @($saved.MandatoryCompanyTerms))
        }
        else {
            $mandatoryTerms = @($script:DefaultMandatoryCompanyTerms)
        }

        [pscustomobject]@{
            SchemaVersion         = 2
            EnabledCategories     = @($enabledCategories)
            ExcludedTerms         = @($excludedTerms)
            MandatoryCompanyTerms = @($mandatoryTerms)
        }
    }
    catch {
        Write-AnonymizerLog -Level WARN -Message 'Настройки повреждены; загружены значения по умолчанию.'
        Get-DefaultAnonymizerSettings
    }
}

function Save-AnonymizerSettings {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Settings
    )

    $dataDirectory = Get-AnonymizerDataDirectory
    if (-not (Test-Path -LiteralPath $dataDirectory)) {
        New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
    }

    $settingsPath = Join-Path $dataDirectory 'settings.json'
    $normalized = [ordered]@{
        SchemaVersion         = 2
        EnabledCategories     = @($Settings.EnabledCategories)
        ExcludedTerms         = @(Get-UniqueTerms @($Settings.ExcludedTerms))
        MandatoryCompanyTerms = @(Get-UniqueTerms @($Settings.MandatoryCompanyTerms))
    }
    $json = $normalized | ConvertTo-Json -Depth 4
    $utf8WithBom = [Text.UTF8Encoding]::new($true)
    [IO.File]::WriteAllText($settingsPath, $json, $utf8WithBom)

    Write-AnonymizerLog -Message (
        'Настройки сохранены: категорий {0}, исключений {1}, обязательных замен {2}.' -f
        @($normalized.EnabledCategories).Count,
        @($normalized.ExcludedTerms).Count,
        @($normalized.MandatoryCompanyTerms).Count
    )
}

function New-Detection {
    param(
        [int]$Start,
        [int]$Length,
        [string]$Category,
        [int]$Priority,
        [string]$Value
    )

    [pscustomobject]@{
        Start    = $Start
        Length   = $Length
        Category = $Category
        Priority = $Priority
        Value    = $Value
    }
}

function Add-PatternDetections {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Target,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [int]$Priority,

        [int]$CaptureGroup = 0,
        [bool]$IgnoreCase = $true
    )

    $options = [Text.RegularExpressions.RegexOptions]::CultureInvariant
    if ($IgnoreCase) {
        $options = $options -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase
    }

    $expression = [regex]::new($Pattern, $options)
    foreach ($match in $expression.Matches($Text)) {
        if ($CaptureGroup -ge $match.Groups.Count) {
            continue
        }

        $group = $match.Groups[$CaptureGroup]
        if ($group.Success -and $group.Length -gt 0) {
            $Target.Add(
                (New-Detection `
                    -Start $group.Index `
                    -Length $group.Length `
                    -Category $Category `
                    -Priority $Priority `
                    -Value $group.Value)
            ) | Out-Null
        }
    }
}

function Test-LooksLikeRussianPersonName {
    param([string]$Value)

    $words = @(
        [regex]::Split($Value.Trim(), '\s+') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.ToLowerInvariant() }
    )

    if ($words.Count -lt 2 -or $words.Count -gt 3) {
        return $false
    }

    $hasFirstName = $false
    $hasSurname = $false
    $hasPatronymic = $false

    foreach ($word in $words) {
        if ($script:CommonFirstNames -contains $word) {
            $hasFirstName = $true
        }
        foreach ($ending in $script:SurnameEndings) {
            if ($word.EndsWith($ending)) {
                $hasSurname = $true
                break
            }
        }
        foreach ($ending in $script:PatronymicEndings) {
            if ($word.EndsWith($ending)) {
                $hasPatronymic = $true
                break
            }
        }
    }

    ($hasFirstName -and $hasSurname) -or
        ($words.Count -eq 3 -and $hasFirstName -and $hasPatronymic)
}

function Normalize-Value {
    param([string]$Value)

    ([regex]::Replace($Value.Trim().ToLowerInvariant(), '\s+', ' '))
}

function Normalize-ExclusionValue {
    param([string]$Value)

    $separated = [regex]::Replace(
        $Value.ToLowerInvariant(),
        '[^\p{L}\p{N}]+',
        ' '
    )
    [regex]::Replace($separated.Trim(), '\s+', ' ')
}

function Test-IsExcluded {
    param(
        [string]$Value,
        [string[]]$NormalizedExclusions
    )

    $normalizedValue = Normalize-ExclusionValue $Value
    $paddedValue = ' ' + $normalizedValue + ' '

    foreach ($exclusion in @($NormalizedExclusions)) {
        if (
            $normalizedValue -eq $exclusion -or
            $paddedValue.Contains(' ' + $exclusion + ' ')
        ) {
            return $true
        }
    }

    $false
}

function Invoke-TextAnonymization {
    param(
        [AllowEmptyString()]
        [string]$Text,

        [psobject]$Settings = (Get-DefaultAnonymizerSettings)
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return [pscustomobject]@{
            Text         = ''
            Counts       = @{}
            TotalMatches = 0
        }
    }

    Write-AnonymizerLog -Message (
        'Обработка начата: символов {0}.' -f $Text.Length
    )

    $matches = New-Object System.Collections.Generic.List[object]

    Add-PatternDetections `
        -Target $matches `
        -Text $Text `
        -Pattern '(?<![\p{L}\p{N}._%+\-])[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-ZА-ЯЁ]{2,}(?![\p{L}\p{N}_\-])' `
        -Category 'EMAIL' `
        -Priority 100

    $ipStartIndex = $matches.Count
    Add-PatternDetections `
        -Target $matches `
        -Text $Text `
        -Pattern '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])' `
        -Category 'IP_ADDRESS' `
        -Priority 95

    for ($index = $matches.Count - 1; $index -ge $ipStartIndex; $index--) {
        $validIP = $true
        foreach ($part in ($matches[$index].Value -split '\.')) {
            $number = 0
            if (
                -not [int]::TryParse($part, [ref]$number) -or
                $number -lt 0 -or
                $number -gt 255
            ) {
                $validIP = $false
                break
            }
        }
        if (-not $validIP) {
            $matches.RemoveAt($index)
        }
    }

    Add-PatternDetections `
        -Target $matches `
        -Text $Text `
        -Pattern '(?<![\p{L}\d])(?:\+7|8)[ \t\-()]*(?:\d[ \t\-()]*){10}(?!\d)' `
        -Category 'PHONE' `
        -Priority 90

    $requisitePatterns = @(
        '\bИНН[ \t]*[:№\-]?[ \t]*(\d{12}|\d{10})(?!\d)',
        '\bКПП[ \t]*[:№\-]?[ \t]*(\d{9})(?!\d)',
        '\bОГРНИП[ \t]*[:№\-]?[ \t]*(\d{15})(?!\d)',
        '\bОГРН[ \t]*[:№\-]?[ \t]*(\d{13})(?!\d)',
        '\bОКПО[ \t]*[:№\-]?[ \t]*(\d{10}|\d{8})(?!\d)',
        '\bБИК[ \t]*[:№\-]?[ \t]*(\d{9})(?!\d)',
        '\b(?:р[\/]?с|расч[её]тный[ \t]+сч[её]т|к[\/]?с|корреспондентский[ \t]+сч[её]т)[ \t]*[:№\-]?[ \t]*(\d{20})(?!\d)',
        '\bСНИЛС[ \t]*[:№\-]?[ \t]*(\d{3}[\- ]?\d{3}[\- ]?\d{3}[ \-]?\d{2})(?!\d)',
        '\b(?:паспорт(?:ные[ \t]+данные)?|серия[ \t]+и[ \t]+номер[ \t]+паспорта)[ \t]*[:\-]?[ \t]*(?:серия[ \t]*)?(\d{4}[ \t\-]*(?:№|номер)?[ \t]*\d{6})(?!\d)'
    )

    foreach ($pattern in $requisitePatterns) {
        Add-PatternDetections `
            -Target $matches `
            -Text $Text `
            -Pattern $pattern `
            -Category 'REQUISITE' `
            -Priority 110 `
            -CaptureGroup 1
    }

    $addressPatterns = @(
        '\b(?:юридический|фактический|почтовый)[ \t]+адрес[ \t]*[:\-—]?[ \t]+([^\r\n;]{8,240})',
        '\b(?:адрес(?:[ \t]+регистрации)?|место[ \t]+нахождения)[ \t]*[:\-—][ \t]*([^\r\n;]{8,240})'
    )

    foreach ($pattern in $addressPatterns) {
        Add-PatternDetections `
            -Target $matches `
            -Text $Text `
            -Pattern $pattern `
            -Category 'REQUISITE' `
            -Priority 130 `
            -CaptureGroup 1
    }

    Add-PatternDetections `
        -Target $matches `
        -Text $Text `
        -Pattern '\b(?:ООО|ПАО|АО|ОАО|ЗАО|ИП|АНО|НКО|ФГУП|ГУП|МУП|ГК)[ \t]+(?:[«"“][^»"”\r\n]{2,80}[»"”]|[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*(?:[ \t]+[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*){0,3})' `
        -Category 'COMPANY' `
        -Priority 70

    Add-PatternDetections `
        -Target $matches `
        -Text $Text `
        -Pattern '\b(?:компания|компании|организация|организации)[ \t]+([«"“][^»"”\r\n]{2,80}[»"”]|[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*(?:[ \t]+[А-ЯЁA-Z][\p{L}\p{N}_\-]*(?:\.[\p{L}\p{N}_\-]+)*){0,2})' `
        -Category 'COMPANY' `
        -Priority 65 `
        -CaptureGroup 1

    $personCandidates = New-Object System.Collections.Generic.List[object]
    Add-PatternDetections `
        -Target $personCandidates `
        -Text $Text `
        -Pattern '\b[А-ЯЁ][а-яё\-]{1,30}(?:\s+[А-ЯЁ][а-яё\-]{1,30}){1,2}\b' `
        -Category 'PERSON' `
        -Priority 50 `
        -IgnoreCase $false

    foreach ($candidate in $personCandidates) {
        if (Test-LooksLikeRussianPersonName $candidate.Value) {
            $matches.Add($candidate) | Out-Null
        }
    }

    $normalizedExclusions = @(
        $Settings.ExcludedTerms |
            ForEach-Object { Normalize-ExclusionValue ([string]$_) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $filteredMatches = New-Object System.Collections.Generic.List[object]
    foreach ($match in $matches) {
        if (
            @($Settings.EnabledCategories) -contains $match.Category -and
            -not (Test-IsExcluded `
                -Value $match.Value `
                -NormalizedExclusions $normalizedExclusions)
        ) {
            $filteredMatches.Add($match) | Out-Null
        }
    }

    foreach ($termItem in @($Settings.MandatoryCompanyTerms)) {
        $term = ([string]$termItem).Trim()
        if ([string]::IsNullOrWhiteSpace($term)) {
            continue
        }

        $escapedTokens = New-Object System.Collections.Generic.List[string]
        $isValidTerm = $true

        foreach ($rawToken in [regex]::Split($term, '\s+')) {
            $token = ([string]$rawToken).Trim()
            if ([string]::IsNullOrWhiteSpace($token)) {
                continue
            }

            if ($token.EndsWith('*')) {
                $prefix = $token.Substring(0, $token.Length - 1)
                if (
                    [string]::IsNullOrWhiteSpace($prefix) -or
                    $prefix.Contains('*')
                ) {
                    $isValidTerm = $false
                    break
                }
                $escapedTokens.Add(
                    [regex]::Escape($prefix) + '[\p{L}\p{M}\p{N}_-]*'
                ) | Out-Null
            }
            elseif ($token.Contains('*')) {
                $isValidTerm = $false
                break
            }
            else {
                $escapedTokens.Add([regex]::Escape($token)) | Out-Null
            }
        }

        if (-not $isValidTerm -or $escapedTokens.Count -eq 0) {
            continue
        }

        $phrasePattern = @($escapedTokens) -join '[ \t]+'
        $mandatoryPattern = '(?<![\p{L}\p{N}])' +
            $phrasePattern +
            '(?![\p{L}\p{N}])'

        Add-PatternDetections `
            -Target $filteredMatches `
            -Text $Text `
            -Pattern $mandatoryPattern `
            -Category 'COMPANY' `
            -Priority 120
    }

    $unique = @{}
    foreach ($match in $filteredMatches) {
        $key = '{0}:{1}:{2}' -f $match.Start, $match.Length, $match.Category
        if (
            -not $unique.ContainsKey($key) -or
            $match.Priority -gt $unique[$key].Priority
        ) {
            $unique[$key] = $match
        }
    }

    $ranked = @(
        $unique.Values |
            Sort-Object -Property `
                @{ Expression = { $_.Priority }; Descending = $true },
                @{ Expression = { $_.Length }; Descending = $true },
                @{ Expression = { $_.Start }; Descending = $false }
    )

    $accepted = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in $ranked) {
        $overlaps = $false
        foreach ($existing in $accepted) {
            if (
                $candidate.Start -lt ($existing.Start + $existing.Length) -and
                $existing.Start -lt ($candidate.Start + $candidate.Length)
            ) {
                $overlaps = $true
                break
            }
        }
        if (-not $overlaps) {
            $accepted.Add($candidate) | Out-Null
        }
    }

    $orderedMatches = @($accepted | Sort-Object -Property Start)
    $placeholders = @{}
    $counters = @{}
    $replacements = New-Object System.Collections.Generic.List[object]
    $counts = @{}

    foreach ($match in $orderedMatches) {
        $category = $match.Category
        if (-not $placeholders.ContainsKey($category)) {
            $placeholders[$category] = @{}
            $counters[$category] = 0
        }

        $canonicalValue = Normalize-Value $match.Value
        if ($placeholders[$category].ContainsKey($canonicalValue)) {
            $placeholder = $placeholders[$category][$canonicalValue]
        }
        else {
            $counters[$category] = [int]$counters[$category] + 1
            $placeholder = '[{0}_{1:D3}]' -f $category, $counters[$category]
            $placeholders[$category][$canonicalValue] = $placeholder
        }

        $replacements.Add(
            [pscustomobject]@{
                Start       = $match.Start
                Length      = $match.Length
                Placeholder = $placeholder
                Category    = $category
            }
        ) | Out-Null

        if (-not $counts.ContainsKey($category)) {
            $counts[$category] = 0
        }
        $counts[$category] = [int]$counts[$category] + 1
    }

    $resultText = $Text
    foreach ($replacement in @($replacements | Sort-Object -Property Start -Descending)) {
        $resultText = $resultText.Remove(
            $replacement.Start,
            $replacement.Length
        ).Insert(
            $replacement.Start,
            $replacement.Placeholder
        )
    }

    Write-AnonymizerLog -Message (
        'Обработка завершена: заменено фрагментов {0}.' -f $replacements.Count
    )

    [pscustomobject]@{
        Text         = $resultText
        Counts       = $counts
        TotalMatches = $replacements.Count
    }
}

Export-ModuleMember -Function @(
    'Get-AnonymizerCategoryDefinitions',
    'Get-DefaultAnonymizerSettings',
    'Get-AnonymizerSettings',
    'Save-AnonymizerSettings',
    'Invoke-TextAnonymization',
    'Write-AnonymizerLog'
)
