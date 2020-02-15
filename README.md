# oracle-env-review

Oracle Environment Review - retrieve and aggregate Oracle application data
installed with Universal Installer.

## What is it?

A set of scripts (mostly written in Perl) used to find, identify and extract
information on Oracle application that were installed on a Linux server.

## Why?

At the last job that I worked with Oracle products, all those that were
installed with Universal Installer, which means they were basically an island:
no easy way to extract information about versions, plugins installed and
everything else a sysadmin should known about. Now deploy all those applications
inside a private cloud which used a lot of VM's with a
[cheap copy](https://www.oracle.com/linux/) of Red Hat Linux installed and
having the task to keep all those applications controlled regarding versions and
security patches required.

Finally, on top of that, add the restriction that you don't have root access
(yep, not kidding here) and need to do everything with SSH and
[PowerBroker](https://www.beyondtrust.com/privilege-management/unix-linux),
which basically forces you to use Expect and other tricks to just get a
CLI program output to `STDOUT`.

Since my upper management didn't care a bit of the lack of tools, I wrote this
code myself to take care of the job and now I'm making it available for everyone
interested.

### Why Universal Installer sucks

Besides the fact it is written in Java, which makes it a horribly choice to
run without a X server?

Well, all regarding versions, patches and modules information from an
application are spread over XML files under the directory. Sometimes the
information wasn't even there, so it was required to execute a CLI and read the
output to parse the information.

Each application, even if it is installed on the same server, have it's own
Universal Installer, which doesn't care about other applications installed with
it.

Now, why Oracle didn't ship those same applications packaged as RPM packages
it's beyond me. It sure as hell it would be much easier to fetch and process
that information.

## How it works?

Besides all the workarounds to be able to deal with both PowerBroker and
non-root access, the idea is basically:

1. Connect to all VMs
2. Run all the scripts from `Oracle::EnvReview` package, which in turn will save
all collected data to XML files (one per application) into a shared space (NFS
export).
3. From your own workstation, recover all those XML files with SSH (even on MS
Windows!), finally feeding them to a MongoDB database.
4. Query MongoDB for all that information and create the reports you need.

### How to install

You must make `Oracle::EnvReview` and `Oracle::EnvReview::Application` packages
available on all servers. This might be a problem, but I had success in
compiling a new `perl` with [perlbrew](https://perlbrew.pl/) and all those
modules installed, created a tarball and extract to an NFS server. It was only
a matter to have all the servers mounting the same NFS export on the same mount
point.

You will also to setup `Oracle::EnvReview::Remote` on your workstation and a
MongoDB server running.

#### Why XML

Not really a choice here. I started working with XML because that is what
Universal Installer uses.

Using JSON is probably a better idea.

#### Why MongoDB

All the applications that I had to support had a bunch of different requirements
regarding what details I should know about them. Basically, creating a good
relational database schema for them would be hard and complex.

Using the "schemaless" MongoDB, doing that was much easier. Go fuck yourself
Oracle database!

## The Good and the Bad

### The Good

You might use only pieces of this repository. When it is all about getting the
information out of an Oracle application, you probably won't need to Google
around about how to do it.

You might also wondering how to get around PowerBroker to read a program output.
This is already implemented with a set of named pipes and Expect to workaround
any dialog from it, which makes your life miserable when using SSH.

Usually using Threads with Perl is a bad idea, but in this case you can use
it safely to connect to several servers in parallel, making all the process
to finish faster.

### The Bad

This code might not be "production ready", besides the fact it might be too
customized to work on your own environment.

Also, you might not have the same restrictions that I got, so all the hacks to
around them might be useless for you. Unfortunately, I don't have any intention
to rewrite that code to make it more generic.

Although all packages were written using [Dist::Zilla](http://dzil.org/), none
will be made available on CPAN (at least not by me).

## COPYRIGHT AND LICENSE

This software is copyright (c) 2020 of Alceu Rodrigues de Freitas Junior,
glasswalk3r@yahoo.com.br

This file is part of **oracle-env-review**.

**oracle-env-review** is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

**oracle-env-review** is distributed in the hope that it will be useful, but
**WITHOUT ANY WARRANTY**; without even the implied warranty of
**MERCHANTABILITY** or **FITNESS FOR A PARTICULAR PURPOSE**. See the GNU General
Public License for more details.

You should have received a copy of the GNU General Public License
along with oracle-env-review.  If not, see http://www.gnu.org/licenses/.
