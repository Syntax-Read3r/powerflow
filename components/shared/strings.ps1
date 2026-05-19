# ==============================================================================
# PowerFlow — String Utilities
# ==============================================================================
# Domain   : Shared
# File     : components/shared/strings.ps1
# Purpose  : Provides naming-convention conversion helpers used by git and project tools
# Functions: Convert-ToKebabCase, Convert-ToSnakeCase, Convert-ToPascalCase, Convert-ToCamelCase
# Depends  : none
# ==============================================================================

# Helper functions for naming conventions
function Convert-ToKebabCase {
    param([string]$text)
    # First handle camelCase and PascalCase by inserting spaces before capitals
    $spacedText = $text -creplace '(?<!^)(?=[A-Z][a-z])', ' '
    # Also handle acronyms like "XMLParser" -> "XML Parser"
    $spacedText = $spacedText -creplace '(?<=[a-z])(?=[A-Z])', ' '

    # Now split on any delimiter (spaces, underscores, hyphens)
    $words = $spacedText -split '[\s_\-]+' | Where-Object { $_ -ne '' }

    # Join with hyphens and lowercase
    return ($words | ForEach-Object { $_.ToLower() }) -join '-'
}

function Convert-ToSnakeCase {
    param([string]$text)
    # First handle camelCase and PascalCase by inserting spaces before capitals
    $spacedText = $text -creplace '(?<!^)(?=[A-Z][a-z])', ' '
    # Also handle acronyms like "XMLParser" -> "XML Parser"
    $spacedText = $spacedText -creplace '(?<=[a-z])(?=[A-Z])', ' '

    # Now split on any delimiter (spaces, underscores, hyphens)
    $words = $spacedText -split '[\s_\-]+' | Where-Object { $_ -ne '' }

    # Join with underscores and lowercase
    return ($words | ForEach-Object { $_.ToLower() }) -join '_'
}

function Convert-ToPascalCase {
    param([string]$text)
    # First handle camelCase and PascalCase by inserting spaces before capitals
    $spacedText = $text -creplace '(?<!^)(?=[A-Z][a-z])', ' '
    # Also handle acronyms like "XMLParser" -> "XML Parser"
    $spacedText = $spacedText -creplace '(?<=[a-z])(?=[A-Z])', ' '

    # Now split on any delimiter (spaces, underscores, hyphens)
    $words = $spacedText -split '[\s_\-]+' | Where-Object { $_ -ne '' }

    # Capitalize first letter of each word
    return ($words | ForEach-Object {
        if ($_.Length -gt 0) {
            $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower()
        } else {
            $_
        }
    }) -join ''
}

function Convert-ToCamelCase {
    param([string]$text)
    $pascal = Convert-ToPascalCase $text
    if ($pascal.Length -gt 0) {
        return $pascal.Substring(0,1).ToLower() + $pascal.Substring(1)
    }
    return $pascal
}
