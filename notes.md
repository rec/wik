How to run and maintain a Wiki using docker containers
------------------------------------------------------

Introduction
=========

Docker containers are a very convenient way of installing and running programs.
This document distills my experiences in deploying four or five different Wikis
for XR Netherlands.

Two seconds about Docker
===================

A docker container is a description of a computer program running on a specific
operating system.  It's a way to compartmentalize a running computer program
from the specific computer that it's running on, for convenience and better
reliability.

A running system nearly always requires more than one container.  Foswiki, the
wiki we finally chose, will require two containers - one for the wiki, and one
for https encryption.  Most wikis require three, because they need a database
which lives in its own container.  Mediawiki required four, because it needed a
separate container for the visual editor.  Note that I never got that working
reliably...

Running more than one docker is often done with a text description file
called a `docker-compose` file.

[Here's](/wiki/docker-compose.yml) the one we're using for foswiki.  It doesn't
have the https container yet.

Foswiki had the simplest `docker-compose.yml` - for example, Bookstack's [is
here](archive/bookstack.yml).


How to start a wiki for the first time
==========================

All the wikis ha


To start a docker-compose, type `docker-compose up -d` in the directory with the
file.  To stop it
