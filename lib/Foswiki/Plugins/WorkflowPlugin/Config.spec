# ---+ Extensions
# ---++ WorkflowPlugin
# **BOOLEAN**
# Enable to get a report on access control decisions printed to the
# Foswiki debug log (usually in working/logs/debug.log)
$Foswiki::cfg{Plugins}{WorkflowPlugin}{Debug} = 0;
# **BOOLEAN**
# Enable this to transfer "Allow Edit" and "Allow View" column entries from the state table into
# Foswiki ACLs (e.g. ALLOWTOPICCHANGE) when a topic is saved. Note that this is experimental
# and is very likely to break compatibility with existing workflows, but does integrate the plugin
# more closely with the rest of Foswiki.
$Foswiki::cfg{Plugins}{WorkflowPlugin}{UpdateFoswikiACLs} = 0;

1;
