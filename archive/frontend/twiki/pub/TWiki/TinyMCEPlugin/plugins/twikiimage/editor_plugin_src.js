/*
  Copyright (C) 2007-2009 Crawford Currie http://c-dot.co.uk
  All Rights Reserved.

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version. For
  more details read LICENSE in the root of the TWiki distribution.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  As per the GPL, removal of this notice is prohibited.
*/
'use strict';
(function () {
    tinymce.PluginManager.requireLangPack('twikiimage');

    tinymce.create('tinymce.plugins.TWikiImage', {

        init: function (ed, url) {

            // Register commands
            ed.addCommand('twikiimage', function () {
                ed.windowManager.open({
                    location: false,
                    menubar: false,
                    toolbar: false,
                    status: false,
                    url: url + '/image.htm',
                    width: 550,
                    height: 400,
                    movable: true,
                    inline: true
                },
                {
                    plugin_url: url,
                    attach_url: TWikiTiny.getTWikiVar("PUBURL") + '/' +
                        TWikiTiny.getTWikiVar("WEB") + '/' +
                        TWikiTiny.getTWikiVar("TOPIC") + '/',
                    vars: ed.getParam("twiki_vars", "")
                });
            });

            // Register buttons
            ed.addButton('image', {
                title: 'twikiimage.image_desc',
                cmd: 'twikiimage'
            });
        },

        getInfo: function () {
            return {
                longname: 'TWiki image',
                author: 'Crawford Currie, from Moxiecode Systems AB original',
                authorurl: 'http://c-dot.co.uk.com',
                infourl: 'http://twiki.org/cgi-bin/view/Plugins/TinyMCEPlugin',
                version: tinyMCE.majorVersion + "." + tinyMCE.minorVersion
            };
        },

        _nodeChange: function (ed, cm, n, co) {
            if (!n) {
                return;
            }

            cm.setActive('twikiimage', ed.dom.getParent(n, 'img'));
        }
    });

    // Register plugin
    tinymce.PluginManager.add('twikiimage', tinymce.plugins.TWikiImage);
})();
