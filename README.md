git-examine
===========

git-examine is an interactive wrapper for "blame" and "diff" of git.

## Usage

    git-examine [commit] svn-or-git-managed-file

## Requirement

* ruby 2.1
* w3m
* git

## Install

    gem install git-examine

## Run without gem

    git clone https://github.com/akr/git-examine.git
    ruby -Igit-examine/lib git-examine/bin/git-examine git-managed-file


## History

The old version of git-examine was called vcs-ann.
vcs-ann supported svn but git-examine supports only git.

## Author

Tanaka Akira
akr@fsij.org
