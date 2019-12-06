var TWikiTiny={twikiVars:null,metaTags:null,tml2html:new Array(),html2tml:new Array(),transformCbs:new Array(),getTWikiVar:function(name){if(TWikiTiny.twikiVars==null){var sets=tinyMCE.activeEditor.getParam("twiki_vars","");TWikiTiny.twikiVars=eval(sets);}
return TWikiTiny.twikiVars[name];},expandVariables:function(url){for(var i in TWikiTiny.twikiVars){url=url.replace('%'+i+'%',TWikiTiny.twikiVars[i],'g');}
return url;},saveEnabled:0,enableSaveButton:function(enabled){var status=enabled?null:"disabled";TWikiTiny.saveEnabled=enabled?1:0;var elm=document.getElementById("save");if(elm){elm.disabled=status;}
elm=document.getElementById("quietsave");if(elm){elm.disabled=status;}
elm=document.getElementById("checkpoint");if(elm){elm.disabled=status;}
elm=document.getElementById("preview");if(elm){elm.style.display='none';elm.disabled=status;}},transform:function(editor,handler,text,onSuccess,onFail){var url=TWikiTiny.getTWikiVar("SCRIPTURL");var suffix=TWikiTiny.getTWikiVar("SCRIPTSUFFIX");if(suffix==null)suffix='';url+="/rest"+suffix+"/WysiwygPlugin/"+handler;var path=TWikiTiny.getTWikiVar("WEB")+'.'+
TWikiTiny.getTWikiVar("TOPIC");tinymce.util.XHR.send({url:url,content_type:"application/x-www-form-urlencoded",type:"POST",data:"nocache="+encodeURIComponent((new Date()).getTime())+
"&topic="+encodeURIComponent(path)+"&text="+
encodeURIComponent(text),async:true,scope:editor,success:onSuccess,error:onFail})},initialisedFromServer:false,removeErasedSpans:function(ed,o){o.content=o.content.replace(/<span[^>]*class=['"][^'">]*WYSIWYG_HIDDENWHITESPACE[^>]+>&nbsp;<\/span>/g,'');},setUpContent:function(editor_id,body,doc){if(TWikiTiny.initialisedFromServer)return;var editor=tinyMCE.getInstanceById(editor_id);TWikiTiny.switchToWYSIWYG(editor);editor.onGetContent.add(TWikiTiny.removeErasedSpans);TWikiTiny.initialisedFromServer=true;},cleanBeforeSave:function(eid,buttonId){var el=document.getElementById(buttonId);if(el==null)return;el.onclick=function(){var editor=tinyMCE.getInstanceById(eid);editor.isNotDirty=true;return true;}},onSubmitHandler:false,switchToRaw:function(editor){var text=editor.getContent();var el=document.getElementById("twikiTinyMcePluginWysiwygEditHelp");if(el){el.style.display='none';}
el=document.getElementById("twikiTinyMcePluginRawEditHelp");if(el){el.style.display='block';}
for(var i=0;i<TWikiTiny.html2tml.length;i++){var cb=TWikiTiny.html2tml[i];text=cb.apply(editor,[editor,text]);}
TWikiTiny.enableSaveButton(false);editor.getElement().value="Please wait... retrieving page from server.";TWikiTiny.transform(editor,"html2tml",text,function(text,req,o){this.getElement().value=text;TWikiTiny.enableSaveButton(true);for(var i=0;i<TWikiTiny.transformCbs.length;i++){var cb=TWikiTiny.transformCbs[i];cb.apply(editor,[editor,text]);}},function(type,req,o){this.setContent("<div class='twikiAlert'>"+
"There was a problem retrieving "+o.url+": "+type+" "+
req.status+"</div>");});var eid=editor.id;var id=eid+"_2WYSIWYG";var el=document.getElementById(id);if(el){el.style.display="inline";}else{el=document.createElement('INPUT');el.id=id;el.type="button";el.value="WYSIWYG";el.className="twikiButton";var pel=editor.getElement().parentNode;pel.insertBefore(el,editor.getElement());}
el.onclick=function(){var el_help=document.getElementById("twikiTinyMcePluginWysiwygEditHelp");if(el_help){el_help.style.display='block';}
el_help=document.getElementById("twikiTinyMcePluginRawEditHelp");if(el_help){el_help.style.display='none';}
tinyMCE.execCommand("mceToggleEditor",null,eid);TWikiTiny.switchToWYSIWYG(editor);return false;}
var body=document.getElementsByTagName('body')[0];tinymce.DOM.removeClass(body,'twikiHasWysiwyg');editor.getElement().onchange=function(){var editor=tinyMCE.getInstanceById(eid);editor.isNotDirty=false;return true;},this.onSubmitHandler=function(ed,e){editor.initialized=false;};editor.onSubmit.addToTop(this.onSubmitHandler);TWikiTiny.cleanBeforeSave(eid,"save");TWikiTiny.cleanBeforeSave(eid,"quietsave");TWikiTiny.cleanBeforeSave(eid,"checkpoint");TWikiTiny.cleanBeforeSave(eid,"preview");TWikiTiny.cleanBeforeSave(eid,"cancel");},switchToWYSIWYG:function(editor){editor.getElement().onchange=null;var text=editor.getElement().value;if(this.onSubmitHandler){editor.onSubmit.remove(this.onSubmitHandler);this.onSubmitHandler=null;}
TWikiTiny.enableSaveButton(false);var throbberPath=TWikiTiny.getTWikiVar('PUBURLPATH')+'/'+TWikiTiny.getTWikiVar('SYSTEMWEB')+'/'+'TWikiDocGraphics/processing.gif';editor.setContent("<img src='"+throbberPath+"' />");TWikiTiny.transform(editor,"tml2html",text,function(text,req,o){for(var i=0;i<TWikiTiny.tml2html.length;i++){var cb=TWikiTiny.tml2html[i];text=cb.apply(this,[this,text]);}
if(this.plugins.wordcount!==undefined&&this.plugins.wordcount.block!==undefined){this.plugins.wordcount.block=0;}
this.setContent(text);this.isNotDirty=true;TWikiTiny.enableSaveButton(true);var id=editor.id+"_2WYSIWYG";var el=document.getElementById(id);if(el){el.style.display="none";var body=document.getElementsByTagName('body')[0];tinymce.DOM.addClass(body,'twikiHasWysiwyg');}
for(var i=0;i<TWikiTiny.transformCbs.length;i++){var cb=TWikiTiny.transformCbs[i];cb.apply(editor,[editor,text]);}},function(type,req,o){this.setContent("<div class='twikiAlert'>"+
"There was a problem retrieving "+o.url+": "+type+
" "+req.status+"</div>");});},saveCallback:function(editor_id,html,body){var editor=tinyMCE.getInstanceById(editor_id);for(var i=0;i<TWikiTiny.html2tml.length;i++){var cb=TWikiTiny.html2tml[i];html=cb.apply(editor,[editor,html]);}
var secret_id=tinyMCE.activeEditor.getParam('twiki_secret_id');if(secret_id!=null&&html.indexOf('<!--'+secret_id+'-->')==-1){html='<!--'+secret_id+'-->'+html;}
return html;},convertLink:function(url,node,onSave){if(onSave==null)onSave=false;var orig=url;var pubUrl=TWikiTiny.getTWikiVar("PUBURL");var vsu=TWikiTiny.getTWikiVar("VIEWSCRIPTURL");url=TWikiTiny.expandVariables(url);if(onSave){if((url.indexOf(pubUrl+'/')!=0)&&(url.indexOf(vsu+'/')==0)){url=url.substr(vsu.length+1);url=url.replace(/\/+/g,'.');if(url.indexOf(TWikiTiny.getTWikiVar('WEB')+'.')==0){url=url.substr(TWikiTiny.getTWikiVar('WEB').length+1);}}}else{if(url.indexOf('/')==-1){var match=/^((?:\w+\.)*)(\w+)$/.exec(url);if(match!=null){var web=match[1];var topic=match[2];if(web==null||web.length==0){web=TWikiTiny.getTWikiVar("WEB");}
web=web.replace(/\.+/g,'/');web=web.replace(/\/+$/,'');url=vsu+'/'+web+'/'+topic;}}}
return url;},convertPubURL:function(url){url=TWikiTiny.expandVariables(url);if(url.indexOf('/')==-1){var base=TWikiTiny.getTWikiVar("PUBURL")+'/'+
TWikiTiny.getTWikiVar("WEB")+'/'+
TWikiTiny.getTWikiVar("TOPIC")+'/';url=base+url;}
return url;},getMetaTag:function(inKey){if(TWikiTiny.metaTags==null||TWikiTiny.metaTags.length==0){var head=document.getElementsByTagName("META");head=head[0].parentNode.childNodes;TWikiTiny.metaTags=new Array();for(var i=0;i<head.length;i++){if(head[i].tagName!=null&&head[i].tagName.toUpperCase()=='META'){TWikiTiny.metaTags[head[i].name]=head[i].content;}}}
return TWikiTiny.metaTags[inKey];},install:function(){if(TWikiTiny.init){tinyMCE.init(TWikiTiny.init);tinyMCE.each(tinyMCE.explode(TWikiTiny.init.plugins),function(p){if(p.charAt(0)=='-'){p=p.substr(1,p.length);var url=TWikiTiny.init.twiki_plugin_urls[p];if(url)
tinyMCE.PluginManager.load(p,url);}});}else{alert('Unable to install TinyMCE: could not read "TINYMCEPLUGIN_INIT" from TWikiTiny.init');}},getTopicPath:function(){return this.getTWikiVar("WEB")+'.'+this.getTWikiVar("TOPIC");},getScriptURL:function(script){var scripturl=this.getTWikiVar("SCRIPTURL");var suffix=this.getTWikiVar("SCRIPTSUFFIX");if(suffix==null)suffix='';return scripturl+"/"+script+suffix;},getRESTURL:function(fn){return this.getScriptURL('rest')+"/WysiwygPlugin/"+fn;},getListOfAttachments:function(onSuccess){var url=this.getRESTURL('attachments');var path=this.getTopicPath();var params="nocache="+
encodeURIComponent((new Date()).getTime())+"&topic="+
encodeURIComponent(path);tinymce.util.XHR.send({url:url+"?"+params,type:"POST",content_type:"application/x-www-form-urlencoded",data:params,success:function(atts){if(atts!=null){onSuccess(eval(atts));}}});}};