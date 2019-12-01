# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2004-2018 Peter Thoeny, peter[at]thoeny.org and
# TWiki Contributors. All Rights Reserved. TWiki Contributors are
# listed in the AUTHORS file in the root of this distribution.
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
#
# Replacement for pushTopicContext in older TWikis. Does the
# minimum needed by MailerContrib.

sub TWiki::Func::pushTopicContext {
    my( $web, $topic ) = @_;
    my $twiki = $TWiki::Plugins::SESSION;
    my( $web, $topic ) = $twiki->normalizeWebTopicName( @_ );
    my $old = {
        web => $twiki->{webName},
        topic => $twiki->{topicName},
        mark => $twiki->{prefs}->mark() };

    push( @{$twiki->{_FUNC_PREFS_STACK}}, $old );
    $twiki->{webName} = $web;
    $twiki->{topicName} = $topic;
    $twiki->{prefs}->pushWebPreferences( $web );
    $twiki->{prefs}->pushPreferences( $web, $topic, 'TOPIC' );
    $twiki->{prefs}->pushPreferenceValues(
        'SESSION', $twiki->{loginManager}->getSessionValues() );
}

sub TWiki::Func::popTopicContext {
    my $twiki = $TWiki::Plugins::SESSION;
    my $old = pop( @{$twiki->{_FUNC_PREFS_STACK}} );
    $twiki->{prefs}->restore( $old->{mark});
    $twiki->{webName} = $old->{web};
    $twiki->{topicName} = $old->{topic};
}

1;
