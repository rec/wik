# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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

package TWiki::Configure::JS;

use strict;

use vars qw( $js1 $js2 );

sub js1 {
    local $/ = undef;
    $js1 ||= <DATA>;
    return $js1;
}

sub js2 {
    return <<'HERE';
//<!--
document.write("<style type='text/css'>");
document.write(".foldableBlockClosed {display:none;}");
document.write("<\/style>");
//-->
HERE
}

1;
__DATA__
//<!--

var lastOpenBlock = null;
var lastOpenBlockLink = null;
var allBlocks = null; // array of all foldable blocks
var allBlockLinks = null; // array of all foldable block links (headers)

function foldBlock(id) {
    var shouldClose = false;
    var block = null;
    if (lastOpenBlock == null) {
        block = document.getElementById(id);
        if (block.open) {
            shouldClose = true;
        }
    }
    if (shouldClose) {
        closeBlock(id);
    } else {
        var o = openBlock(id);
        if (lastOpenBlock != null) {
            closeBlockElement(lastOpenBlock, lastOpenBlockLink);
        }
    }
    if (o && o.block) {
        lastOpenBlock = (lastOpenBlock == o.block) ? null : o.block;
    }
    if (o && o.blockLink) {
        lastOpenBlockLink = (lastOpenBlockLink == o.blockLink) ? null : o.blockLink;
    }
}

function openBlock(id) {
    var block = document.getElementById(id);
    var blockLink = document.getElementById('blockLink' + id);
    openBlockElement(block, blockLink);
    return {block:block, blockLink:blockLink};
}

function openBlockElement(block, blockLink) {
    block.className = 'foldableBlock foldableBlockOpen';
    block.open = true;
    blockLink.className = 'blockLink blockLinkOn';
}

function closeBlock(id) {
    var block = document.getElementById(id);
    var blockLink = document.getElementById('blockLink' + id);
    closeBlockElement(block, blockLink);
    return {block:block, blockLink:blockLink};
}

function closeBlockElement(block, blockLink) {
    block.className = 'foldableBlock foldableBlockClosed';
    block.open = false;
    blockLink.className = 'blockLink blockLinkOff';
}

function toggleAllOptions(open) {
    if (allBlocks == null) {
        allBlocks = getElementsByClassName('foldableBlock');
    }
    if (allBlockLinks == null) {
        allBlockLinks = getElementsByClassName('blockLink');
    }
    var i, ilen=allBlocks.length;
    if (open) {
        for (i=0; i<ilen; ++i) {
            openBlockElement(allBlocks[i], allBlockLinks[i]);
        }
    } else {
        for (i=0; i<ilen; ++i) {
            closeBlockElement(allBlocks[i], allBlockLinks[i]);
        }
    }
    lastOpenBlock = null;
    lastOpenBlockLink = null;
}

function getElementsByClassName(class_name)
{
    var all_obj, ret_obj = new Array();
    if (document.all)
        all_obj=document.all;
     else if (document.getElementsByTagName && !document.all)
        all_obj=document.getElementsByTagName("*");
    var len = all_obj.length;
    for (i=0;i<len;++i) {
        var myClass = all_obj[i].className;
         if (myClass == class_name) {
            ret_obj.push(all_obj[i]);
        } else {
            var classElems = myClass.split(" ");
            var elemLen = classElems.length;
            for (ii=0; ii<elemLen; ++ii) {
                if (classElems[ii] == class_name) {
                    ret_obj.push(all_obj[i]);
                }
            }    
        }
    }
    return ret_obj;
}
//-->

