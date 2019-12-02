#!/usr/bin/env bash

set -Eeo pipefail
perl -MCPAN -e shell <<EOF
o conf make_arg -I /code/twiki/twiki/lib/CPAN
o conf make_install_arg -I /code/twiki/twiki/lib/CPAN
o conf makepl_arg "install_base= /code/twiki/twiki/lib/CPAN LIB= /code/twiki/twiki/lib/CPAN/lib INSTALLPRIVLIB= /code/twiki/twiki/lib/CPAN/lib INSTALLARCHLIB= /code/twiki/twiki/lib/CPAN/lib/arch INSTALLSITEARCH= /code/twiki/twiki/lib/CPAN/lib/arch INSTALLSITELIB= /code/twiki/twiki/lib/CPAN/lib INSTALLSCRIPT= /code/twiki/twiki/lib/CPAN/bin INSTALLBIN= /code/twiki/twiki/lib/CPAN/bin INSTALLSITEBIN= /code/twiki/twiki/lib/CPAN/bin INSTALLMAN1DIR= /code/twiki/twiki/lib/CPAN/man/man1 INSTALLSITEMAN1DIR= /code/twiki/twiki/lib/CPAN/man/man1 INSTALLMAN3DIR= /code/twiki/twiki/lib/CPAN/man/man3 INSTALLSITEMAN3DIR= /code/twiki/twiki/lib/CPAN/man/man3"
o conf commit
q
EOF

export PERL5LIB=/code/twiki/twiki/lib/CPAN/lib

perl -MCPAN -e shell <<EOF
install CGI::Session
install FreezeThaw
install GD
EOF
