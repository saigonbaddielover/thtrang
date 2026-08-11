Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Drawio.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'Svg.Geometry.psm1')

function Get-DrawioShapeKind {
    param([Parameter(Mandatory = $true)][System.Xml.XmlElement]$Cell)
    $style=Get-DrawioStyleMap ([string]$Cell.style)
    $shape=if($style.ContainsKey('shape')){[string]$style.shape}else{''}
    if($style.ContainsKey('swimlane')){return 'swimlane'}
    if($shape -match '(?i)archive'){return 'archive'}
    if($shape -match '(?i)(multi.*document|multiple.*document)'){return 'multiple-document'}
    if($shape -match '(?i)document'){return 'document'}
    if($shape -match '(?i)(cylinder|data.?store|database|stored_data|partialRectangle)'){return 'data-store'}
    if($shape -match '(?i)note'){return 'note'}
    if($shape -match '(?i)(rhombus|decision)' -or $style.ContainsKey('rhombus')){return 'rhombus'}
    if($shape -match '(?i)(ellipse|terminator)' -or $style.ContainsKey('ellipse')){return 'ellipse'}
    if([string]::IsNullOrWhiteSpace($shape)){
        if($style.ContainsKey('rounded') -and [string]$style.rounded -eq '1'){return 'rounded-rectangle'}
        return 'rectangle'
    }
    if($shape -match '(?i)(rectangle|process)'){
        if($style.ContainsKey('rounded') -and [string]$style.rounded -eq '1'){return 'rounded-rectangle'}
        return 'rectangle'
    }
    'unknown'
}

function Get-DrawioShapeSafeArea {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Cell,
        [Parameter(Mandatory = $true)][object]$Bounds,
        [double]$Clearance = 2.0
    )
    $kind=Get-DrawioShapeKind $Cell
    $style=Get-DrawioStyleMap ([string]$Cell.style)
    $left=$Bounds.X+$Clearance;$top=$Bounds.Y+$Clearance;$right=$Bounds.X+$Bounds.Width-$Clearance;$bottom=$Bounds.Y+$Bounds.Height-$Clearance
    switch($kind){
        'document' {$bottom-=[math]::Max(5.0,$Bounds.Height*0.14)}
        'multiple-document' {$right-=[math]::Max(3.0,$Bounds.Width*0.04);$bottom-=[math]::Max(7.0,$Bounds.Height*0.18)}
        'note' {$right-=[math]::Min(20.0,$Bounds.Width*0.18);$top+=[math]::Min(4.0,$Bounds.Height*0.05)}
        'data-store' {$top+=[math]::Min(12.0,$Bounds.Height*0.16);$bottom-=[math]::Min(12.0,$Bounds.Height*0.16)}
        'swimlane' {
            $startSize=if($style.ContainsKey('startSize')){ConvertTo-DrawioNumber $style.startSize}else{23.0}
            $horizontal=(-not $style.ContainsKey('horizontal'))-or [string]$style.horizontal-ne'0'
            if($horizontal){$bottom=[math]::Min($bottom,$Bounds.Y+$startSize-$Clearance)}else{$right=[math]::Min($right,$Bounds.X+$startSize-$Clearance)}
        }
    }
    [pscustomobject]@{Kind=$kind;Left=$left;Top=$top;Right=$right;Bottom=$bottom;Bounds=$Bounds}
}

function Test-DrawioInkSafeArea {
    param(
        [Parameter(Mandatory = $true)][object]$Ink,
        [Parameter(Mandatory = $true)][object]$SafeArea,
        [double]$Epsilon = 0.05
    )
    $corners=@(
        [pscustomobject]@{X=$Ink.Left;Y=$Ink.Top},[pscustomobject]@{X=$Ink.Right;Y=$Ink.Top},
        [pscustomobject]@{X=$Ink.Right;Y=$Ink.Bottom},[pscustomobject]@{X=$Ink.Left;Y=$Ink.Bottom}
    )
    if($SafeArea.Right-le$SafeArea.Left-or$SafeArea.Bottom-le$SafeArea.Top){return $false}
    switch($SafeArea.Kind){
        'ellipse' {
            $cx=($SafeArea.Left+$SafeArea.Right)/2.0;$cy=($SafeArea.Top+$SafeArea.Bottom)/2.0;$rx=($SafeArea.Right-$SafeArea.Left)/2.0;$ry=($SafeArea.Bottom-$SafeArea.Top)/2.0
            foreach($corner in $corners){if([math]::Pow(($corner.X-$cx)/$rx,2)+[math]::Pow(($corner.Y-$cy)/$ry,2)-gt(1.0+$Epsilon)){return $false}}
            return $true
        }
        'rhombus' {
            $cx=($SafeArea.Left+$SafeArea.Right)/2.0;$cy=($SafeArea.Top+$SafeArea.Bottom)/2.0;$rx=($SafeArea.Right-$SafeArea.Left)/2.0;$ry=($SafeArea.Bottom-$SafeArea.Top)/2.0
            foreach($corner in $corners){if(([math]::Abs($corner.X-$cx)/$rx)+([math]::Abs($corner.Y-$cy)/$ry)-gt(1.0+$Epsilon)){return $false}}
            return $true
        }
        'rounded-rectangle' {
            $radius=[math]::Min(($SafeArea.Right-$SafeArea.Left)*0.12,($SafeArea.Bottom-$SafeArea.Top)*0.25)
            foreach($corner in $corners){
                $nearestX=[math]::Max($SafeArea.Left+$radius,[math]::Min($SafeArea.Right-$radius,$corner.X));$nearestY=[math]::Max($SafeArea.Top+$radius,[math]::Min($SafeArea.Bottom-$radius,$corner.Y))
                if($corner.X-lt$SafeArea.Left-$Epsilon-or$corner.X-gt$SafeArea.Right+$Epsilon-or$corner.Y-lt$SafeArea.Top-$Epsilon-or$corner.Y-gt$SafeArea.Bottom+$Epsilon){return $false}
                if(($corner.X-lt$SafeArea.Left+$radius-or$corner.X-gt$SafeArea.Right-$radius)-and($corner.Y-lt$SafeArea.Top+$radius-or$corner.Y-gt$SafeArea.Bottom-$radius)){
                    if([math]::Pow($corner.X-$nearestX,2)+[math]::Pow($corner.Y-$nearestY,2)-gt($radius*$radius+$Epsilon)){return $false}
                }
            }
            return $true
        }
        'archive' {return $null}
        'unknown' {return $null}
        default {return $Ink.Left-ge$SafeArea.Left-$Epsilon-and$Ink.Top-ge$SafeArea.Top-$Epsilon-and$Ink.Right-le$SafeArea.Right+$Epsilon-and$Ink.Bottom-le$SafeArea.Bottom+$Epsilon}
    }
}

function Get-SvgGroupOutline {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Group,
        [Parameter(Mandatory = $true)][System.Xml.XmlNamespaceManager]$Namespace
    )
    $candidates=[System.Collections.Generic.List[object]]::new()
    $geometryGroup=$Group.SelectSingleNode('./s:g[1]',$Namespace)
    if(-not$geometryGroup){$geometryGroup=$Group}
    foreach($element in $geometryGroup.SelectNodes('.//s:path|.//s:rect|.//s:ellipse|.//s:circle|.//s:polygon|.//s:polyline',$Namespace)){
        $fill=[string]$element.GetAttribute('fill');$stroke=[string]$element.GetAttribute('stroke')
        if($fill-eq'none'-and($stroke-eq'none'-or[string]::IsNullOrWhiteSpace($stroke))){continue}
        try{$points=@(Get-SvgElementPoints -Element $element -Boundary $Group)}catch{throw "Rendered outline parse failed for $([string]$Group.GetAttribute('data-cell-id')): $($_.Exception.Message)"}
        if($points.Count-lt2){continue}
        $length=0.0;for($i=1;$i-lt$points.Count;$i++){$length+=[math]::Sqrt([math]::Pow($points[$i].X-$points[$i-1].X,2)+[math]::Pow($points[$i].Y-$points[$i-1].Y,2))}
        $candidates.Add([pscustomobject]@{Points=$points;Length=$length;Element=$element.LocalName})
    }
    if($candidates.Count-eq0){return $null}
    $chosen=$candidates|Sort-Object Length -Descending|Select-Object -First 1
    [pscustomobject]@{Points=@($chosen.Points);Bounds=Get-PolylineBounds @($chosen.Points);Element=$chosen.Element}
}

function Get-SvgOutlineContact {
    param([Parameter(Mandatory = $true)][object]$Point,[Parameter(Mandatory = $true)][object]$Outline)
    [pscustomobject]@{Distance=Get-PointPolylineDistance $Point @($Outline.Points);Point=$Point;Bounds=$Outline.Bounds}
}

Export-ModuleMember -Function Get-DrawioShapeKind, Get-DrawioShapeSafeArea, Test-DrawioInkSafeArea, Get-SvgGroupOutline, Get-SvgOutlineContact
