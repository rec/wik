# ---+ Extensions
# ---++ TagMePlugin
# **BOOLEAN**
# Store tags under its top level web
$TWiki::cfg{TagMePlugin}{SplitSpace} = 0;
# **BOOLEAN**
# Normalize tag, strip illegal characters, limit length
$TWiki::cfg{TagMePlugin}{NormalizeTagInput} = 0;
# **BOOLEAN**
# Write debug log
$TWiki::cfg{TagMePlugin}{LogAction} = 0;
# **BOOLEAN**
# Show related results only
$TWiki::cfg{TagMePlugin}{AlwaysRefine} = 0;
# **BOOLEAN**
# Make tags user agnostic
$TWiki::cfg{TagMePlugin}{UserAgnostic} = 0;
# **NUMBER**
# Max tag length (default=30)
$TWiki::cfg{TagMePlugin}{TagLenLimit} = 30;
1;
