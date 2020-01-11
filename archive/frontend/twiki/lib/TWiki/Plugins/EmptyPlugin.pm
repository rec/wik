# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2001-2018 TWiki Contributors.
# All Rights Reserved. TWiki Contributors are listed in the AUTHORS
# file in the root of this distribution.
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
# For licensing info read LICENSE file in the TWiki root.

=pod

---+ package EmptyPlugin

This is an empty TWiki plugin. It is a fully defined plugin, but is
disabled by default in a TWiki installation. Use it as a template
for your own plugins; see TWiki.TWikiPlugins for details.

This version of the !EmptyPlugin documents the handlers supported
by revision 1.2 of the Plugins API. See the documentation of =TWiki::Func=
for more information about what this revision number means, and how a
plugin can check it.

__NOTE:__ To interact with TWiki use ONLY the official API functions
in the TWiki::Func module. Do not reference any functions or
variables elsewhere in TWiki, as these are subject to change
without prior warning, and your plugin may suddenly stop
working.

For increased performance, all handlers except initPlugin are commented 
out. Remove the # comments on handlers you need. For efficiency and 
clarity, you should delete the whole of handlers you don't use before 
you release your plugin.

__NOTE:__ When developing a plugin it is important to remember that
TWiki is tolerant of plugins that do not compile. In this case,
the failure will be silent but the plugin will not be available.
See %SYSTEMWEB%.TWikiPlugins#FAILEDPLUGINS for error messages.

__NOTE:__ Defining deprecated handlers will cause the handlers to be 
listed in %SYSTEMWEB%.TWikiPlugins#FAILEDPLUGINS. See
%SYSTEMWEB%.TWikiPlugins#Handlig_deprecated_functions
for information on regarding deprecated handlers that are defined for
compatibility with older TWiki versions.

__NOTE:__ When writing handlers, keep in mind that these may be invoked
on included topics. For example, if a plugin generates links to the current
topic, these need to be generated before the afterCommonTagsHandler is run,
as at that point in the rendering loop we have lost the information that we
the text had been included from another topic.

=cut

# Always use strict to enforce variable scoping
use strict;

# change the package name and $pluginName!!!
package TWiki::Plugins::EmptyPlugin;

# Name of this Plugin, only used in this module
our $pluginName = 'EmptyPlugin';

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version

# $VERSION is referred to by TWiki, and is the only global variable that
# *must* exist in this package. It should always be Rev enclosed in dollar
# signs so that TWiki can determine the checked-in status of the plugin.
# It is used by the build automation tools, so you should leave it alone.
our $VERSION = '$Rev: 30450 (2018-07-16) $';

# This is a free-form string you can use to "name" your own plugin version.
# It is *not* used by the build automation tools, but is reported as part
# of the version number in PLUGINDESCRIPTIONS. Add a release date in ISO
# format (preferred) or a release number such as '1.3'.
our $RELEASE = '2018-07-05';

# One line description, is shown in the %SYSTEMWEB%.TextFormattingRules topic:
our $SHORTDESCRIPTION = 'Empty Plugin used as a template for new Plugins';

# You must set $NO_PREFS_IN_TOPIC to 0 if you want your plugin to use preferences
# stored in the plugin topic. This default is required for compatibility with
# older plugins, but imposes a significant performance penalty, and
# is not recommended. Instead, use $TWiki::cfg entries set in LocalSite.cfg, or
# if you want the users to be able to change settings, then use standard TWiki
# preferences that can be defined in your Main.TWikiPreferences and overridden
# at the web and topic level.
our $NO_PREFS_IN_TOPIC = 1;

# Define other global package variables
our $debug;

=pod

---++ initPlugin($topic, $web, $user, $installWeb) -> $boolean
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$user= - the login name of the user
   * =$installWeb= - the name of the web the plugin is installed in

REQUIRED

Called to initialise the plugin. If everything is OK, should return
a non-zero value. On non-fatal failure, should write a message
using TWiki::Func::writeWarning and return 0. In this case
%FAILEDPLUGINS% will indicate which plugins failed.

In the case of a catastrophic failure that will prevent the whole
installation from working safely, this handler may use 'die', which
will be trapped and reported in the browser.

You may also call =TWiki::Func::registerTagHandler= here to register
a function to handle variables that have standard TWiki syntax - for example,
=%MYVAR{"my param" myarg="My Arg"}%. You can also override internal
TWiki variable handling functions this way, though this practice is unsupported
and highly dangerous!

__Note:__ Please align variables names with the Plugin name, e.g. if 
your Plugin is called FooBarPlugin, name variables FOOBAR and/or 
FOOBARSOMETHING. This avoids namespace issues.

=cut

sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.1 ) {
        TWiki::Func::writeWarning( "Version mismatch between $pluginName and Plugins.pm" );
        return 0;
    }

    # Example code of how to get a preference value, register a variable handler
    # and register a RESTHandler. (remove code you do not need)

    # Set plugin preferences in LocalSite.cfg, like this:
    # $TWiki::cfg{Plugins}{EmptyPlugin}{ExampleSetting} = 1;
    # Always provide a default in case the setting is not defined in
    # LocalSite.cfg. See TWiki.TWikiPlugins for help in adding your plugin
    # configuration to the =configure= interface.
    my $setting = $TWiki::cfg{Plugins}{EmptyPlugin}{ExampleSetting} || 0;
    $debug = $TWiki::cfg{Plugins}{EmptyPlugin}{Debug} || 0;

    # register the _EXAMPLEVAR function to handle %EXAMPLEVAR{...}%
    # This will be called whenever %EXAMPLEVAR% or %EXAMPLEVAR{...}% is
    # seen in the topic text.
    TWiki::Func::registerTagHandler( 'EXAMPLEVAR', \&_EXAMPLEVAR );

    # Allow a sub to be called from the REST interface using the provided alias.
    # To invoke, call /twiki/bin/rest/EmptyPlugin/example.
    TWiki::Func::registerRESTHandler('example', \&_restExample);

    # Plugin correctly initialized
    return 1;
}

# The function used to handle the %EXAMPLEVAR{...}% variable
# You would have one of these for each variable you want to process.
sub _EXAMPLEVAR {
    my($session, $params, $theTopic, $theWeb, $meta, $textRef) = @_;
    # $session  - a reference to the TWiki session object (if you don't know
    #             what this is, just ignore it)
    # $params=  - a reference to a TWiki::Attrs object containing parameters.
    #             This can be used as a simple hash that maps parameter names
    #             to values, with _DEFAULT being the name for the default
    #             parameter.
    # $theTopic - name of the topic in the query
    # $theWeb   - name of the web in the query
    # $meta     - topic meta-data to use while expanding, can be undef (Since TWiki::Plugins::VERSION 1.4)
    # $textRef  - reference to unexpanded topic text, can be undef (Since TWiki::Plugins::VERSION 1.4)

    # Return: the result of processing the variable

    # For example, %EXAMPLEVAR{"to be" or="not to be" that="is the question"}%
    #    $params->{_DEFAULT} will be 'to be'
    #    $params->{or}       will be 'not to be'
    #    $params->{that}     will be 'is the question'

    return 'Cogito ergo sum.';
}

=pod

---++ _restExample($session) -> $text

This is an example of a sub to be called by the =rest= script. The parameter is:
   * =$session= - The TWiki object associated to this session.

Additional parameters can be recovered via de query object in the $session.

For more information, check TWiki:TWiki.TWikiScripts#rest

*Since:* TWiki::Plugins::VERSION 1.1

=cut

sub _restExample {
   #my ($session) = @_;
   return "This is an example of a REST invocation\n\n";
}

=pod

---++ earlyInitPlugin()

This handler is called before any other handler, and before it has been
determined if the plugin is enabled or not. Use it with great care!

If it returns a non-null error string, the plugin will be disabled.

=cut

#sub earlyInitPlugin {
#    return undef;
#}

=pod

---++ initializeUserHandler( $loginName, $url, $pathInfo )
   * =$loginName= - login name recovered from $ENV{REMOTE_USER}
   * =$url= - request url
   * =$pathInfo= - pathinfo from the CGI query
Allows a plugin to set the username. Normally TWiki gets the username
from the login manager. This handler gives you a chance to override the
login manager.

Return the *login* name.

This handler is called very early, immediately after =earlyInitPlugin=.

*Since:* TWiki::Plugins::VERSION = '1.010'

=cut

#sub initializeUserHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $loginName, $url, $pathInfo ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::initializeUserHandler( $_[0], $_[1] )" ) if $debug;
#}

=pod

---++ registrationHandler($web, $wikiName, $loginName )
   * =$web= - the name of the web in the current CGI query
   * =$wikiName= - users wiki name
   * =$loginName= - users login name

Called when a new user registers with this TWiki.

*Since:* TWiki::Plugins::VERSION = '1.010'

=cut

#sub registrationHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $web, $wikiName, $loginName ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::registrationHandler( $_[0], $_[1] )" ) if $debug;
#}

=pod

---++ commonTagsHandler($text, $topic, $web, $included, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$included= - Boolean flag indicating whether the handler is invoked on an included topic
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called by the code that expands %<nop>VARIABLES% syntax in
the topic body and in form fields. It may be called many times while
a topic is being rendered.

For variables with trivial syntax it is far more efficient to use
=TWiki::Func::registerTagHandler= (see =initPlugin=).

Plugins that have to parse the entire topic content should implement
this function. Internal TWiki
variables (and any variables declared using =TWiki::Func::registerTagHandler=)
are expanded _before_, and then again _after_, this function is called
to ensure all %<nop>VARIABLES% are expanded.

__NOTE:__ when this handler is called, &lt;verbatim> blocks have been
removed from the text (though all other blocks such as &lt;pre> and
&lt;noautolink> are still present).

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler. Use the =$meta= object.

*Since:* $TWiki::Plugins::VERSION 1.000

=cut

#sub commonTagsHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web, $included, $meta ) = @_;
#    
#    # If you don't want to be called from nested includes...
#    #   if( $_[3] ) {
#    #   # bail out, handler called from an %INCLUDE{}%
#    #         return;
#    #   }
#
#    TWiki::Func::writeDebug( "- ${pluginName}::commonTagsHandler( $_[2].$_[1] )" ) if $debug;
#
#    # do custom extension rule, like for example:
#    # $_[0] =~ s/%XYZ%/&handleXyz()/ge;
#    # $_[0] =~ s/%XYZ{(.*?)}%/&handleXyz($1)/ge;
#}

=pod

---++ beforeCommonTagsHandler($text, $topic, $web, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is called before TWiki does any expansion of it's own
internal variables. It is designed for use by cache plugins. Note that
when this handler is called, &lt;verbatim> blocks are still present
in the text.

__NOTE__: This handler is called once for each call to
=commonTagsHandler= i.e. it may be called many times during the
rendering of a topic.

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler.

__NOTE:__ This handler is not separately called on included topics.

=cut

#sub beforeCommonTagsHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web, $meta ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::beforeCommonTagsHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ afterCommonTagsHandler($text, $topic, $web, $meta )
   * =$text= - text to be processed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic MAY BE =undef=
This handler is after TWiki has completed expansion of %VARIABLES%.
It is designed for use by cache plugins. Note that when this handler
is called, &lt;verbatim> blocks are present in the text.

__NOTE__: This handler is called once for each call to
=commonTagsHandler= i.e. it may be called many times during the
rendering of a topic.

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler.

=cut

#sub afterCommonTagsHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web, $meta ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::afterCommonTagsHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ preRenderingHandler( $text, \%map )
   * =$text= - text, with the head, verbatim and pre blocks replaced with placeholders
   * =\%removed= - reference to a hash that maps the placeholders to the removed blocks.

Handler called immediately before TWiki syntax structures (such as lists) are
processed, but after all variables have been expanded. Use this handler to 
process special syntax only recognised by your plugin.

Placeholders are text strings constructed using the tag name and a 
sequence number e.g. 'pre1', "verbatim6", "head1" etc. Placeholders are 
inserted into the text inside &lt;!--!marker!--&gt; characters so the 
text will contain &lt;!--!pre1!--&gt; for placeholder pre1.

Each removed block is represented by the block text and the parameters 
passed to the tag (usually empty) e.g. for
<verbatim>
<pre class='slobadob'>
XYZ
</pre>
</verbatim>
the map will contain:
<pre>
$removed->{'pre1'}{text}:   XYZ
$removed->{'pre1'}{params}: class="slobadob"
</pre>
Iterating over blocks for a single tag is easy. For example, to prepend a 
line number to every line of every pre block you might use this code:
<verbatim>
foreach my $placeholder ( keys %$map ) {
    if( $placeholder =~ /^pre/i ) {
       my $n = 1;
       $map->{$placeholder}{text} =~ s/^/$n++/gem;
    }
}
</verbatim>

__NOTE__: This handler is called once for each rendered block of text i.e. 
it may be called several times during the rendering of a topic.

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler.

Since TWiki::Plugins::VERSION = '1.026'

=cut

#sub preRenderingHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    #my( $text, $pMap ) = @_;
#}

=pod

---++ postRenderingHandler( $text )
   * =$text= - the text that has just been rendered. May be modified in place.

__NOTE__: This handler is called once for each rendered block of text i.e. 
it may be called several times during the rendering of a topic.

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler.

Since TWiki::Plugins::VERSION = '1.026'

=cut

#sub postRenderingHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    #my $text = shift;
#}

=pod

---++ viewRedirectHandler($session, $web, $topic)
   * =$session= - the current TWiki session
   * =$web= - the name of the web in the current CGI query
   * =$topic= - the name of the topic in the current CGI query
This handler is called by the view script at the beginning.
As its name suggests, this handler provides a way to redirect a view request
to some other URL.
This handler returns 1 if it did =$session->redirect(...)=.
It returns 0 otherwise.
The plug-in dispatcher calls =viewRedirectHandler()= of enabled plug-ins until
one plug-in's returns 1 or the handlers are exausted.

*Since:* TWiki::Plugins::VERSION = '6.00'

=cut

#sub viewRedirectHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $session, $web $topic, ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::viewRedirectHandler( $_[1].$_[2] )" ) if $debug;
#}

=pod

---++ viewFileRedirectHandler($session, $web, $topic)
   * =$session= - the current TWiki session
   * =$web= - the name of the web in the current CGI query
   * =$topic= - the name of the topic in the current CGI query
This handler is called by the viewfile script at the beginning.
As its name suggests, this handler provides a way to redirect a viewfile request
to some other URL. This is similar to viewRedirectHandler(), needless to say.
This handler returns 1 if it did =$session->redirect(...)=.
It returns 0 otherwise.
The plug-in dispatcher calls =viewFileRedirectHandler()= of enabled plug-ins
until one plug-in's returns 1 or the handlers are exausted.

*Since:* TWiki::Plugins::VERSION = '6.02'

=cut

#sub viewFileRedirectHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $session, $web $topic, ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::viewFileRedirectHandler( $_[1].$_[2] )" ) if $debug;
#}

=pod

---++ beforeEditHandler($text, $topic, $web )
   * =$text= - text that will be edited
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
This handler is called by the edit script just before presenting the edit text
in the edit box. It is called once when the =edit= script is run.

__NOTE__: meta-data may be embedded in the text passed to this handler 
(using %META: tags)

*Since:* TWiki::Plugins::VERSION = '1.010'

=cut

#sub beforeEditHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::beforeEditHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ afterEditHandler($text, $topic, $web, $meta )
   * =$text= - text that is being previewed
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data for the topic.
This handler is called by the preview script just before presenting the text.
It is called once when the =preview= script is run.

__NOTE:__ this handler is _not_ called unless the text is previewed.

__NOTE:__ meta-data is _not_ embedded in the text passed to this
handler. Use the =$meta= object.

*Since:* $TWiki::Plugins::VERSION 1.010

=cut

#sub afterEditHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::afterEditHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ beforeSaveHandler($text, $topic, $web, $meta )
   * =$text= - text _with embedded meta-data tags_
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - the metadata of the topic being saved, represented by a TWiki::Meta object.

This handler is called each time a topic is saved.

__NOTE:__ meta-data is embedded in =$text= (using %META: tags). If you modify
the =$meta= object, then it will override any changes to the meta-data
embedded in the text. Modify *either* the META in the text *or* the =$meta=
object, never both. You are recommended to modify the =$meta= object rather
than the text, as this approach is proof against changes in the embedded
text format.

*Since:* TWiki::Plugins::VERSION = '1.010'

=cut

#sub beforeSaveHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::beforeSaveHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ afterSaveHandler($text, $topic, $web, $error, $meta )
   * =$text= - the text of the topic _excluding meta-data tags_
     (see beforeSaveHandler)
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$error= - any error string returned by the save.
   * =$meta= - the metadata of the saved topic, represented by a TWiki::Meta object 

This handler is called each time a topic is saved.

__NOTE:__ meta-data is embedded in $text (using %META: tags)

*Since:* TWiki::Plugins::VERSION 1.025

=cut

#sub afterSaveHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $text, $topic, $web, $error, $meta ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::afterSaveHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ afterRenameHandler( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment )

   * =$oldWeb= - name of old web
   * =$oldTopic= - name of old topic (empty string if web rename)
   * =$oldAttachment= - name of old attachment (empty string if web or topic rename)
   * =$newWeb= - name of new web
   * =$newTopic= - name of new topic (empty string if web rename)
   * =$newAttachment= - name of new attachment (empty string if web or topic rename)

This handler is called just after the rename/move/delete action of a web, topic or attachment.

*Since:* TWiki::Plugins::VERSION = '1.11'

=cut

#sub afterRenameHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::afterRenameHandler( " .
#                             "$_[0].$_[1] $_[2] -> $_[3].$_[4] $_[5] )" ) if $debug;
#}

=pod

---++ beforeAttachmentSaveHandler(\%attrHash, $topic, $web, $meta )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$meta= - meta-data object for the topic (since TWiki::Plugins::VERSION 1.4)

This handler is called once when an attachment is uploaded. When this
handler is called, the attachment has *not* been recorded in the database.

The attributes hash will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id
   * =tmpFilename= - name of a temporary file containing the attachment data

*Since:* TWiki::Plugins::VERSION = 1.025

=cut

#sub beforeAttachmentSaveHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ###   my( $attrHashRef, $topic, $web, $meta ) = @_;
#    TWiki::Func::writeDebug( "- ${pluginName}::beforeAttachmentSaveHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ afterAttachmentSaveHandler(\%attrHash, $topic, $web, $error, $meta )
   * =\%attrHash= - reference to hash of attachment attribute values
   * =$topic= - the name of the topic in the current CGI query
   * =$web= - the name of the web in the current CGI query
   * =$error= - any error string generated during the save process
   * =$meta= - meta-data object for the topic (since TWiki::Plugins::VERSION 1.4)

This handler is called just after the save action. The attributes hash
will include at least the following attributes:
   * =attachment= => the attachment name
   * =comment= - the comment
   * =user= - the user id

*Since:* TWiki::Plugins::VERSION = 1.025

=cut

#sub afterAttachmentSaveHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ###   my( $attrHashRef, $topic, $web, $error, $meta ) = @_;
#    TWiki::Func::writeDebug( "- ${pluginName}::afterAttachmentSaveHandler( $_[2].$_[1] )" ) if $debug;
#}

=pod

---++ mergeHandler( $diff, $old, $new, \%info ) -> $text
Try to resolve a difference encountered during merge. The =differences= 
array is an array of hash references, where each hash contains the 
following fields:
   * =$diff= => one of the characters '+', '-', 'c' or ' '.
      * '+' - =new= contains text inserted in the new version
      * '-' - =old= contains text deleted from the old version
      * 'c' - =old= contains text from the old version, and =new= text
        from the version being saved
      * ' ' - =new= contains text common to both versions, or the change
        only involved whitespace
   * =$old= => text from version currently saved
   * =$new= => text from version being saved
   * =\%info= is a reference to the form field description { name, title,
     type, size, value, tooltip, attributes, referenced }. It must _not_
     be wrtten to. This parameter will be undef when merging the body
     text of the topic.

Plugins should try to resolve differences and return the merged text. 
For example, a radio button field where we have 
={ diff=>'c', old=>'Leafy', new=>'Barky' }= might be resolved as 
='Treelike'=. If the plugin cannot resolve a difference it should return 
undef.

The merge handler will be called several times during a save; once for 
each difference that needs resolution.

If any merges are left unresolved after all plugins have been given a 
chance to intercede, the following algorithm is used to decide how to 
merge the data:
   1 =new= is taken for all =radio=, =checkbox= and =select= fields to 
     resolve 'c' conflicts
   1 '+' and '-' text is always included in the the body text and text
     fields
   1 =&lt;del>conflict&lt;/del> &lt;ins>markers&lt;/ins>= are used to 
     mark 'c' merges in text fields

The merge handler is called whenever a topic is saved, and a merge is 
required to resolve concurrent edits on a topic.

*Since:* TWiki::Plugins::VERSION = 1.1

=cut

#sub mergeHandler {
#}

=pod

---++ modifyHeaderHandler( \%headers, $query )
   * =\%headers= - reference to a hash of existing header values
   * =$query= - reference to CGI query object
Lets the plugin modify the HTTP headers that will be emitted when a
page is written to the browser. \%headers= will contain the headers
proposed by the core, plus any modifications made by other plugins that also
implement this method that come earlier in the plugins list.
<verbatim>
$headers->{expires} = '+1h';
</verbatim>

Note that this is the HTTP header which is _not_ the same as the HTML
&lt;HEAD&gt; tag. The contents of the &lt;HEAD&gt; tag may be manipulated
using the =TWiki::Func::addToHEAD= method.

*Since:* TWiki::Plugins::VERSION 1.1

=cut

#sub modifyHeaderHandler {
#    my ( $headers, $query ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::modifyHeaderHandler()" ) if $debug;
#}

=pod

---++ redirectCgiQueryHandler($query, $url )
   * =$query= - the CGI query
   * =$url= - the URL to redirect to

This handler can be used to replace TWiki's internal redirect function.

If this handler is defined in more than one plugin, only the handler
in the earliest plugin in the INSTALLEDPLUGINS list will be called. All
the others will be ignored.

*Since:* TWiki::Plugins::VERSION 1.010

=cut

#sub redirectCgiQueryHandler {
#    # do not uncomment, use $_[0], $_[1] instead
#    ### my ( $query, $url ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::redirectCgiQueryHandler( query, $_[1] )" ) if $debug;
#}

=pod

---++ renderFormFieldForEditHandler($name, $type, $size, $value, $attributes, $possibleValues) -> $html

This handler is called before built-in types are considered. It generates 
the HTML text rendering this form field, or false, if the rendering 
should be done by the built-in type handlers.
   * =$name= - name of form field
   * =$type= - type of form field (checkbox, radio etc)
   * =$size= - size of form field
   * =$value= - value held in the form field
   * =$attributes= - attributes of form field 
   * =$possibleValues= - the values defined as options for form field, if
     any. May be a scalar (one legal value) or a ref to an array
     (several legal values)

Return HTML text that renders this field. If false, form rendering
continues by considering the built-in types.

*Since:* TWiki::Plugins::VERSION 1.1

Note that since TWiki-4.2, you can also extend the range of available
types by providing a subclass of =TWiki::Form::FieldDefinition= to implement
the new type (see =TWiki::Plugins.DatePickerPlugin= and
=TWiki::Plugins.RatingContrib= for examples). This is the preferred way to
extend the form field types.

=cut

#sub renderFormFieldForEditHandler {
#}

=pod

---++ renderWikiWordHandler($linkText, $hasExplicitLinkLabel, $web, $topic) -> $linkText
   * =$linkText= - the text for the link i.e. for =[<nop>[Link][blah blah]]=
     it's =blah blah=, for =BlahBlah= it's =BlahBlah=, and for [[Blah Blah]] it's =Blah Blah=.
   * =$hasExplicitLinkLabel= - true if the link is of the form =[<nop>[Link][blah blah]]= (false if it's ==<nop>[Blah]] or =BlahBlah=)
   * =$web=, =$topic= - specify the topic being rendered (only since TWiki 4.2)

Called during rendering, this handler allows the plugin a chance to change
the rendering of labels used for links.

Return the new link text.

*Since:* TWiki::Plugins::VERSION 1.1

=cut

#sub renderWikiWordHandler {
#    my( $linkText, $hasExplicitLinkLabel, $web, $topic ) = @_;
#    return $linkText;
#}

=pod

---++ completePageHandler($html, $httpHeaders)

This handler is called on the ingredients of every page that is
output by the standard TWiki scripts. It is designed primarily for use by
cache and security plugins.
   * =$html= - the body of the page (normally &lt;html>..$lt;/html>)
   * =$httpHeaders= - the HTTP headers. Note that the headers do not contain
     a =Content-length=. That will be computed and added immediately before
     the page is actually written. This is a string, which must end in \n\n.

*Since:* TWiki::Plugins::VERSION 1.2

=cut

#sub completePageHandler {
#    #my($html, $httpHeaders) = @_;
#    # modify $_[0] or $_[1] if you must change the HTML or headers
#}

=pod

---++ topicTitleHandler($session, $web, $topic, $titleRef)
   * =$session= - the current TWiki session
   * =$web= =$topic= - specifies the topic to get the title of
   * =$titleRef= - the reference to which the title is assigned
This handler is called by TWiki::Meta::topicTitle() before doing its own
things.

If the handler determines the topic's title in its own way, the title is
assigned to $$titleRef and the handler return 1.

The plug-in dispatcher calls =topicTitleHandler()= of enabled plug-ins
until one plug-in returns 1 or the handlers are exausted.

*Since:* TWiki::Plugins::VERSION = '6.02'

=cut

#sub topicTitleHandler {
#    # do not uncomment, use $_[0], $_[1]... instead
#    ### my ( $session, $web, $topic, $titleRef ) = @_;
#
#    TWiki::Func::writeDebug( "- ${pluginName}::topicTitleHandler( $_[1].$_[2] )" ) if $debug;
#}

1;
