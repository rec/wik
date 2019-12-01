# ---+ Extensions
# ---++ MailerContrib
# Settings for the mailer that sends out topic change notifications.
# **REGEX**
# Define the regular expression that an email address entered in WebNotify
# must match to be identified as a legal email by the notifier. You can use
# this expression to - for example - filter email addresses on your company
# domain, or even block use of raw emails in WebNotify altogether (just make
# it something that will never match, e.g. ='^notAnEmail$'=).
# If this is not defined, then the default setting of
# =[A-Za-z0-9.+-_]+\@[A-Za-z0-9.-]+= is used.
$TWiki::cfg{MailerContrib}{EmailFilterIn} = '';

# **REGEX**
# You may have a special non wikiname notation of users and groups and want
# to use it in WebNotify.
# Assuming you have a custom user mapping handler taking care of that
# notation, you can achieve that by putting the regular expression of that
# notation in the following.
$TWiki::cfg{MailerContrib}{CustomUserGroupNotations} = '';
