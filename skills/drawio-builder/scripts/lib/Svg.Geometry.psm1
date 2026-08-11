Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Drawio.Core.psm1')

$script:CurveTolerance = 0.75
$script:Epsilon = 0.000001

function New-SvgMatrix {
    param(
        [double]$A = 1.0,
        [double]$B = 0.0,
        [double]$C = 0.0,
        [double]$D = 1.0,
        [double]$E = 0.0,
        [double]$F = 0.0
    )
    [pscustomobject]@{ A=$A; B=$B; C=$C; D=$D; E=$E; F=$F }
}

function Join-SvgMatrix {
    param([object]$Outer, [object]$Inner)
    New-SvgMatrix `
        -A ($Outer.A*$Inner.A + $Outer.C*$Inner.B) `
        -B ($Outer.B*$Inner.A + $Outer.D*$Inner.B) `
        -C ($Outer.A*$Inner.C + $Outer.C*$Inner.D) `
        -D ($Outer.B*$Inner.C + $Outer.D*$Inner.D) `
        -E ($Outer.A*$Inner.E + $Outer.C*$Inner.F + $Outer.E) `
        -F ($Outer.B*$Inner.E + $Outer.D*$Inner.F + $Outer.F)
}

function Convert-SvgPoint {
    param([object]$Point, [object]$Matrix)
    [pscustomobject]@{
        X = $Matrix.A*$Point.X + $Matrix.C*$Point.Y + $Matrix.E
        Y = $Matrix.B*$Point.X + $Matrix.D*$Point.Y + $Matrix.F
    }
}

function Get-SvgTransformMatrix {
    param([AllowNull()][string]$Transform)
    $matrix = New-SvgMatrix
    if ([string]::IsNullOrWhiteSpace($Transform)) { return $matrix }
    $matches = [regex]::Matches($Transform, '(?i)(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)')
    $consumed = ($matches | ForEach-Object { $_.Value }) -join ''
    $normalized = [regex]::Replace($Transform, '[\s,]+', '')
    $normalizedConsumed = [regex]::Replace($consumed, '[\s,]+', '')
    if ($matches.Count -eq 0 -or $normalized -ne $normalizedConsumed) { throw "Unsupported SVG transform: $Transform" }
    foreach ($match in $matches) {
        $name = $match.Groups[1].Value.ToLowerInvariant()
        $values = @([regex]::Matches($match.Groups[2].Value, '[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?') | ForEach-Object { ConvertTo-DrawioNumber $_.Value })
        $next = $null
        switch ($name) {
            'matrix' {
                if ($values.Count -ne 6) { throw "Invalid SVG matrix transform: $($match.Value)" }
                $next = New-SvgMatrix $values[0] $values[1] $values[2] $values[3] $values[4] $values[5]
            }
            'translate' {
                if ($values.Count -lt 1 -or $values.Count -gt 2) { throw "Invalid SVG translate transform: $($match.Value)" }
                $next = New-SvgMatrix -E $values[0] -F $(if ($values.Count -eq 2) { $values[1] } else { 0.0 })
            }
            'scale' {
                if ($values.Count -lt 1 -or $values.Count -gt 2) { throw "Invalid SVG scale transform: $($match.Value)" }
                $scaleY = if ($values.Count -eq 2) { $values[1] } else { $values[0] }
                $next = New-SvgMatrix -A $values[0] -D $scaleY
            }
            'rotate' {
                if ($values.Count -notin @(1,3)) { throw "Invalid SVG rotate transform: $($match.Value)" }
                $angle = $values[0] * [math]::PI / 180.0
                $rotation = New-SvgMatrix -A ([math]::Cos($angle)) -B ([math]::Sin($angle)) -C (-[math]::Sin($angle)) -D ([math]::Cos($angle))
                if ($values.Count -eq 3) {
                    $next = Join-SvgMatrix (New-SvgMatrix -E $values[1] -F $values[2]) (Join-SvgMatrix $rotation (New-SvgMatrix -E (-$values[1]) -F (-$values[2])))
                }
                else { $next = $rotation }
            }
            'skewx' {
                if ($values.Count -ne 1) { throw "Invalid SVG skewX transform: $($match.Value)" }
                $next = New-SvgMatrix -C ([math]::Tan($values[0]*[math]::PI/180.0))
            }
            'skewy' {
                if ($values.Count -ne 1) { throw "Invalid SVG skewY transform: $($match.Value)" }
                $next = New-SvgMatrix -B ([math]::Tan($values[0]*[math]::PI/180.0))
            }
        }
        $matrix = Join-SvgMatrix $matrix $next
    }
    $matrix
}

function Get-SvgCumulativeMatrix {
    param(
        [Parameter(Mandatory = $true)][System.Xml.XmlElement]$Element,
        [AllowNull()][System.Xml.XmlElement]$Boundary,
        [switch]$IncludeElement
    )
    $chain = [System.Collections.Generic.List[object]]::new()
    $node = if ($IncludeElement) { $Element } else { $Element.ParentNode }
    while ($node -and $node.NodeType -eq [System.Xml.XmlNodeType]::Element) {
        if ($Boundary -and $node -eq $Boundary.ParentNode) { break }
        $chain.Add($node)
        if ($Boundary -and $node -eq $Boundary) { break }
        $node = $node.ParentNode
    }
    $matrix = New-SvgMatrix
    for ($index = $chain.Count - 1; $index -ge 0; $index--) {
        $local = Get-SvgTransformMatrix ([string]$chain[$index].GetAttribute('transform'))
        $matrix = Join-SvgMatrix $matrix $local
    }
    $matrix
}

function Add-SvgPoint {
    param([System.Collections.Generic.List[object]]$Points, [double]$X, [double]$Y)
    if ($Points.Count -eq 0 -or [math]::Abs($Points[$Points.Count-1].X-$X) -gt $script:Epsilon -or [math]::Abs($Points[$Points.Count-1].Y-$Y) -gt $script:Epsilon) {
        $Points.Add([pscustomobject]@{ X=$X; Y=$Y })
    }
}

function Get-SvgPathTokens {
    param([string]$Data)
    $matches = [regex]::Matches($Data, '[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?')
    $residual = [regex]::Replace($Data, '[AaCcHhLlMmQqSsTtVvZz]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?|[\s,]+', '')
    if ($residual.Length -gt 0) { throw "Unsupported SVG path token: $residual" }
    @($matches | ForEach-Object { $_.Value })
}

function Get-CubicPoint {
    param($P0,$P1,$P2,$P3,[double]$T)
    $u=1.0-$T
    [pscustomobject]@{ X=$u*$u*$u*$P0.X+3*$u*$u*$T*$P1.X+3*$u*$T*$T*$P2.X+$T*$T*$T*$P3.X; Y=$u*$u*$u*$P0.Y+3*$u*$u*$T*$P1.Y+3*$u*$T*$T*$P2.Y+$T*$T*$T*$P3.Y }
}

function Get-QuadraticPoint {
    param($P0,$P1,$P2,[double]$T)
    $u=1.0-$T
    [pscustomobject]@{ X=$u*$u*$P0.X+2*$u*$T*$P1.X+$T*$T*$P2.X; Y=$u*$u*$P0.Y+2*$u*$T*$P1.Y+$T*$T*$P2.Y }
}

function Get-CurveSteps {
    param([object[]]$Points,[double]$Tolerance)
    $length=0.0
    for($i=1;$i -lt $Points.Count;$i++){ $length += [math]::Sqrt([math]::Pow($Points[$i].X-$Points[$i-1].X,2)+[math]::Pow($Points[$i].Y-$Points[$i-1].Y,2)) }
    [math]::Max(2,[math]::Min(256,[math]::Ceiling($length/[math]::Max($Tolerance,0.1))))
}

function Get-ArcPoints {
    param($Start,[double]$Rx,[double]$Ry,[double]$Rotation,[int]$LargeArc,[int]$Sweep,$End,[double]$Tolerance)
    $rx=[math]::Abs($Rx); $ry=[math]::Abs($Ry)
    if($rx -le $script:Epsilon -or $ry -le $script:Epsilon){ return @($End) }
    $phi=$Rotation*[math]::PI/180.0; $cosPhi=[math]::Cos($phi); $sinPhi=[math]::Sin($phi)
    $dx=($Start.X-$End.X)/2.0; $dy=($Start.Y-$End.Y)/2.0
    $xPrime=$cosPhi*$dx+$sinPhi*$dy; $yPrime=-$sinPhi*$dx+$cosPhi*$dy
    $lambda=($xPrime*$xPrime)/($rx*$rx)+($yPrime*$yPrime)/($ry*$ry)
    if($lambda -gt 1.0){ $scale=[math]::Sqrt($lambda); $rx*=$scale; $ry*=$scale }
    $numerator=[math]::Max(0.0,(($rx*$rx*$ry*$ry)-($rx*$rx*$yPrime*$yPrime)-($ry*$ry*$xPrime*$xPrime))/(($rx*$rx*$yPrime*$yPrime)+($ry*$ry*$xPrime*$xPrime)))
    $factor=[math]::Sqrt($numerator); if($LargeArc -eq $Sweep){$factor=-$factor}
    $cxPrime=$factor*($rx*$yPrime/$ry); $cyPrime=$factor*(-$ry*$xPrime/$rx)
    $cx=$cosPhi*$cxPrime-$sinPhi*$cyPrime+($Start.X+$End.X)/2.0
    $cy=$sinPhi*$cxPrime+$cosPhi*$cyPrime+($Start.Y+$End.Y)/2.0
    $ux=($xPrime-$cxPrime)/$rx; $uy=($yPrime-$cyPrime)/$ry
    $vx=(-$xPrime-$cxPrime)/$rx; $vy=(-$yPrime-$cyPrime)/$ry
    $theta=[math]::Atan2($uy,$ux)
    $delta=[math]::Atan2($ux*$vy-$uy*$vx,$ux*$vx+$uy*$vy)
    if($Sweep -eq 0 -and $delta -gt 0){$delta-=2*[math]::PI}; if($Sweep -eq 1 -and $delta -lt 0){$delta+=2*[math]::PI}
    $steps=[math]::Max(2,[math]::Min(512,[math]::Ceiling([math]::Abs($delta)*[math]::Max($rx,$ry)/[math]::Max($Tolerance,0.1))))
    $result=[System.Collections.Generic.List[object]]::new()
    for($i=1;$i -le $steps;$i++){ $angle=$theta+$delta*$i/$steps; $result.Add([pscustomobject]@{X=$cx+$cosPhi*$rx*[math]::Cos($angle)-$sinPhi*$ry*[math]::Sin($angle);Y=$cy+$sinPhi*$rx*[math]::Cos($angle)+$cosPhi*$ry*[math]::Sin($angle)}) }
    @($result)
}

function Get-SvgPathPoints {
    param(
        [Parameter(Mandatory = $true)][string]$Data,
        [AllowNull()][object]$Matrix,
        [double]$Tolerance = $script:CurveTolerance
    )
    $tokens=Get-SvgPathTokens $Data
    $points=[System.Collections.Generic.List[object]]::new(); $i=0; $command=''; $current=[pscustomobject]@{X=0.0;Y=0.0}; $start=$current; $lastCubic=$null; $lastQuad=$null
    $arity=@{M=2;L=2;H=1;V=1;C=6;S=4;Q=4;T=2;A=7;Z=0}
    while($i -lt $tokens.Count){
        if($tokens[$i] -match '^[A-Za-z]$'){ $command=$tokens[$i]; $i++ } elseif(-not $command){ throw 'SVG path starts without a command' }
        $upper=$command.ToUpperInvariant(); $relative=$command -cmatch '[a-z]'
        if(-not $arity.ContainsKey($upper)){ throw "Unsupported SVG path command: $command" }
        if($upper -eq 'Z'){ Add-SvgPoint $points $start.X $start.Y; $current=$start; $lastCubic=$null; $lastQuad=$null; $command=''; continue }
        $need=$arity[$upper]; if($i+$need -gt $tokens.Count){ throw "Incomplete SVG path command: $command" }
        $values=@(); for($n=0;$n -lt $need;$n++){ if($tokens[$i+$n] -match '^[A-Za-z]$'){throw "Incomplete SVG path command: $command"}; $values+=ConvertTo-DrawioNumber $tokens[$i+$n] }; $i+=$need
        $originX=if($relative){$current.X}else{0.0}; $originY=if($relative){$current.Y}else{0.0}
        switch($upper){
            'M' { $current=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; $start=$current; Add-SvgPoint $points $current.X $current.Y; $command=if($relative){'l'}else{'L'} }
            'L' { $current=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; Add-SvgPoint $points $current.X $current.Y }
            'H' { $current=[pscustomobject]@{X=$originX+$values[0];Y=$current.Y}; Add-SvgPoint $points $current.X $current.Y }
            'V' { $current=[pscustomobject]@{X=$current.X;Y=$originY+$values[0]}; Add-SvgPoint $points $current.X $current.Y }
            'C' { $p0=$current; $p1=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; $p2=[pscustomobject]@{X=$originX+$values[2];Y=$originY+$values[3]}; $p3=[pscustomobject]@{X=$originX+$values[4];Y=$originY+$values[5]}; $steps=Get-CurveSteps @($p0,$p1,$p2,$p3) $Tolerance; for($n=1;$n -le $steps;$n++){$p=Get-CubicPoint $p0 $p1 $p2 $p3 ($n/$steps);Add-SvgPoint $points $p.X $p.Y}; $current=$p3; $lastCubic=$p2; $lastQuad=$null }
            'S' { $p0=$current; $p1=if($lastCubic){[pscustomobject]@{X=2*$p0.X-$lastCubic.X;Y=2*$p0.Y-$lastCubic.Y}}else{$p0}; $p2=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; $p3=[pscustomobject]@{X=$originX+$values[2];Y=$originY+$values[3]}; $steps=Get-CurveSteps @($p0,$p1,$p2,$p3) $Tolerance; for($n=1;$n -le $steps;$n++){$p=Get-CubicPoint $p0 $p1 $p2 $p3 ($n/$steps);Add-SvgPoint $points $p.X $p.Y}; $current=$p3; $lastCubic=$p2; $lastQuad=$null }
            'Q' { $p0=$current; $p1=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; $p2=[pscustomobject]@{X=$originX+$values[2];Y=$originY+$values[3]}; $steps=Get-CurveSteps @($p0,$p1,$p2) $Tolerance; for($n=1;$n -le $steps;$n++){$p=Get-QuadraticPoint $p0 $p1 $p2 ($n/$steps);Add-SvgPoint $points $p.X $p.Y}; $current=$p2; $lastQuad=$p1; $lastCubic=$null }
            'T' { $p0=$current; $p1=if($lastQuad){[pscustomobject]@{X=2*$p0.X-$lastQuad.X;Y=2*$p0.Y-$lastQuad.Y}}else{$p0}; $p2=[pscustomobject]@{X=$originX+$values[0];Y=$originY+$values[1]}; $steps=Get-CurveSteps @($p0,$p1,$p2) $Tolerance; for($n=1;$n -le $steps;$n++){$p=Get-QuadraticPoint $p0 $p1 $p2 ($n/$steps);Add-SvgPoint $points $p.X $p.Y}; $current=$p2; $lastQuad=$p1; $lastCubic=$null }
            'A' { $end=[pscustomobject]@{X=$originX+$values[5];Y=$originY+$values[6]}; foreach($p in @(Get-ArcPoints $current $values[0] $values[1] $values[2] ([int]$values[3]) ([int]$values[4]) $end $Tolerance)){Add-SvgPoint $points $p.X $p.Y}; $current=$end; $lastCubic=$null; $lastQuad=$null }
        }
        if($upper -notin @('C','S')){$lastCubic=$null}; if($upper -notin @('Q','T')){$lastQuad=$null}
    }
    $output=@($points)
    if($Matrix){ $output=@($output|ForEach-Object{Convert-SvgPoint $_ $Matrix}) }
    $output
}

function Get-SvgElementPoints {
    param([Parameter(Mandatory = $true)][System.Xml.XmlElement]$Element,[AllowNull()][System.Xml.XmlElement]$Boundary,[double]$Tolerance=$script:CurveTolerance)
    $matrix=Get-SvgCumulativeMatrix -Element $Element -Boundary $Boundary -IncludeElement
    switch($Element.LocalName){
        'path' { return @(Get-SvgPathPoints -Data ([string]$Element.d) -Matrix $matrix -Tolerance $Tolerance) }
        'line' { return @((Convert-SvgPoint ([pscustomobject]@{X=ConvertTo-DrawioNumber $Element.x1;Y=ConvertTo-DrawioNumber $Element.y1}) $matrix),(Convert-SvgPoint ([pscustomobject]@{X=ConvertTo-DrawioNumber $Element.x2;Y=ConvertTo-DrawioNumber $Element.y2}) $matrix)) }
        'polyline' { $raw=[regex]::Matches([string]$Element.points,'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?'); if($raw.Count%2-ne 0){throw 'Invalid SVG polyline points'}; $r=@();for($j=0;$j-lt$raw.Count;$j+=2){$r+=Convert-SvgPoint ([pscustomobject]@{X=ConvertTo-DrawioNumber $raw[$j].Value;Y=ConvertTo-DrawioNumber $raw[$j+1].Value}) $matrix};return $r }
        'polygon' { $raw=[regex]::Matches([string]$Element.points,'[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?'); if($raw.Count%2-ne 0){throw 'Invalid SVG polygon points'}; $r=@();for($j=0;$j-lt$raw.Count;$j+=2){$r+=Convert-SvgPoint ([pscustomobject]@{X=ConvertTo-DrawioNumber $raw[$j].Value;Y=ConvertTo-DrawioNumber $raw[$j+1].Value}) $matrix};if($r.Count-gt 0){$r+=,$r[0]};return $r }
        'rect' { $x=ConvertTo-DrawioNumber $Element.x -AllowMissing;$y=ConvertTo-DrawioNumber $Element.y -AllowMissing;$w=ConvertTo-DrawioNumber $Element.width;$h=ConvertTo-DrawioNumber $Element.height;$raw=@([pscustomobject]@{X=$x;Y=$y},[pscustomobject]@{X=$x+$w;Y=$y},[pscustomobject]@{X=$x+$w;Y=$y+$h},[pscustomobject]@{X=$x;Y=$y+$h},[pscustomobject]@{X=$x;Y=$y});return @($raw|ForEach-Object{Convert-SvgPoint $_ $matrix}) }
        'ellipse' { $cx=ConvertTo-DrawioNumber $Element.cx;$cy=ConvertTo-DrawioNumber $Element.cy;$rx=ConvertTo-DrawioNumber $Element.rx;$ry=ConvertTo-DrawioNumber $Element.ry;$r=@();for($j=0;$j-le 48;$j++){$a=2*[math]::PI*$j/48;$r+=Convert-SvgPoint ([pscustomobject]@{X=$cx+$rx*[math]::Cos($a);Y=$cy+$ry*[math]::Sin($a)}) $matrix};return $r }
        'circle' { $cx=ConvertTo-DrawioNumber $Element.cx;$cy=ConvertTo-DrawioNumber $Element.cy;$radius=ConvertTo-DrawioNumber $Element.r;$r=@();for($j=0;$j-le 48;$j++){$a=2*[math]::PI*$j/48;$r+=Convert-SvgPoint ([pscustomobject]@{X=$cx+$radius*[math]::Cos($a);Y=$cy+$radius*[math]::Sin($a)}) $matrix};return $r }
        default { throw "Unsupported SVG geometry element: $($Element.LocalName)" }
    }
}

function Get-SvgSegments {
    param([string]$ElementId,[object[]]$Points)
    $segments=[System.Collections.Generic.List[object]]::new()
    for($i=1;$i-lt$Points.Count;$i++){
        $dx=$Points[$i].X-$Points[$i-1].X;$dy=$Points[$i].Y-$Points[$i-1].Y
        $length=[math]::Sqrt($dx*$dx+$dy*$dy)
        if($length-le$script:Epsilon){continue}
        $segments.Add([pscustomobject]@{Element=$ElementId;Index=$i-1;X1=$Points[$i-1].X;Y1=$Points[$i-1].Y;X2=$Points[$i].X;Y2=$Points[$i].Y;MinimumX=[math]::Min($Points[$i-1].X,$Points[$i].X);MaximumX=[math]::Max($Points[$i-1].X,$Points[$i].X);MinimumY=[math]::Min($Points[$i-1].Y,$Points[$i].Y);MaximumY=[math]::Max($Points[$i-1].Y,$Points[$i].Y);Length=$length})
    }
    @($segments)
}

function Get-PointSegmentDistance {
    param([object]$Point,[object]$Segment)
    $dx=$Segment.X2-$Segment.X1;$dy=$Segment.Y2-$Segment.Y1;$den=$dx*$dx+$dy*$dy
    if($den-le$script:Epsilon){return [math]::Sqrt([math]::Pow($Point.X-$Segment.X1,2)+[math]::Pow($Point.Y-$Segment.Y1,2))}
    $t=(($Point.X-$Segment.X1)*$dx+($Point.Y-$Segment.Y1)*$dy)/$den;$t=[math]::Max(0.0,[math]::Min(1.0,[double]$t))
    [math]::Sqrt([math]::Pow($Point.X-($Segment.X1+$t*$dx),2)+[math]::Pow($Point.Y-($Segment.Y1+$t*$dy),2))
}

function Get-PointPolylineDistance {
    param([object]$Point,[object[]]$Points)
    $segments=@(Get-SvgSegments '' $Points);if($segments.Count-eq 0){return [double]::PositiveInfinity}
    ($segments|ForEach-Object{Get-PointSegmentDistance $Point $_}|Measure-Object -Minimum).Minimum
}

function Get-PolylineBounds {
    param([object[]]$Points)
    if($Points.Count-eq 0){return $null}
    [pscustomobject]@{Left=($Points|Measure-Object X -Minimum).Minimum;Top=($Points|Measure-Object Y -Minimum).Minimum;Right=($Points|Measure-Object X -Maximum).Maximum;Bottom=($Points|Measure-Object Y -Maximum).Maximum}
}

function Test-PointInPolygon {
    param([object]$Point,[object[]]$Polygon)
    if($Polygon.Count-lt3){return $false}
    $inside=$false;$j=$Polygon.Count-1
    for($i=0;$i-lt$Polygon.Count;$i++){
        $a=$Polygon[$i];$b=$Polygon[$j]
        if((($a.Y-gt$Point.Y)-ne($b.Y-gt$Point.Y))-and($Point.X-lt(($b.X-$a.X)*($Point.Y-$a.Y)/($b.Y-$a.Y)+$a.X))){$inside=-not$inside}
        $j=$i
    }
    $inside
}

function Get-SegmentPolygonRelation {
    param([object]$Segment,[object[]]$Polygon,[double]$BorderTolerance=1.5,[double]$SampleStep=1.0)
    $steps=[math]::Max(1,[math]::Min(64,[math]::Ceiling($Segment.Length/[math]::Max($SampleStep,0.25))));$inside=0;$border=0
    for($i=0;$i-le$steps;$i++){
        $t=$i/$steps;$point=[pscustomobject]@{X=$Segment.X1+($Segment.X2-$Segment.X1)*$t;Y=$Segment.Y1+($Segment.Y2-$Segment.Y1)*$t}
        if(Test-PointInPolygon $point $Polygon){$inside++}elseif((Get-PointPolylineDistance $point $Polygon)-le$BorderTolerance){$border++}
    }
    [pscustomobject]@{InteriorSamples=$inside;BorderSamples=$border;SampleCount=$steps+1}
}

function Test-SvgSegmentIntersection {
    param([object]$A1,[object]$A2,[object]$B1,[object]$B2,[double]$Tolerance=0.000001)
    $cross=($A2.X-$A1.X)*($B2.Y-$B1.Y)-($A2.Y-$A1.Y)*($B2.X-$B1.X)
    $deltaX=$B1.X-$A1.X;$deltaY=$B1.Y-$A1.Y
    if([math]::Abs($cross)-le$Tolerance){
        if([math]::Abs($deltaX*($A2.Y-$A1.Y)-$deltaY*($A2.X-$A1.X))-gt$Tolerance){return $false}
        return ([math]::Max([math]::Min($A1.X,$A2.X),[math]::Min($B1.X,$B2.X))-le[math]::Min([math]::Max($A1.X,$A2.X),[math]::Max($B1.X,$B2.X))+$Tolerance) -and ([math]::Max([math]::Min($A1.Y,$A2.Y),[math]::Min($B1.Y,$B2.Y))-le[math]::Min([math]::Max($A1.Y,$A2.Y),[math]::Max($B1.Y,$B2.Y))+$Tolerance)
    }
    $t=($deltaX*($B2.Y-$B1.Y)-$deltaY*($B2.X-$B1.X))/$cross
    $u=($deltaX*($A2.Y-$A1.Y)-$deltaY*($A2.X-$A1.X))/$cross
    $t-ge-$Tolerance-and$t-le(1.0+$Tolerance)-and$u-ge-$Tolerance-and$u-le(1.0+$Tolerance)
}

function Test-SvgBoxPolygonOverlap {
    param([object]$Box,[object[]]$Polygon,[double]$Inset=0.0)
    if($Polygon.Count-lt3){return $null}
    $left=$Box.Left+$Inset;$top=$Box.Top+$Inset;$right=$Box.Right-$Inset;$bottom=$Box.Bottom-$Inset
    if($left-ge$right-or$top-ge$bottom){return $false}
    $corners=@([pscustomobject]@{X=$left;Y=$top},[pscustomobject]@{X=$right;Y=$top},[pscustomobject]@{X=$right;Y=$bottom},[pscustomobject]@{X=$left;Y=$bottom})
    foreach($corner in $corners){if(Test-PointInPolygon $corner $Polygon){return $true}}
    foreach($point in $Polygon){if($point.X-gt$left-and$point.X-lt$right-and$point.Y-gt$top-and$point.Y-lt$bottom){return $true}}
    $boxEdges=@(@($corners[0],$corners[1]),@($corners[1],$corners[2]),@($corners[2],$corners[3]),@($corners[3],$corners[0]))
    for($index=1;$index-lt$Polygon.Count;$index++){foreach($edge in $boxEdges){if(Test-SvgSegmentIntersection $Polygon[$index-1] $Polygon[$index] $edge[0] $edge[1]){return $true}}}
    $false
}

Export-ModuleMember -Function New-SvgMatrix, Join-SvgMatrix, Convert-SvgPoint, Get-SvgTransformMatrix, Get-SvgCumulativeMatrix, Get-SvgPathPoints, Get-SvgElementPoints, Get-SvgSegments, Get-PointSegmentDistance, Get-PointPolylineDistance, Get-PolylineBounds, Test-PointInPolygon, Get-SegmentPolygonRelation, Test-SvgSegmentIntersection, Test-SvgBoxPolygonOverlap
