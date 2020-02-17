How to run and maintain a Wiki using docker containers
------------------------------------------------------

Introduction
=========

Docker containers are a very convenient way of installing, running and deploying
programs.

This document distills my experiences with five or six different Wikis
for XR Netherlands.  It should also extend to any service we want to run.

What's missing
============

I still don't know how to create a container that does https encryption! I know
we have this knowledge within XR so it should be easily resolved.

Two minutes about Docker
===================

A docker container is a description of a computer program running on a specific
operating system.  It's a way to compartmentalize a running computer program
from the specific computer that it's running on, for convenience and better
reliability.

A running system nearly always requires more than one container.  Foswiki, the
wiki we finally chose, will require two containers - one for the wiki, and one
for https encryption.

Most wikis require three containers, because they need a database
which lives in its own container.

Mediawiki required four, because it needed a separate container for the visual
editor.  And I never got that working reliably...

Running more than one docker is often done with a text description file
called a `docker-compose` file.

For each separate system you want to run, there's a separate directory with a
file called `docker-compose.yml`.  We have directories called `foswiki/`,
`bookstack/`, `wikijs/` and `mediawiki/` for the four Wikis that turned out to
be useful candidates.

[Here's](/foswiki/docker-compose.yml) the one we're using for foswiki.  It
doesn't have the https container yet.  It's the simplest `docker-compose.yml` -
for example, Bookstack's [is here](/bookstack/docker-compose.yml).


How to start a wiki for the first time
==========================

It's the same idea for all the wikis:

1. Prepare a `docker-compose.yml` for the wiki
2. Start up the containers
3. Configure internally
4. Configure externally
5. Test the whole system
6. Save the containers
7. Deploy
8. Set up user accounts

1.  Prepare a `docker-compose.yml` for the wiki
=================================

This would take a document ten times as long as this one to explain, but this
has already been done for a few wikis.

2. Start up the containers
====================

Open a the command line, and go to the directory that contains that
`docker-compose.yml`.

Type `docker-compose up -d` in the command line and the wiki starts up!

There's also the idea of "environment variables", but we don't need them to
deploy a production Foswiki, so I put them in Appendix A.

3. Configure internally
===================

These are internal configuration values that can't be set from the web and
depend entirely on the program you're running.  Usually you need the command
line to achieve this and sometimes the program's website too.

For Foswiki, we only need to set the Wiki administrator password.

(I recommend selecting passwords by picking five or so random words from [one of
these](https://www.google.com/search?q=random+words&rlz=1C5CHFA_enNL800NL800&oq=random+words&aqs=chrome..69i57j0l4j69i60j69i65j69i60.2313j0j7&sourceid=chrome&ie=UTF-8).
Whatever you do, don't use the passwords here!)

From the command line, you will start a bash shell inside the foswiki docker
container, and then from inside that bash shell, you set the password - exactly
like this:

    docker exec -it docker-foswiki /bin/bash
    cd /var/www/foswiki
    tools/configure -save -set {Password}=dont-use-this-password
    exit

4. Configure externally
=======================

Externally means "through the website". The details depend again on the wiki.

A Foswiki installation is called a _site_ and within it, it has individual
subareas called _webs_ each of which can have a different style, and then each
web is made up of the boring old WikiWords we are so familiar with from
Wikipedia.

Log in.

In Foswiki, you need to configure XXX and you go pages.

 5. Test the whole system
=================

TBD




Appendix A: Environment variables
===========================

The simple command `docker-compose up -d` above is complicated only a little by
the idea of _environment variables_ which in our case hold either _port numbers_
or _passwords_.

If you read a `docker-compose.yml` file, environment variables are easy to spot
because they start with `${`. For example, in [this
file](/bookstack/docker-compose.yml) you can see this line:

    image: '${DOCKER_PROVIDER-solidnerd}/bookstack'

This means that `DOCKER_PROVIDER` is an _optional_ environment variable, and if
you don't set it, it gets the value `solidnerd`.

A little later in the same file, you see this:

    DB_PASSWORD: '${DB_USER_PASSWORD:?DB_USER_PASSWORD must be set}'

This means that `DB_USER_PASSWORD` is a _required_ environment variable, and if
you don't set it, you get an error and the program doesn't even start.

**A.1 Passwords**

_Passwords_ are just what you think they are.  We need passwords for databases.

If there is a separate database container, the main container and the database
container have to share a password because of course you have to have a password
to log in to the database.  And you can't store the passwords in the
`docker-compose.yml` file because that would be horribly insecure, so they must
be environment variables.

**A.2. Port numbers**

You only need to know about port numbers if you are running more than one system
on your server at a time.

A _port_ is just a communication endpoint over the internet and is represented
by the address of a host or server and the _port number_, a number from 1 to
65535.  Two different systems can run on the same server without interfering
with each other if they use different port numbers.  For your experimentation,
you can use any port number 1024 or up - more information is
[here](https://en.wikipedia.org/wiki/Port_\(computer_networking\)).

**A.3. Setting environment variables**

There are two different ways to set environment variables while you are starting
up the containers - from the command line, or using a `.env` file.

Let's suppose we need to set both `MEDIAWIKI_PORT=8080` and
`DB_USER_PASSWORD=EbyLepADi+nyEd`.

To add the variables from the command line, it's:

    MEDIAWIKI_PORT=8080 DB_USER_PASSWORD=bad-password docker-compose up -d

Or you can create a text file called `.env` and put these lines into it:

    MEDIAWIKI_PORT=8080
    DB_USER_PASSWORD=bad-password

NOTE: this _only_ works if you are the only one who can see that `.env` file -
otherwise use the command line method.
