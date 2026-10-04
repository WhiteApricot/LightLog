$ErrorActionPreference = 'Stop'

function Invoke-Json([string]$Uri) {
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      Start-Sleep -Milliseconds 350
      return Invoke-RestMethod -Uri $Uri -TimeoutSec 60 -Headers @{
        'User-Agent' = 'LightLogKnowledgeBuilder/1.0 (https://github.com/WhiteApricot/LightLog)'
      }
    }
    catch {
      if ($attempt -eq 5) { throw }
      Start-Sleep -Seconds (10 * $attempt)
    }
  }
}

function Get-CategoryMembers([string]$Category, [bool]$IncludeSubcategories) {
  $items = [System.Collections.Generic.List[object]]::new()
  $continue = $null
  do {
    $params = @{
      action = 'query'; list = 'categorymembers'; cmtitle = 'Category:' + $Category
      cmnamespace = if ($IncludeSubcategories) { '0|14' } else { '0' }
      cmlimit = '500'; format = 'json'; formatversion = '2'
    }
    if ($continue) { $params.cmcontinue = $continue }
    $query = @($params.GetEnumerator() | ForEach-Object {
      [uri]::EscapeDataString($_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
    $uri = 'https://zh.wikipedia.org/w/api.php?' + $query
    $root = Invoke-Json $uri
    foreach ($item in $root.query.categorymembers) { $items.Add($item) }
    $continue = $root.continue.cmcontinue
  } while ($continue)
  return $items
}

function Get-WikidataIds([int[]]$PageIds) {
  $ids = [System.Collections.Generic.List[string]]::new()
  for ($i = 0; $i -lt $PageIds.Count; $i += 50) {
    $batch = $PageIds[$i..([Math]::Min($i + 49, $PageIds.Count - 1))]
    $uri = 'https://zh.wikipedia.org/w/api.php?action=query&prop=pageprops&ppprop=wikibase_item&format=json&formatversion=2&pageids=' +
      [uri]::EscapeDataString(($batch -join '|'))
    $root = Invoke-Json $uri
    foreach ($page in $root.query.pages) {
      if ($page.pageprops.wikibase_item) { $ids.Add($page.pageprops.wikibase_item) }
    }
  }
  return $ids
}

function Add-CategoryEntities(
  [System.Collections.Generic.List[object]]$Records,
  [string]$RootCategory,
  [string]$SemanticKey,
  [int]$Target
) {
  $pageIds = [System.Collections.Generic.HashSet[int]]::new()
  $queue = [System.Collections.Generic.Queue[object]]::new()
  $queue.Enqueue([pscustomobject]@{ name = $RootCategory; depth = 0 })
  $seenCategories = [System.Collections.Generic.HashSet[string]]::new()
  while ($queue.Count -gt 0 -and $pageIds.Count -lt ($Target * 3)) {
    $current = $queue.Dequeue()
    if (-not $seenCategories.Add($current.name)) { continue }
    $members = Get-CategoryMembers $current.name ($current.depth -lt 3)
    foreach ($page in ($members | Where-Object ns -eq 0)) {
      [void]$pageIds.Add($page.pageid)
    }
    if ($current.depth -lt 3) {
      foreach ($subcategory in ($members | Where-Object ns -eq 14)) {
        $queue.Enqueue([pscustomobject]@{
          name = ($subcategory.title -replace '^Category:', '')
          depth = $current.depth + 1
        })
      }
    }
  }
  $itemIds = @(Get-WikidataIds @($pageIds))
  $added = 0
  for ($i = 0; $i -lt $itemIds.Count -and $added -lt $Target; $i += 50) {
    $batch = $itemIds[$i..([Math]::Min($i + 49, $itemIds.Count - 1))]
    $uri = 'https://www.wikidata.org/w/api.php?action=wbgetentities&props=labels%7Caliases&languages=zh%7Czh-hans%7Czh-cn%7Cen&format=json&formatversion=2&ids=' +
      [uri]::EscapeDataString(($batch -join '|'))
    $root = Invoke-Json $uri
    foreach ($property in $root.entities.PSObject.Properties) {
      $entity = $property.Value
      $canonical = @($entity.labels.'zh-hans'.value, $entity.labels.'zh-cn'.value, $entity.labels.zh.value, $entity.labels.en.value) |
        Where-Object { $_ } | Select-Object -First 1
      if (-not $canonical) { continue }
      $aliases = [System.Collections.Generic.HashSet[string]]::new()
      foreach ($language in @('zh-hans', 'zh-cn', 'zh', 'en')) {
        $label = $entity.labels.$language.value
        if ($label -and $label -ne $canonical) { [void]$aliases.Add($label) }
        foreach ($alias in $entity.aliases.$language) {
          if ($alias.value -and $alias.value -ne $canonical) { [void]$aliases.Add($alias.value) }
        }
      }
      if ($aliases.Count -lt 2) { continue }
      $Records.Add([ordered]@{
        wikidataId = $property.Name; canonicalName = $canonical
        aliases = @($aliases | Select-Object -First 12)
        kind = 'media/game title'; semanticKey = $SemanticKey; confidence = 0.86
        sourceUrl = 'https://www.wikidata.org/wiki/' + $property.Name
        sourceType = 'Wikidata via Wikimedia category'
        license = 'Wikidata CC0 1.0; category selection CC BY-SA 4.0'
        verifiedAt = '2026-10-04'
      })
      $added++
      if ($added -ge $Target) { break }
    }
  }
  Write-Output ($RootCategory + ': ' + $added + ' entities')
}

$records = [System.Collections.Generic.List[object]]::new()
Add-CategoryEntities $records '各年电子游戏' 'expense.entertainment.game' 800
Add-CategoryEntities $records '各年中国电影' 'expense.entertainment.movie' 800
$payload = [ordered]@{ version = 1; records = @($records) }
New-Item -ItemType Directory -Force tools\knowledge\source_data | Out-Null
$payload | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 tools\knowledge\source_data\wikidata_entities.json
Write-Output ('Wrote ' + $records.Count + ' entities')
