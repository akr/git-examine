git-examine
===========

git-examine is an interactive wrapper for "annotate/blame/praise" and "diff" of svn and git.

## Usage

    git-examine [commit] svn-or-git-managed-file

## Requirement

* ruby 2.1
* w3m
* svn
* git

## Install

    gem install git-examine

## Run without gem

    git clone https://github.com/akr/git-examine.git
    ruby -Igit-examine/lib git-examine/bin/git-examine git-managed-file

## Author

Tanaka Akira
akr@fsij.org
