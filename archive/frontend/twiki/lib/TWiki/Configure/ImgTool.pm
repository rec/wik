# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2006-2018 TWiki Contributors. All Rights Reserved.
# TWiki Contributors are listed in the AUTHORS file in the root of
# this distribution. NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

package TWiki::Configure::ImgTool;
use warnings;
use strict;

=begin twiki

---+!! package TWiki::Configure::ImgTool

This class is a singleton that offers URLs for the images (logos,
warning, info) used during configuration - when neither =pub= nor
=data= nor =template= directories are reliably available.

All the methods can be called either as class methods or as object
methods on the singleton:

   * Class method: %BR%
     $img = "=&lt;img src=" . TWiki::Configure::ImgTool->logo . "/&gt;"
   * Object method: %BR%
     my $imgtool = TWiki::Configure::ImgTool->instance;
     $img = "=&lt;img src=" . $imgtool->logo . "/&gt;"

=cut

=pod

---++ Class Method instance()

Returns the singleton object.

=cut

my $imgTool = bless {},__PACKAGE__;
sub instance { return $imgTool; }


my $logo140x40 = <<ENDBASE64;
R0lGODlhjAAoAPcAAHJycuMXAOMYAuMaBOMcBuMeCP8PAP8OCf8RAP8VAP8SCf8WCf8aAP8eAP8Z
Cf8eCf8dEeQgCuQiDOQkDuQnEuUpE+UpFOUsF+UuGeYwG+YxHf8hAP8lAP8iCf8lCf8pAP8tAP8q
Cf8uCf8pF/8xAP82AP8xCf81Cf86AP89AP85Cf89Cf86HeY1IeY3JOY4Jec7KOc8KP9BAP9FAP9B
Cf9FCf9JAP9NAP9JCf9NCf9AGf9SAP9WAP9RCf9VCf9ZAP9dAP9YCf9aCf9cCf9fCedALehBL+hC
MOhFM+hINulKOOlMO+lPPf9LK/9hAP9lAP9hCf9jCf9mCf9pAP9tAP9pCf9rCf9uCf9xAP91AP9w
Cf9yCf93Df95AP99AP9+Gv9tI+pSQepUQ+pVRepZSetcTP9OTexiU+xlVexnWO1sXe1vYO1wYu5z
Zu51Z+51aO56be98b+9+cf9zbf+BAP+EAP+GD/+KAP+OAP+MEP+RAP+VAP+ZAP+aBf+dAP+VH/+L
Lf+RIP+QLv+cLv+XOP+ZOv+dOv+gAP+lAP+pAP+tAP+xAP+1AP+5AP+9AP+gIP+lJv+gOv+lPP+L
Tv+OTv+RTv+VTv+ZTv+eTu+BdfCEePCJff+Bc/+hTv+lTv+qTv+iVv+nU/+wUf+4XP+maf+va/+i
cv+lcv+ocv++ZvTAAPTBBv/BAP/GAP/JAP/NAPXGG/XHH//RAP/TBP/VAP/YAP/eGPXIIPXJJPXK
Kv/aI//bJvfUUffWWvfWXPjYYvjcc/nddfndeP/kSf/mYpubm/GNgfGPhPGRhvGSiPKVivKWjP+W
j/KckvOimfSmnvSqofWtpfWwqfW0rf+xoPa4sfa8tfe/uPfBu/fDvf/Ws//fuPrkk/rll/rlmfrm
nfvppvvqqv/ms/vrsP/rs8D///jGwfjJw/jJxP/Jx//MxfjNyfnSzvnV0frZ1frb2P/hwv/mx//j
yv/lyv/qyv/tyv/q1//u2vzwxf/1wf3wyv/24f/z6//16//9+v///yH5BAEAAOUALAAAAACMACgA
AAj+AMsJFJiPmK5Zsl65ctWKFStHjhoxYrRIkaJEiBAdOuSHD589j0ZtG0iypMmT5coIVHmSJcqX
MGOadDmQZsxhtWjJSriw4cOIEytezLix40c9evDckSSzKUubNZvChCpVILaVUZvayrlTIUOHECVS
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
ENDBASE64

=pod

---++ Class Method logo()

Returns the URL for the TWiki 140x40 logo (gif).

=cut

sub logo {
    return "data:image/gif;base64,$logo140x40";
}


my $logo34x26 = <<ENDOFPNG;
iVBORw0KGgoAAAANSUhEUgAAACIAAAAaCAYAAADSbo4CAAAABHNCSVQICAgIfAhkiAAAABl0RVh0
U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAIlSURBVHictZc9aBRBFMd/E8/zsFFLkQuk
UNAUFoqNaGMh2EQQTCNWgoUgiiCkjBaKjaWFIAgW2qQTFC1EAnYiCJJE8QuSwGFhuuRmZp/Fnnf7
NR97ufvDsMyyb+e3//fmMatEhL6W1TFgFjgCHAKaACSAzQxTmA/uCZZ1LJ8xfMDylIvZBdxSIgLL
qgncBW4BO3JP+BcOwb3GconL8icEMtG7zgG3cxAJoLc9zqJ5EOfIElPAF6DldWEYV9J5F8sU12TN
B9IAzvchsrXQOAy7j6b3XMMW5qYLPxaKME0sp4AXIZBpqPiafTMwec8XW1Z3A1ZKIGA5EAptkHCw
0tqkHkNfmiqQ/WEQzS5njutKeu8o18rOGBB3wQ0jXQES8S43yK8nsPZqkKY9x+HE43z06jtYvJnG
JICxg9TUdLfhsBI2O2A7g7nsLUdvbcD6p7itHOVIbM8o6n/Ti+krYwWRUYPEdtKiRu5IbAsvquiI
D2ZkIDE1UietTpCQtTE1MjIQH4zLEdf2HxuIr0aGqa8KEBNlra9GwiCtiuicJjD8zp2qDOWTlgtE
PDH5cY7TSoUc+RrVQzo/4eV86oL03Fhdiu0jbSxngLcuECX3OYlhMSo923vmL5YZPsr7ahARmFfP
MczWXrw+3CaGOSyPWJGtLEh6itdcR/Om9im9WBvhWmmheYjmG5PqKm3VPzCp3A/WDXUFywUs01ja
Y0pRdjt/B+4Az/4B12Nh7zt36/sAAAAASUVORK5CYII=
ENDOFPNG

=pod

---++ Class Method logoSmall()

Returns the URL for the TWiki small (34x26) logo (png).

=cut

sub logoSmall {
    return "data:image/png;base64,$logo34x26";
}


my $favicon = <<ENDOFICON;
AAABAAEAEBAAAAAAAABoBQAAFgAAACgAAAAQAAAAIAAAAAEACAAAAAAAQAEAAAAAAAAAAAAAAAAA
AAAAAAAAAAAA////AACA/wCoz/8AANj/AFCe/wAARf8A1PD/ADG//wAArP8ANIr/AABi/wC75P8A
KqP/AADC/wAAlf8AOK3/AD6Y/wAAU/8AAHD/AOD3/wDI6P8AqNr/AAC3/wAAof8AAMz/AACK/wAA
eP8AOL7/AABa/wDA6P8AAEv/AABo/wDI4/8AqNX/AADR/wAAx/8AAIX/AACP/wAAvP8AALL/AACc
/wAAp/8AAHz/AKjS/wAAUP8AAF3/AABl/wAAbf8AANT/AAB1/wAAv/8AAJL/AACv/wAAmf8AAKT/
AMjq/wDI5v8AwOb/AKjY/wAAVf8AAFj/AABg/wAAav8AANb/AABy/wAAz/8AAHr/AADJ/wAAxP8A
AIL/AACH/wAAuv8AAIz/AAC0/wAAl/8AAKr/AACf/wDg9v8AyOX/AABv/wAAd/8AAH3/AAB//wAA
wf8AAIT/AACI/wAAuf8AAI3/AACQ/wAAsf8AAJT/AACt/wAAqf8AAJ3/AACl/wAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVVNDMlA/Lz4dPC0fBgAAAElHRisR
BQogCy49EgAAADZbJhpVIQEDEz8vPgAAAAAYKUs0SU8BLFFBMCAAAAAAXTdNNls5ASJTQzITAAAA
AFoJKhgpFQE7R0ZSGwAAAABXSjVdNzgBFiYaJQIAAAAAVCcXCBwHAQwQDVhWAAAAAERFM04BAQEB
AToPWQAAAAAjGSQUAQEBAQEeXksAAAAAADFCREUzSEo1TF9NAAAAAAAEQCMZJA4nFyhcAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAP//AAD//wAAgAMAAIAHAAAADwAAAA8AAAAP
AAAADwAAAA8AAAAPAAAADwAAAA8AAIAPAACAHwAA//8AAP//AAA=
ENDOFICON

=pod

---++ Class Method favicon()

Returns the URL for the TWiki favicon (16x16, x-icon).

=cut

sub favicon {
    return "data:image/x-icon;base64,$favicon";
}


my $warning = <<ENDOFWARNING;
R0lGODlhEAAQAMQAAP///93d3f9aAP/cyf/ezP/Jq/99Nv/Uvf/9/P+OUf+MTv+JSP/i0v+FQv/S
uv/OtP+LS/91Kv97M/+QVP+BPP/Fpf+HRf93Lf/Yw//LrgAAAAAAAAAAAAAAAAAAAAAAACH5BAAA
AAAALAAAAAAQABAAAAVUYCCOZCkCaKqq54pVK9CqVoSsMzoIQoEHqwXv8lPteIIMC5iCCFACyTJF
4EEFj9RMYQXwDFpmtYt0oFoJ5FVAOQMZyKcXeZABJ/G8oGGP+e0mgSIhADs=
ENDOFWARNING

=pod

---++ Class Method iconWarning()

Returns the URL for the warning icon (16x16, gif).

=cut

sub iconWarning {
    return "data:image/gif;base64,$warning";
}


my $info = <<ENDOFINFO;
R0lGODlhEAAQAMQAADOZAP///93d3VmsMI7HcnG4TlKpJ9nsz7zdq4XCZkShFabTkG+3S16vNoC/
YOXy3p/Ph6TRjUmkG/X68zqdCfr9+dvt0t3u1U2mIVCnJAAAAAAAAAAAAAAAAAAAAAAAACH5BAAA
AAAALAAAAAAQABAAAAVRoCCOZCkGaKqqJ+C+sBu0sfMw7ywEMYAEiRwNhjHAdLxXwxJYHIeGxA/y
3L0oikpgUE26CIFDDAm7BAhcodUlQUUK3VdmcoDHe+PTao8y+UkhADs=
ENDOFINFO

=pod

---++ Class Method iconInfo()

Returns the URL for the info icon (16x16, gif).

=cut

sub iconInfo {
    return "data:image/gif;base64,$info";
}
1;
