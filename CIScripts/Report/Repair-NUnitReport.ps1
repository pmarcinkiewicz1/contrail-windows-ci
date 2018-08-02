function Repair-NUnitReport {
    Param([Parameter(Mandatory = $true)] [string] $InputData)
    [xml] $XML = $InputData

    $CaseNodes = Find-CaseNodes -XML $XML
    Set-DescriptionAndNameTheSameFor -Nodes $CaseNodes

    Compress-ParametrizedTests -Xml $XML

    $SuiteNodesWithCases = Get-DirectSuiteParentsOf -Nodes $CaseNodes
    $SuiteNodesWithCases | Foreach-Object { $XML.'test-results'.AppendChild($_) } | Out-Null

    $SuiteNodesWithoutCases = Find-SuiteNodesWithoutCases -XML $XML
    Remove-Nodes -Nodes $SuiteNodesWithoutCases

    $RootResultsNode = Find-RootPesterResultsNode -XML $XML
    $Counters = Get-TestResultCounts -Nodes $CaseNodes
    Set-TestResultCountersTo -Node $RootResultsNode -Counters $Counters

    return $XML.OuterXml
}

function Split-NUnitReport {
    Param([Parameter(Mandatory = $true)] [string] $InputData)
    [xml] $XML = $InputData

    $Root = Find-RootPesterSuiteNode -XML $XML

    $PesterFilesNodes = $Root.Node.FirstChild.ChildNodes
    $NumOfPesterFilesNodes = $PesterFilesNodes.Count

    $XMLClones = 1..$NumOfPesterFilesNodes | ForEach-Object { $XML.Clone() }

    $NodeToKeepIdx = 0
    $XMLs = $XMLClones | ForEach-Object {
        $RootOfClonedXML = Find-RootPesterSuiteNode -XML $_
        $KeptNode = Copy-NodeOfSpecificTestSuite -FromNode $RootOfClonedXML.Node `
            -IndexOfNodeTokeep $NodeToKeepIdx

        $AllNodesOfSpecificTestSuites = $RootOfClonedXML.Node.FirstChild.ChildNodes
        Remove-Nodes -Nodes $AllNodesOfSpecificTestSuites

        $RootOfClonedXML.Node.FirstChild.AppendChild($KeptNode) | Out-Null

        $SuiteName = Get-NameOfPesterTestSuite -FromNode $KeptNode
        $NodeToKeepIdx += 1
        return @{
            Content=$_.OuterXml;
            SuiteName=$SuiteName;
        }
    }

    return $XMLs
}

function Find-RootPesterResultsNode {
    Param([Parameter(Mandatory = $true)] [xml] $XML)
    $RootResults = $XML | Select-Xml -Xpath '/test-results'
    return ,$RootResults.Node
}

function Set-TestResultCountersTo {
    Param([Parameter(Mandatory = $true)] [System.Xml.XmlElement] $Node,
          [Parameter(Mandatory = $true)] [AllowEmptyCollection()] $Counters)
    if ($Node.HasAttribute('total')) {
        $Node.SetAttribute('total', $Counters.Total)
    }
    if ($Node.HasAttribute('failures')) {
        $Node.SetAttribute('failures', $Counters.Failures)
    }
    if ($Node.HasAttribute('inconclusive')) {
        $Node.SetAttribute('inconclusive', $Counters.Inconclusive)
    }
}

function Find-CaseNodes {
    Param([Parameter(Mandatory = $true)] [xml] $XML)
    $XPath = "//test-case"
    $Selection = $XML | Select-Xml -XPath $Xpath
    $Nodes = @()
    $Nodes += ($Selection | ForEach-Object { $_.Node })
    # use coma notation to return empty array if nothing was selected.
    return ,$Nodes
}

function Find-RootPesterSuiteNode {
    Param([Parameter(Mandatory = $true)] [xml] $XML)
    $Root = $XML | Select-Xml -Xpath '//test-suite[@name="Pester"]'
    return ,$Root
}

function Get-DirectSuiteParentsOf {
    Param([Parameter(Mandatory = $true)] [AllowEmptyCollection()]
          [System.Xml.XmlElement[]] $Nodes)
    $Arr = @()
    $Arr += $Nodes | ForEach-Object {
        $_.ParentNode.ParentNode
    }
    return ,$Arr
}

function Compress-ParametrizedTests {
    Param([Parameter(Mandatory = $true)] [xml] $XML)
    $ParametrizedTests = $XML | Select-Xml -Xpath '//test-suite[@type="ParameterizedTest"]/results/*'
    foreach ($TestCase in $ParametrizedTests | Foreach-Object { $_.Node }) {
        $TestCase.ParentNode.ParentNode.ParentNode.AppendChild($TestCase) | Out-Null
    }
}

function Set-DescriptionAndNameTheSameFor {
    Param([Parameter(Mandatory = $true)] [AllowEmptyCollection()]
          [System.Xml.XmlElement[]] $Nodes)
    $Nodes | ForEach-Object {
        if ($_.Attributes['description']) {
            $_.name = $_.description
        }
    } | Out-Null
}

function Find-SuiteNodesWithoutCases {
    Param([Parameter(Mandatory = $true)] [xml] $XML)
    $XPath = "//test-suite[not(.//test-case)]"
    $Selection = $XML | Select-Xml -XPath $Xpath
    $Nodes = @()
    $Nodes += ($Selection | ForEach-Object { $_.Node })
    return ,$Nodes
}

function Remove-Nodes {
    Param([Parameter(Mandatory = $true)] [AllowEmptyCollection()]
          [System.Xml.XmlElement[]] $Nodes)
    $Nodes | ForEach-Object {
        $_.ParentNode.RemoveChild($_)
    } | Out-Null
}

function Get-TestResultCounts {
    Param([Parameter(Mandatory = $true)] [AllowEmptyCollection()]
          [System.Xml.XmlElement[]] $Nodes)
    $Counters = @{
        "Total"=0;
        "Failures"=0;
        "Inconclusive"=0
    }
    $Nodes | ForEach-Object {
        $Counters.Total += 1
        if ($_.HasAttribute('result')) {
            if ($_.'result' -eq 'Inconclusive') {
                $Counters.Inconclusive += 1
            } elseif ($_.'result' -eq 'Failure') {
                $Counters.Failures += 1
            }
        }
    } | Out-Null
    return $Counters
}

function Get-NameOfPesterTestSuite {
    Param([Parameter(Mandatory = $true)] [System.Xml.XmlElement] $FromNode)
    $PesterFilepath = $FromNode."name"
    # Example:
    # From "C:/SomePath/TestSuiteName.Tests.ps1"
    # we get "TestSuiteName"
    $SuiteName = (Split-Path $PesterFilepath -Leaf).split('.')[-3]
    return $SuiteName
}

function Copy-NodeOfSpecificTestSuite {
    Param([Parameter(Mandatory = $true)] [System.Xml.XmlElement] $FromNode,
          [Parameter(Mandatory = $true)] [int] $IndexOfNodeTokeep)
    $PesterFilesNodes = $FromNode.FirstChild.ChildNodes
    $ClonedNode = $PesterFilesNodes[$IndexOfNodeTokeep].Clone()
    return $ClonedNode
}
