# How to run and maintain a Wiki using docker containers

## Introduction

Docker containers are a very convenient way of installing, running and deploying
programs.

This document distills my experiences with five or six different Wikis
for XR Netherlands.  It should also extend to any service we want to run.

## What's missing

1. I still don't know how to create a container that does https encryption!
   I know we have this knowledge within XR.

2. I have never tried sending outgoing mail from any of the Wikis because this
   involves having a permanent location.  My guess is that this won't be an
   issue but we'll have to see.

## Two minutes about Docker

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


## How to start a wiki for the first time

It's the same idea for all the wikis:

0. Get logo images
1. Prepare a `docker-compose.yml` for the wiki
2. Start up the containers
3. Configure on the command line
4. Configure the site
5. Test the whole system
6. Save the containers
7. Deploy
8. Set up user accounts

### 0. Get logo icons

You're going to need two logo images - one image can be in any format and should
be 46 pixels high and as wide as you like.  The other is in .ico format - if you
don't have one of those, you can skip that step for now.

Let's suppose the files are `logo.jpg` and `logo.ico`.

### 1.  Prepare a `docker-compose.yml` for the wiki

This would take a document ten times as long as this one to explain, but this
has already been done for a few wikis.

### 2. Start up the containers

Open a the command line, and go to the directory that contains that
`docker-compose.yml`.

Type `docker-compose up -d` in the command line and the wiki starts up!

There's also the idea of "environment variables", but we don't need them to
deploy a production Foswiki, so I put them in Appendix A.

### 3. Configure on the command line

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

    docker exec -it foswiki /bin/bash
    cd /var/www/foswiki
    tools/configure -save -set '{Password}=dont-use-this-password'
    exit

If you are setting up for offsite git backup then you need to do a little more
stuff - see Appendix B.

### 4. Configure the site

#### 4.1 Open the site

Open a browser like Chrome or Firefox.  If you are running docker on your local
machine, type `localhost`;  if you are running it on a server, type the internet
address of the server.

If all has gone well you should see a page saying `Foswiki - Welcome to the Main
web`.

#### 4.2 Log in

Now click in the left hand corner and sign in using the account Admin and the
password that you used in step 3.  If that doesn't work, you can try step 3
again with a different password.

#### 4.3 Configure site preferences

In Foswiki, you edit preferences and settings by editing the settings page as
part of the wiki!  Very neat.

Click on the text link `SitePreferences`, around the middle of the page.

First, we're going to upload the logos!

For each image, click on Attach near the top right.  You get an ugly dialog.
Click on Choose File and then select the file.

Now, turn on the check box marked `Do not show attachment` then click on `Upload
file` and select your image.

Do this once for each image you have.  You can use any names you like, but below
I use `logo.jpg` and `logo.ico`.

Click on Edit Preference toward the middle

Change the following variables:

    * Set WIKILOGOIMG = %PUBURL%/%USERSWEB%/SitePreferences/logo.jpg
    * Set WIKILOGOALT = The name of your site
    * Set WIKITOOLNAME = The name of your site
    * Set FAVICON = %PUBURL%/%USERSWEB%/SitePreferences/logo.ico

Save the page.  You should see the logo in the top left hand corner of the
page.  (You might not see the favicon during testing.)

Now we're going to clean the front page!  First go to the main page by clicking
on the top left hand corner, then click on `More topic actions` in the bottom
right corner.  Scroll down to `Copy topic` then in the box marked `Name of copy`
type `WebUtilities`, then click on `Copy topic...`.  Click save.

Now click on Edit and delete everything above `Web Utilities`, then click on
Save.

Now you get to put in your own text.

Click on the top left hand corner to go back to the main page.  Click on edit,
remove everything except the very first line.


We can do much more - see [here](https://foswiki.org/System/InstantEnhancements).

More, a Foswiki installation is called a _site_ and within it, it has individual
subareas called _webs_ each of which can have a different style, and then each
web is made up of the boring old WikiWords we are so familiar with from
Wikipedia.


### 5. Test the whole system

Visit the site, create a page, make sure it all works.


### 6. Save the containers


### 7. Deploy


### 8. Set up user accounts


## Appendix A: Environment variables

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

### A.1 Passwords

_Passwords_ are just what you think they are.  We need passwords for databases.

If there is a separate database container, the main container and the database
container have to share a password because of course you have to have a password
to log in to the database.  And you can't store the passwords in the
`docker-compose.yml` file because that would be horribly insecure, so they must
be environment variables.

### A.2. Port numbers

You only need to know about port numbers if you are running more than one system
on your server at a time.

A _port_ is just a communication endpoint over the internet and is represented
by the address of a host or server and the _port number_, a number from 1 to
65535.  Two different systems can run on the same server without interfering
with each other if they use different port numbers.  For your experimentation,
you can use any port number 1024 or up - more information is
[here](https://en.wikipedia.org/wiki/Port_\(computer_networking\)).

### A.3. Setting environment variables

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


## Appendix B: Offsite git backup

In fact, we are using continuous git backup - sounds fancy!

Each change to the Wiki becomes a git commit and and you get the ability to
instantly move the Wiki back to any point in time in the past that you like
without losing any of the new data.

You get that for free without any extra setup.

But even better, we can also push each commit to one or more remote servers
which means that you are getting this backup offsite continuously.

But we need to do a bit more setup for that.  This cannot be done automatically
because there are keys and identify involved.

### The goal

We need to get the `git push` command to work in the backup container without a
password.

This means we need to install some sort of authentication _key_ in the backup
container.

The details will depend on who your provider is and what keys you want to use.
I will give instructions for _SSH_ keys and the Microsoft-owned
defense-contractor _Github_, because they are unfortunately whom I am familiar
with.

### 1. Run a terminal on the backup container

    docker exec -it backup /bin/bash

### 2. Generate a new key.

Github's instructions are
[here](https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent).
Make sure you are looking at the Linux instructions and not the ones for the
machine you are working on!

    ssh-keygen -t rsa -b 4096 -C "your@email-here.com"
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa

Keep this terminal open - we're going to come back to it.

### 3. Add the key to your account.

On github, it's https://github.com/settings/keys, (documentation
[here](https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account)).

### 4. Create a new repository on your account.

On Github, it's here: https://github.com/new.  Select "private repository" so no
one else can see it. Do not add a license, a README or anything else.

It's simpler to name it the same as the root directory of your wiki - in our
case, it's `foswiki` - but you can name the private repo anything you like.

The result of this will be some page which contains an address looking like:

    git@github.com:your-name/foswiki.git

and probably a button to copy it to the clipboard!

So copy that address onto your clipboard and proceed...

### 5. Commit the wiki installation.

Go to the root directory of your wiki and execute these commands

    WIKI=the address on your clipboard
    cd /var/www/foswiki
    git init
    git remote add origin $WIKI
    git add .
    git commit -m "First commit"
    git push -u origin master

Congratulations - you've backed up the wiki, and backups will happen
continuously to that account from now on.

To stop backups, open a terminal to the container `backup` and do this:

    cd /var/www/foswiki
    git remote remove origin

To add new backups, add a new remote with a new name - it doesn't have to
be a github account even if you started with one.

    cd /var/www/foswiki
    git remote add somename git@gitwherever.com:someone/foswiki.git

You will have to also add the SSH key you created in step 3 above to this new
account.
