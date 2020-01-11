/*
  Copyright (C) 2007-2015 TWiki Contributors http://twiki.org
  Copyright (C) 2007 Crawford Currie http://wikiring.com and Arthur Clemens
  Copyright (C) 2010 Foswiki Contributors http://foswiki.org
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

// The TWikiTiny class object
var TWikiTiny = {

    twikiVars: null,
    metaTags: null,

    tml2html: new Array(),
    // callbacks, attached in plugins
    html2tml: new Array(),
    // callbacks, attached in plugins
    transformCbs: new Array(),
    // callbacks, attached in plugins
    // Get a TWiki variable from the set passed
    getTWikiVar: function(name) {
        if (TWikiTiny.twikiVars == null) {
            var sets = tinyMCE.activeEditor.getParam("twiki_vars", "");
            TWikiTiny.twikiVars = eval(sets);
        }
        return TWikiTiny.twikiVars[name];
    },

    expandVariables: function(url) {
        for (var i in TWikiTiny.twikiVars) {
            url = url.replace('%' + i + '%', TWikiTiny.twikiVars[i], 'g');
        }
        return url;
    },

    saveEnabled: 0,
    enableSaveButton: function(enabled) {
        var status = enabled ? null : "disabled";
        TWikiTiny.saveEnabled = enabled ? 1 : 0;
        var elm = document.getElementById("save");
        if (elm) {
            elm.disabled = status;
        }
        elm = document.getElementById("quietsave");
        if (elm) {
            elm.disabled = status;
        }
        elm = document.getElementById("checkpoint");
        if (elm) {
            elm.disabled = status;
        }
        elm = document.getElementById("preview");
        if (elm) {
            elm.style.display = 'none'; // Item5263: broken preview
            elm.disabled = status;
        }
    },

    transform: function(editor, handler, text, onSuccess, onFail) {
        // Work out the rest URL from the location
        var url = TWikiTiny.getTWikiVar("SCRIPTURL");
        var suffix = TWikiTiny.getTWikiVar("SCRIPTSUFFIX");
        if (suffix == null) suffix = '';
        url += "/rest" + suffix + "/WysiwygPlugin/" + handler;
        var path = TWikiTiny.getTWikiVar("WEB") + '.' + 
            TWikiTiny.getTWikiVar("TOPIC");

        tinymce.util.XHR.send({
            url: url,
            content_type: "application/x-www-form-urlencoded",
            type: "POST",
            data: "nocache=" + encodeURIComponent((new Date()).getTime()) +
                  "&topic=" + encodeURIComponent(path) + "&text=" +
                  encodeURIComponent(text),
            async: true,
            scope: editor,
            success: onSuccess,
            error: onFail
        })
    },

    initialisedFromServer: false,

    removeErasedSpans: function(ed, o) {
        // forced_root_block makes TMCE insert &nbsp; into empty spans.
        // TML2HTML emits spans with the WYSIWYG_HIDDENWHITESPACE class
        // that contain a single space.
        // Some browsers (e.g. IE8 and Opera 10.60) remove the span if
        // the user deletes the space within the span.
        // Other browsers (e.g. various versions of Firefox) do not.
        //
        // This function removes spans with this class that contain
        // only a &nbsp; as the &nbsp; is assumed to come from the
        // forced_root_block code.
        o.content = o.content.replace(/<span[^>]*class=['"][^'">]*WYSIWYG_HIDDENWHITESPACE[^>]+>&nbsp;<\/span>/g, '');
    },

    // Set up content for the initial edit
    setUpContent: function(editor_id, body, doc) {
        // If we haven't done it before, then transform from TML
        // to HTML. We need this test so that pressing the 'back'
        // button from a failed save doesn't banjax the old content.
        if (TWikiTiny.initialisedFromServer) return;
        var editor = tinyMCE.getInstanceById(editor_id);
        TWikiTiny.switchToWYSIWYG(editor);

        // Also add the handler for cleaning up after force_root_blocks
        editor.onGetContent.add(TWikiTiny.removeErasedSpans);
        TWikiTiny.initialisedFromServer = true;
    },

    cleanBeforeSave: function(eid, buttonId) {
        var el = document.getElementById(buttonId);
        if (el == null) return;
        // SMELL: what if there is already an onclick handler?
        el.onclick = function() {
            var editor = tinyMCE.getInstanceById(eid);
            editor.isNotDirty = true;
            return true;
        }
    },

    onSubmitHandler: false,

    // Convert HTML content to textarea. Called from the WYSIWYG->raw switch
    switchToRaw: function(editor) {
        var text = editor.getContent();

        // Make the raw-edit help visible (still subject to toggle)
        var el = document.getElementById("twikiTinyMcePluginWysiwygEditHelp");
        if (el) {
            el.style.display = 'none';
        }
        el = document.getElementById("twikiTinyMcePluginRawEditHelp");
        if (el) {
            el.style.display = 'block';
        }

        // Evaluate post-processors attached from plugins
        for (var i = 0; i < TWikiTiny.html2tml.length; i++) {
            var cb = TWikiTiny.html2tml[i];
            text = cb.apply(editor, [editor, text]);
        }
        TWikiTiny.enableSaveButton(false);

        editor.getElement().value = "Please wait... retrieving page from server.";
        TWikiTiny.transform(
        editor, "html2tml", text, function(text, req, o) {
            this.getElement().value = text;
            TWikiTiny.enableSaveButton(true);
            // Call post-transform callbacks attached from plugins
			for (var i = 0; i < TWikiTiny.transformCbs.length; i++) {
				var cb = TWikiTiny.transformCbs[i];
				cb.apply(editor, [editor, text]);
			}
        },
        function(type, req, o) {
            this.setContent("<div class='twikiAlert'>" + 
                "There was a problem retrieving " + o.url + ": " + type + " " +
                req.status + "</div>");
            //TWikiTiny.enableSaveButton(true); leave save disabled
        });
        // Add the button for the switch back to WYSIWYG mode
        var eid = editor.id;
        var id = eid + "_2WYSIWYG";
        var el = document.getElementById(id);
        if (el) {
            // exists, unhide it
            el.style.display = "inline";
        } else {
            // does not exist, create it
            el = document.createElement('INPUT');
            el.id = id;
            el.type = "button";
            el.value = "WYSIWYG";
            el.className = "twikiButton";
            
			// Need to insert after to avoid knackering 'back'
			var pel = editor.getElement().parentNode;
			pel.insertBefore(el, editor.getElement());
        }
		el.onclick = function() {
			// Make the wysiwyg help visible (still subject to toggle)
			var el_help = document.getElementById(
					"twikiTinyMcePluginWysiwygEditHelp");
			if (el_help) {
				el_help.style.display = 'block';
			}
			el_help = document.getElementById("twikiTinyMcePluginRawEditHelp");
			if (el_help) {
				el_help.style.display = 'none';
			}
			tinyMCE.execCommand("mceToggleEditor", null, eid);
			TWikiTiny.switchToWYSIWYG(editor);
			return false;
		}

		// remove class 'twikiHasWysiwyg' to make non-wysiwyg controls visible 
		var body = document.getElementsByTagName('body')[0];
		tinymce.DOM.removeClass(body, 'twikiHasWysiwyg');

        // SMELL: what if there is already an onchange handler?
        editor.getElement().onchange = function() {
            var editor = tinyMCE.getInstanceById(eid);
            editor.isNotDirty = false;
            return true;
        },
        // Ooo-err. Stomp on the default submit handler and
        // forcibly disable the editor to prevent a call to
        // the TMCE save. This in turn blocks the getContent
        // that would otherwise wipe out the content of the
        // textarea with the DOM. We'd better make damn sure we
        // remove this handler when we switch back!
        this.onSubmitHandler = function(ed, e) {
            // SMELL: Editor.initialized is undocumented and liable
            // to break when we upgrade TMCE
            editor.initialized = false;
        };
        // SMELL: Event.addToTop() is undocumented and liable
        // to break when we upgrade TMCE
        editor.onSubmit.addToTop(this.onSubmitHandler);
        // Make the save buttons mark the text as not-dirty 
        // to avoid the popup that says "Are you sure? The changes you have
        // made will be lost"
        TWikiTiny.cleanBeforeSave(eid, "save");
        TWikiTiny.cleanBeforeSave(eid, "quietsave");
        TWikiTiny.cleanBeforeSave(eid, "checkpoint");
        // preview shouldn't get the popup either, when preview is enabled one
        // day
        TWikiTiny.cleanBeforeSave(eid, "preview");
        // cancel shouldn't get the popup because the user just *said* they
        // want to cancel
        TWikiTiny.cleanBeforeSave(eid, "cancel");
    },

    // Convert textarea content to HTML. This is invoked from the content
    // setup handler, and also from the raw->WYSIWYG switch
    switchToWYSIWYG: function(editor) {
        // Kill the change handler to avoid excess fires
        editor.getElement().onchange = null;

        // Get the textarea content
        var text = editor.getElement().value;

        if (this.onSubmitHandler) {
            editor.onSubmit.remove(this.onSubmitHandler);
            this.onSubmitHandler = null;
        }
        TWikiTiny.enableSaveButton(false);
        
		var throbberPath = TWikiTiny.getTWikiVar('PUBURLPATH') + '/' + TWikiTiny.getTWikiVar('SYSTEMWEB') + '/' + 'TWikiDocGraphics/processing.gif';
        editor.setContent("<img src='" + throbberPath + "' />");
        
        TWikiTiny.transform(
        editor, "tml2html", text, function(text, req, o) { // Success
            // Evaluate any registered pre-processors
            for (var i = 0; i < TWikiTiny.tml2html.length; i++) {
                var cb = TWikiTiny.tml2html[i];
                text = cb.apply(this, [this, text]);
            }
            /* SMELL: Work-around for Item2270. In future this plugin may
                   be updated so that this needs to be changed. TMCE's wordcount
                   plugin limits itself to a max. of one count per
                   2 seconds, so users always see a wordcount of 6 (Please
                   wait... retrieving page from server) when they first edit a
                   document. So remove lock before setContent() */
            if (this.plugins.wordcount !== undefined && 
                this.plugins.wordcount.block !== undefined) {
                this.plugins.wordcount.block = 0;
            }
            this.setContent(text);
            this.isNotDirty = true;
            TWikiTiny.enableSaveButton(true);
            
            // Hide the conversion button, if it exists
			var id = editor.id + "_2WYSIWYG";
			var el = document.getElementById(id);
			if (el) {
				// exists, hide it
				el.style.display = "none";
				
				// and show controls
				var body = document.getElementsByTagName('body')[0];
				tinymce.DOM.addClass(body, 'twikiHasWysiwyg');
			}
			
            // Call post-transform callbacks attached from plugins
			for (var i = 0; i < TWikiTiny.transformCbs.length; i++) {
				var cb = TWikiTiny.transformCbs[i];
				cb.apply(editor, [editor, text]);
			}
        },
        function(type, req, o) {
            // Handle a failure
            this.setContent("<div class='twikiAlert'>" + 
                    "There was a problem retrieving " + o.url + ": " + type + 
                    " " + req.status + "</div>");
            //TWikiTiny.enableSaveButton(true); leave save disabled
        }); 
    },

    // Callback on save. Make sure the WYSIWYG flag ID is there.
    saveCallback: function(editor_id, html, body) {
        // Evaluate any registered post-processors
        var editor = tinyMCE.getInstanceById(editor_id);
        for (var i = 0; i < TWikiTiny.html2tml.length; i++) {
            var cb = TWikiTiny.html2tml[i];
            html = cb.apply(editor, [editor, html]);
        }
        var secret_id = tinyMCE.activeEditor.getParam('twiki_secret_id');
        if (secret_id != null && 
                html.indexOf('<!--' + secret_id + '-->') == -1) {
            // Something ate the ID. Probably IE. Add it back.
            html = '<!--' + secret_id + '-->' + html;
        }
        return html;
    },

    // Called 
    // Called on URL insertion, but not on image sources. Expand TWiki
    // variables in the url.
    convertLink: function(url, node, onSave) {
        if (onSave == null) onSave = false;
        var orig = url;
        var pubUrl = TWikiTiny.getTWikiVar("PUBURL");
        var vsu = TWikiTiny.getTWikiVar("VIEWSCRIPTURL");
        url = TWikiTiny.expandVariables(url);
        if (onSave) {
            if ((url.indexOf(pubUrl + '/') != 0) && 
                    (url.indexOf(vsu + '/') == 0)) {
                url = url.substr(vsu.length + 1);
                url = url.replace(/\/+/g, '.');
                if (url.indexOf(TWikiTiny.getTWikiVar('WEB') + '.') == 0) {
                    url =
                        url.substr(TWikiTiny.getTWikiVar('WEB').length + 1);
                }
            }
        } else {
            if (url.indexOf('/') == -1) {
                // if it's a wikiword, make a suitable link
                var match = /^((?:\w+\.)*)(\w+)$/.exec(url);
                if (match != null) {
                    var web = match[1];
                    var topic = match[2];
                    if (web == null || web.length == 0) {
                        web = TWikiTiny.getTWikiVar("WEB");
                    }
                    web = web.replace(/\.+/g, '/');
                    web = web.replace(/\/+$/, '');
                    url = vsu + '/' + web + '/' + topic;
                }
            }
        }
        return url;
    },

    // Called from Insert Image, when the image is inserted. The resultant
    // URL is only used when displaying the image in the picture dialog. It
    // is thrown away (reverts to the typed address) when the image is
    // actually inserted, at which time convertLink is called.
    convertPubURL: function(url) {
        url = TWikiTiny.expandVariables(url);
        if (url.indexOf('/') == -1) {
            var base = TWikiTiny.getTWikiVar("PUBURL") + '/' + 
                TWikiTiny.getTWikiVar("WEB") + '/' + 
                TWikiTiny.getTWikiVar("TOPIC") + '/';
            url = base + url;
        }
        return url;
    },

    getMetaTag: function(inKey) {
        if (TWikiTiny.metaTags == null || TWikiTiny.metaTags.length == 0) {
            // Do this the brute-force way because of the Firefox problem
            // seen sporadically on Bugs where the DOM appears complete, but
            // the META tags are not all found by getElementsByTagName
            var head = document.getElementsByTagName("META");
            head = head[0].parentNode.childNodes;
            TWikiTiny.metaTags = new Array();
            for (var i = 0; i < head.length; i++) {
                if (head[i].tagName != null && 
                        head[i].tagName.toUpperCase() == 'META') {
                    TWikiTiny.metaTags[head[i].name] = head[i].content;
                }
            }
        }
        return TWikiTiny.metaTags[inKey];
    },

    install: function() {
        // find the TINYMCEPLUGIN_INIT preference
        if (TWikiTiny.init) {
            tinyMCE.init(TWikiTiny.init);
	    // Load plugins
	    tinyMCE.each(tinyMCE.explode(TWikiTiny.init.plugins), function(p) {
		if (p.charAt(0) == '-') {
		    p = p.substr(1, p.length);
		    var url = TWikiTiny.init.twiki_plugin_urls[p];
		    if (url)
			tinyMCE.PluginManager.load(p, url);
		}
	    });
        } else {
            alert(
'Unable to install TinyMCE: could not read "TINYMCEPLUGIN_INIT" from TWikiTiny.init');
        }
    },

    getTopicPath: function() {
        return this.getTWikiVar("WEB") + '.' + this.getTWikiVar("TOPIC");
    },

    getScriptURL: function(script) {
        var scripturl = this.getTWikiVar("SCRIPTURL");
        var suffix = this.getTWikiVar("SCRIPTSUFFIX");
        if (suffix == null) suffix = '';
        return scripturl + "/" + script + suffix;
    },

    getRESTURL: function(fn) {
        return this.getScriptURL('rest') + "/WysiwygPlugin/" + fn;
    },

    getListOfAttachments: function(onSuccess) {
        var url = this.getRESTURL('attachments');
        var path = this.getTopicPath();
        var params = "nocache=" + 
            encodeURIComponent((new Date()).getTime()) + "&topic=" +
            encodeURIComponent(path);

        tinymce.util.XHR.send({
            url: url + "?" + params,
            type: "POST",
            content_type: "application/x-www-form-urlencoded",
            data: params,
            success: function(atts) {
                if (atts != null) {
                    onSuccess(eval(atts));
                }
            }
        });
    }
};
