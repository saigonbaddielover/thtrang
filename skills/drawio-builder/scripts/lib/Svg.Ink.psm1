Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Drawio.Core.psm1')
Import-Module (Join-Path $PSScriptRoot 'Svg.Geometry.psm1')
Add-Type -AssemblyName System.Drawing

$script:XLinkNamespace='http://www.w3.org/1999/xlink'

function Merge-SvgBounds {
    param([object[]]$Bounds)
    $items=@($Bounds|Where-Object{$_})
    if($items.Count-eq0){return $null}
    [pscustomobject]@{Left=($items|Measure-Object Left -Minimum).Minimum;Top=($items|Measure-Object Top -Minimum).Minimum;Right=($items|Measure-Object Right -Maximum).Maximum;Bottom=($items|Measure-Object Bottom -Maximum).Maximum}
}

function Convert-SvgBox {
    param([object]$Box,[object]$Matrix)
    $points=@(
        (Convert-SvgPoint ([pscustomobject]@{X=$Box.Left;Y=$Box.Top}) $Matrix),
        (Convert-SvgPoint ([pscustomobject]@{X=$Box.Right;Y=$Box.Top}) $Matrix),
        (Convert-SvgPoint ([pscustomobject]@{X=$Box.Right;Y=$Box.Bottom}) $Matrix),
        (Convert-SvgPoint ([pscustomobject]@{X=$Box.Left;Y=$Box.Bottom}) $Matrix)
    )
    [pscustomobject]@{Left=($points|Measure-Object X -Minimum).Minimum;Top=($points|Measure-Object Y -Minimum).Minimum;Right=($points|Measure-Object X -Maximum).Maximum;Bottom=($points|Measure-Object Y -Maximum).Maximum}
}

function Get-SvgInheritedValue {
    param([System.Xml.XmlElement]$Element,[System.Xml.XmlElement]$Boundary,[string]$Name,[string]$Default)
    $node=$Element
    while($node-and$node-ne$Boundary.ParentNode){
        if($node.NodeType-eq[System.Xml.XmlNodeType]::Element){
            $value=[string]$node.GetAttribute($Name);if($value){return $value}
            $style=[string]$node.GetAttribute('style')
            if($style){$match=[regex]::Match($style,'(?:^|;)\s*'+[regex]::Escape($Name)+'\s*:\s*([^;]+)');if($match.Success){return $match.Groups[1].Value.Trim()}}
        }
        $node=$node.ParentNode
    }
    $Default
}

function Get-SvgImageInkBounds {
    param([System.Xml.XmlElement]$Image,[System.Xml.XmlElement]$Boundary)
    $href=[string]$Image.GetAttribute('href');if(-not$href){$href=[string]$Image.GetAttribute('href',$script:XLinkNamespace)}
    $match=[regex]::Match($href,'^data:image/png;base64,(.+)$',[System.Text.RegularExpressions.RegexOptions]::Singleline)
    if(-not$match.Success){throw 'Unsupported embedded label image format'}
    $bytes=[Convert]::FromBase64String($match.Groups[1].Value);$stream=[System.IO.MemoryStream]::new($bytes,$false);$bitmap=$null
    try{
        $bitmap=[System.Drawing.Bitmap]::new($stream);$minX=$bitmap.Width;$minY=$bitmap.Height;$maxX=-1;$maxY=-1
        for($y=0;$y-lt$bitmap.Height;$y++){for($x=0;$x-lt$bitmap.Width;$x++){if($bitmap.GetPixel($x,$y).A-eq0){continue};if($x-lt$minX){$minX=$x};if($x-gt$maxX){$maxX=$x};if($y-lt$minY){$minY=$y};if($y-gt$maxY){$maxY=$y}}}
        if($maxX-lt0-or$maxY-lt0){return $null}
        $imageX=ConvertTo-DrawioNumber $Image.x;$imageY=ConvertTo-DrawioNumber $Image.y;$width=ConvertTo-DrawioNumber $Image.width;$height=ConvertTo-DrawioNumber $Image.height
        $box=[pscustomobject]@{Left=$imageX+$minX/$bitmap.Width*$width;Top=$imageY+$minY/$bitmap.Height*$height;Right=$imageX+($maxX+1)/$bitmap.Width*$width;Bottom=$imageY+($maxY+1)/$bitmap.Height*$height}
        Convert-SvgBox $box (Get-SvgCumulativeMatrix -Element $Image -Boundary $Boundary -IncludeElement)
    }finally{if($bitmap){$bitmap.Dispose()};$stream.Dispose()}
}

function Get-SvgTextInkBounds {
    param([System.Xml.XmlElement]$Text,[System.Xml.XmlElement]$Boundary)
    $value=[string]$Text.InnerText;if([string]::IsNullOrWhiteSpace($value)){return $null}
    $x=ConvertTo-DrawioNumber (([string]$Text.x-split'[\s,]+')[0]);$y=ConvertTo-DrawioNumber (([string]$Text.y-split'[\s,]+')[0])
    $fontSize=ConvertTo-DrawioNumber ((Get-SvgInheritedValue $Text $Boundary 'font-size' '10')-replace'px$','');$requestedFont=Get-SvgInheritedValue $Text $Boundary 'font-family' 'Arial'
    $weight=Get-SvgInheritedValue $Text $Boundary 'font-weight' 'normal';$fontStyleValue=Get-SvgInheritedValue $Text $Boundary 'font-style' 'normal';$anchor=Get-SvgInheritedValue $Text $Boundary 'text-anchor' 'start'
    $style=[System.Drawing.FontStyle]::Regular;if($weight-in@('bold','600','700','800','900')){$style=$style-bor[System.Drawing.FontStyle]::Bold};if($fontStyleValue-eq'italic'){$style=$style-bor[System.Drawing.FontStyle]::Italic}
    $family=$null;$fallback=$false;$path=[System.Drawing.Drawing2D.GraphicsPath]::new();$surface=[System.Drawing.Bitmap]::new(1,1);$graphics=[System.Drawing.Graphics]::FromImage($surface);$format=[System.Drawing.StringFormat]::GenericTypographic.Clone()
    try{
        try{$family=[System.Drawing.FontFamily]::new($requestedFont)}catch{$family=[System.Drawing.FontFamily]::GenericSansSerif;$fallback=$true}
        $ascent=$family.GetCellAscent($style)/$family.GetEmHeight($style)*$fontSize;$path.AddString($value,$family,[int]$style,[single]$fontSize,[System.Drawing.PointF]::new(0,-$ascent),$format)
        $font=[System.Drawing.Font]::new($family,[single]$fontSize,$style,[System.Drawing.GraphicsUnit]::Pixel);try{$advance=$graphics.MeasureString($value,$font,[int]::MaxValue,$format).Width}finally{$font.Dispose()}
        $originX=$x;if($anchor-eq'middle'){$originX-=$advance/2.0};if($anchor-eq'end'){$originX-=$advance}
        $raw=$path.GetBounds();$box=[pscustomobject]@{Left=$originX+$raw.Left;Top=$y+$raw.Top;Right=$originX+$raw.Right;Bottom=$y+$raw.Bottom};$transformed=Convert-SvgBox $box (Get-SvgCumulativeMatrix -Element $Text -Boundary $Boundary -IncludeElement)
        [pscustomobject]@{Left=$transformed.Left;Top=$transformed.Top;Right=$transformed.Right;Bottom=$transformed.Bottom;FontFallback=$fallback;RequestedFont=$requestedFont;RenderedFont=$family.Name}
    }finally{$format.Dispose();$graphics.Dispose();$surface.Dispose();$path.Dispose();if($family-and$family-ne[System.Drawing.FontFamily]::GenericSansSerif){$family.Dispose()}}
}

function Get-SvgLabelInkBounds {
    param([System.Xml.XmlElement]$Group,[System.Xml.XmlNamespaceManager]$Namespace)
    $bounds=[System.Collections.Generic.List[object]]::new();$fallbacks=[System.Collections.Generic.List[object]]::new()
    foreach($switch in $Group.SelectNodes('.//s:switch',$Namespace)){
        $owner=$switch.ParentNode;$nested=$false
        while($owner-and$owner-ne$Group){if($owner-is[System.Xml.XmlElement]-and$owner.LocalName-eq'g'-and$owner.HasAttribute('data-cell-id')){$nested=$true;break};$owner=$owner.ParentNode}
        if($nested){continue}
        foreach($image in $switch.SelectNodes('./s:image',$Namespace)){$item=Get-SvgImageInkBounds $image $Group;if($item){$bounds.Add($item)}}
    }
    if($bounds.Count-eq0){
        foreach($text in $Group.SelectNodes('.//s:text',$Namespace)){
            $owner=$text.ParentNode;$nested=$false
            while($owner-and$owner-ne$Group){if($owner-is[System.Xml.XmlElement]-and$owner.LocalName-eq'g'-and$owner.HasAttribute('data-cell-id')){$nested=$true;break};$owner=$owner.ParentNode}
            if($nested){continue}
            $item=Get-SvgTextInkBounds $text $Group;if($item){$bounds.Add($item);if($item.FontFallback){$fallbacks.Add([pscustomobject]@{Requested=$item.RequestedFont;Rendered=$item.RenderedFont})}}
        }
    }
    $merged=Merge-SvgBounds @($bounds);if(-not$merged){return $null}
    [pscustomobject]@{Left=$merged.Left;Top=$merged.Top;Right=$merged.Right;Bottom=$merged.Bottom;FontFallbacks=@($fallbacks)}
}

Export-ModuleMember -Function Merge-SvgBounds, Convert-SvgBox, Get-SvgImageInkBounds, Get-SvgTextInkBounds, Get-SvgLabelInkBounds
